# index-this-repo.ps1 - Copy this file into a repo root and run it.
#
# It indexes the current directory with the installed codebase-memory-mcp
# binary, stores the cache under .codebase-memory/cache, and deletes this helper
# script after a successful index.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\index-this-repo.ps1
#   powershell -ExecutionPolicy Bypass -File .\index-this-repo.ps1 -Mode moderate
#   powershell -ExecutionPolicy Bypass -File .\index-this-repo.ps1 -Name my-project
#   powershell -ExecutionPolicy Bypass -File .\index-this-repo.ps1 -KeepScript

[CmdletBinding()]
param(
    [string]$Mode = "fast",
    [string]$Name = "",
    [string]$CacheDir = "",
    [switch]$KeepScript
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

$RepoPath = (Get-Location).Path
if (-not $Name) {
    $Name = Normalize-ProjectName (Split-Path -Leaf $RepoPath)
}
if (-not $CacheDir) {
    $CacheDir = Join-Path $RepoPath ".codebase-memory\cache"
}

New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null

$env:CBM_INDEX_SUPERVISOR = "0"
$env:CBM_CACHE_DIR = $CacheDir

$Exe = Find-CbmExe

Write-Host "Indexing repository"
Write-Host "  repo:    $RepoPath"
Write-Host "  project: $Name"
Write-Host "  mode:    $Mode"
Write-Host "  cache:   $CacheDir"
Write-Host "  exe:     $Exe"
Write-Host ""

& $Exe cli index_repository --repo-path $RepoPath --name $Name --mode $Mode
if ($LASTEXITCODE -ne 0) {
    throw "index_repository failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Index status:"
& $Exe cli index_status --project $Name

if (-not $KeepScript -and $PSCommandPath) {
    Write-Host ""
    Write-Host "Removing helper script: $PSCommandPath"
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
