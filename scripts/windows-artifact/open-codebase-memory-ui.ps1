# open-codebase-memory-ui.ps1 - Start the local Codebase Memory UI.
#
# Run from the repo root. It checks the installed binary, uses the repo-local
# cache, starts a visible server window, verifies the local HTTP UI, then opens
# the browser.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\open-codebase-memory-ui.ps1
#   powershell -ExecutionPolicy Bypass -File .\open-codebase-memory-ui.ps1 -Reindex
#   powershell -ExecutionPolicy Bypass -File .\open-codebase-memory-ui.ps1 -Port 9750

[CmdletBinding()]
param(
    [int]$Port = 9749,
    [string]$Project = "",
    [string]$CacheDir = "",
    [string]$Mode = "fast",
    [switch]$Reindex
)

$ErrorActionPreference = "Stop"

function Find-CbmExe {
    $cmd = Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidate = Join-Path $env:LOCALAPPDATA "Programs\codebase-memory-mcp\codebase-memory-mcp.exe"
    if (Test-Path $candidate) { return $candidate }

    throw "codebase-memory-mcp.exe was not found. Run install.ps1 from the windows-exe-ui artifact first."
}

function Normalize-ProjectName {
    param([string]$Value)
    $n = $Value -replace '[^A-Za-z0-9_.-]', '-'
    $n = $n.Trim('-')
    if (-not $n) { return "repo" }
    return $n
}

function Test-Ui {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
        return ($r.StatusCode -eq 200 -and $r.Content -match "Codebase Memory|<script|<html")
    } catch {
        return $false
    }
}

$RepoPath = (Get-Location).Path
if (-not $Project) {
    $Project = Normalize-ProjectName (Split-Path -Leaf $RepoPath)
}
if (-not $CacheDir) {
    $CacheDir = Join-Path $RepoPath ".codebase-memory\cache"
}

New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null

$env:CBM_INDEX_SUPERVISOR = "0"
$env:CBM_CACHE_DIR = $CacheDir

$Exe = Find-CbmExe
$Url = "http://127.0.0.1:$Port/"

Write-Host "Checking installed binary..."
& $Exe --version
if ($LASTEXITCODE -ne 0) {
    throw "codebase-memory-mcp --version failed"
}

if ($Reindex) {
    Write-Host ""
    Write-Host "Reindexing $RepoPath as $Project..."
    & $Exe cli index_repository --repo-path $RepoPath --name $Project --mode $Mode
    if ($LASTEXITCODE -ne 0) {
        throw "index_repository failed with exit code $LASTEXITCODE"
    }
} else {
    Write-Host ""
    Write-Host "Checking index status for $Project..."
    & $Exe cli index_status --project $Project
    if ($LASTEXITCODE -ne 0) {
        Write-Host "No usable index status found. Indexing now..."
        & $Exe cli index_repository --repo-path $RepoPath --name $Project --mode $Mode
        if ($LASTEXITCODE -ne 0) {
            throw "index_repository failed with exit code $LASTEXITCODE"
        }
    }
}

if (-not (Test-Ui $Url)) {
    Write-Host ""
    Write-Host "Starting UI server in a visible PowerShell window..."
    $cmd = "`$env:CBM_INDEX_SUPERVISOR='0'; `$env:CBM_CACHE_DIR='$CacheDir'; & '$Exe' --ui=true --port=$Port"
    Start-Process -FilePath powershell.exe `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit", "-Command", $cmd) `
        -WorkingDirectory $RepoPath `
        -WindowStyle Normal | Out-Null

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Ui $Url) {
            $ready = $true
            break
        }
    }

    if (-not $ready) {
        throw "UI did not become ready at $Url. Make sure you installed the windows-exe-ui build, not the standard build."
    }
}

Write-Host ""
Write-Host "UI is ready: $Url"
Start-Process $Url
