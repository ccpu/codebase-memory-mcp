# install.ps1 - Artifact-local installer for codebase-memory-mcp Windows builds.
#
# This installer is packaged into the Windows artifact. It installs the
# codebase-memory-mcp.exe located next to this script. It does not download
# release binaries and does not contact GitHub.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 --configure
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 --dir=C:\Tools\codebase-memory-mcp
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 --no-path

$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\codebase-memory-mcp"
$BinName = "codebase-memory-mcp.exe"
$ConfigureAgents = $false
$NoPath = $false

foreach ($arg in $args) {
    if ($arg -eq "--configure") { $ConfigureAgents = $true }
    if ($arg -eq "--skip-config") { $ConfigureAgents = $false }
    if ($arg -eq "--no-path") { $NoPath = $true }
    if ($arg -like "--dir=*") { $InstallDir = $arg.Substring(6) }
}

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Source = Join-Path $ScriptDir $BinName

if (-not (Test-Path $Source)) {
    Write-Host "error: $BinName was not found next to install.ps1" -ForegroundColor Red
    Write-Host "Extract the zip first, then run install.ps1 from the extracted folder."
    exit 1
}

Write-Host "codebase-memory-mcp artifact installer (Windows)"
Write-Host "  source: $Source"
Write-Host "  target: $InstallDir\$BinName"
Write-Host "  downloads: none"
Write-Host ""

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
$Dest = Join-Path $InstallDir $BinName

$SourceHash = (Get-FileHash -Path $Source -Algorithm SHA256).Hash.ToLowerInvariant()
$AlreadyInstalled = $false
if (Test-Path $Dest) {
    $DestHash = (Get-FileHash -Path $Dest -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($DestHash -eq $SourceHash) {
        $AlreadyInstalled = $true
    }
}

if ($AlreadyInstalled) {
    Write-Host "Already installed: local binary matches artifact SHA-256."
} else {
    $running = Get-Process -Name "codebase-memory-mcp" -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "Stopping running codebase-memory-mcp process(es)..."
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $Dest) {
        $OldDest = "$Dest.old"
        Remove-Item $OldDest -Force -ErrorAction SilentlyContinue
        Rename-Item $Dest $OldDest -ErrorAction SilentlyContinue
    }

    Copy-Item $Source $Dest -Force

    $InstalledHash = (Get-FileHash -Path $Dest -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($InstalledHash -ne $SourceHash) {
        Write-Host "error: installed binary hash mismatch" -ForegroundColor Red
        Write-Host "  source:    $SourceHash"
        Write-Host "  installed: $InstalledHash"
        exit 1
    }
    Write-Host "Installed binary hash verified."
}

try {
    $ver = & $Dest --version 2>&1
    if ($AlreadyInstalled) {
        Write-Host "Current: $ver"
    } else {
        Write-Host "Installed: $ver"
    }
} catch {
    Write-Host "error: installed binary failed to run" -ForegroundColor Red
    exit 1
}

if (-not $NoPath) {
    $UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($UserPath -notlike "*$InstallDir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$UserPath;$InstallDir", "User")
        $env:PATH = "$env:PATH;$InstallDir"
        Write-Host "Added $InstallDir to user PATH"
    }
}

if ($ConfigureAgents) {
    Write-Host ""
    Write-Host "Configuring coding agents..."
    & $Dest install -y 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "error: agent configuration failed (exit code $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "Agent configuration skipped."
    Write-Host "Review first:"
    Write-Host "  `"$Dest`" install --plan"
    Write-Host "  `"$Dest`" install --dry-run"
    Write-Host "Configure later:"
    Write-Host "  `"$Dest`" install"
}

Write-Host ""
Write-Host "Done. Restart your terminal so PATH changes are visible."
