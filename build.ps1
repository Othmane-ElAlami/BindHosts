param(
    [string]$OutputPath,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WebUiDir = Join-Path $RepoRoot "webui"
$ModuleDir = Join-Path $RepoRoot "module"
$ModulePropPath = Join-Path $ModuleDir "module.prop"
$ModuleVersion = (Select-String -Path $ModulePropPath -Pattern '^version=(.+)$').Matches[0].Groups[1].Value
$DefaultZipName = "BindHosts-$ModuleVersion.zip"
$ZipPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
}
elseif ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Join-Path $RepoRoot $DefaultZipName
}
else {
    Join-Path $RepoRoot $OutputPath
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Script
    )

    Write-Host "[+] $Message"
    & $Script
}

if (-not $SkipBuild) {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw "npm is required but was not found in PATH."
    }

    Invoke-Step -Message "Building WebUI into module/webroot" -Script {
        Push-Location $WebUiDir
        try {
            npm exec --yes pnpm@11.8.0 -- install --frozen-lockfile
            if ($LASTEXITCODE -ne 0) { throw "pnpm install failed." }

            npm exec --yes pnpm@11.8.0 -- build
            if ($LASTEXITCODE -ne 0) { throw "pnpm build failed." }
        }
        finally {
            Pop-Location
        }
    }
}

Invoke-Step -Message "Creating flashable ZIP: $ZipPath" -Script {
    if (Test-Path $ZipPath) {
        Remove-Item $ZipPath -Force
    }
    Compress-Archive -Path (Join-Path $ModuleDir "*") -DestinationPath $ZipPath -Force
}

Invoke-Step -Message "Validating ZIP structure" -Script {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $requiredEntries = @(
        "module.prop",
        "action.sh",
        "service.sh",
        "post-fs-data.sh",
        "customize.sh",
        "uninstall.sh",
        "META-INF/com/google/android/updater-script"
    )

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entryNames = $zip.Entries | ForEach-Object { ($_.FullName -replace '\\', '/') }
        $missing = @($requiredEntries | Where-Object { $_ -notin $entryNames })
        if ($missing.Count -gt 0) {
            throw ("ZIP is missing required entries: " + ($missing -join ", "))
        }
    }
    finally {
        $zip.Dispose()
    }
}

$zipInfo = Get-Item $ZipPath
Write-Host "[+] Done"
Write-Host ("[+] Output: {0}" -f $zipInfo.FullName)
Write-Host ("[+] Size: {0} bytes" -f $zipInfo.Length)
