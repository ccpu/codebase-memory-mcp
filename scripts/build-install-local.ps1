<#
.SYNOPSIS
    Build codebase-memory-mcp locally on Windows and install the local binary.

.DESCRIPTION
    This script does not download release binaries. It builds from the current
    checkout using Makefile.cbm, removes any previous install directory, copies
    the locally built codebase-memory-mcp.exe into the install directory, and
    verifies the installed binary.

    Native Windows builds require an MSYS2/MinGW-style toolchain on PATH:
      - make
      - gcc
      - g++

    The default target is "cbm" (no graph UI) because the UI target runs
    "npm ci" inside graph-ui, which downloads npm dependencies when they are
    not already cached.

.PARAMETER WithUI
    Build the graph UI variant. This may download npm dependencies through
    "npm ci" if graph-ui/node_modules is not already present.

.PARAMETER ConfigureAgents
    After installing the binary, run "codebase-memory-mcp install -y" from the
    locally built binary to configure detected coding agents. Omit this switch
    if you only want the binary installed.

.PARAMETER InstallDir
    Installation directory. Defaults to the same path used by install.ps1:
    %LOCALAPPDATA%\Programs\codebase-memory-mcp.

.PARAMETER Make
    GNU make executable. Defaults to "make". If make is not on PATH, pass the
    MSYS2 path, for example: C:\msys64\usr\bin\make.exe

.PARAMETER NoPath
    Do not add the install directory to the user PATH.

.PARAMETER KeepBuild
    Do not remove build/c before building.

.EXAMPLE
    pwsh -ExecutionPolicy Bypass -File scripts/build-install-local.ps1

.EXAMPLE
    pwsh -ExecutionPolicy Bypass -File scripts/build-install-local.ps1 -Make C:\msys64\usr\bin\make.exe

.EXAMPLE
    pwsh -ExecutionPolicy Bypass -File scripts/build-install-local.ps1 -ConfigureAgents
#>
[CmdletBinding()]
param(
    [switch]$WithUI,
    [switch]$ConfigureAgents,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\codebase-memory-mcp"),
    [string]$Make = "make",
    [switch]$NoPath,
    [switch]$KeepBuild
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Yellow
}

function Require-Command {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Required command not found on PATH: $Name"
    }
    return $cmd.Source
}

function Enable-Msys2Toolchain {
    $roots = @()
    if ($env:MSYS2_ROOT) {
        $roots += $env:MSYS2_ROOT
    }
    $roots += "C:\msys64"

    $profiles = @("ucrt64", "mingw64", "clang64")
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) {
            continue
        }
        foreach ($profile in $profiles) {
            $bin = Join-Path $root "$profile\bin"
            $usr = Join-Path $root "usr\bin"
            $gcc = Join-Path $bin "gcc.exe"
            $gxx = Join-Path $bin "g++.exe"
            $makeExe = Join-Path $usr "make.exe"
            if ((Test-Path $gcc) -and (Test-Path $gxx) -and (Test-Path $makeExe)) {
                $env:Path = "$bin;$usr;$env:Path"
                return "$root ($profile)"
            }
        }
    }
    return $null
}

function Resolve-Under {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullParent = [System.IO.Path]::GetFullPath($Parent)
    if (-not $fullParent.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $fullParent += [System.IO.Path]::DirectorySeparatorChar
    }
    if (-not $fullPath.StartsWith($fullParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside expected parent. Path=$fullPath Parent=$fullParent"
    }
    return $fullPath
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "codebase-memory-mcp local build/install" -ForegroundColor White
Write-Host "  repo:       $repoRoot"
Write-Host "  install:    $InstallDir"
Write-Host "  target:     $(if ($WithUI) { 'cbm-with-ui' } else { 'cbm' })"
Write-Host "  configure:  $ConfigureAgents"

Write-Step "Checking toolchain..."
$msys2 = Enable-Msys2Toolchain
if ($msys2) {
    Write-Ok "using MSYS2 toolchain: $msys2"
}
$makePath = Require-Command $Make
$gccPath = Require-Command "gcc"
$gxxPath = Require-Command "g++"
Write-Ok "make: $makePath"
Write-Ok "gcc:  $gccPath"
Write-Ok "g++:  $gxxPath"

$tmp = $env:TEMP
if (-not $tmp) {
    $tmp = Join-Path $env:USERPROFILE "AppData\Local\Temp"
}

if (-not $KeepBuild) {
    Write-Step "Cleaning previous build output..."
    $buildDir = Resolve-Under -Path (Join-Path $repoRoot "build\c") -Parent $repoRoot
    if (Test-Path $buildDir) {
        Remove-Item -LiteralPath $buildDir -Recurse -Force
        Write-Ok "removed $buildDir"
    } else {
        Write-Ok "nothing to clean"
    }
}

Write-Step "Building local binary..."
$target = if ($WithUI) { "cbm-with-ui" } else { "cbm" }
& $Make "-j" "-f" "Makefile.cbm" $target "SANITIZE=" "TMP=$tmp" "TEMP=$tmp" "TMPDIR=$tmp"
if ($LASTEXITCODE -ne 0) {
    throw "build failed with exit code $LASTEXITCODE"
}

$builtExe = Join-Path $repoRoot "build\c\codebase-memory-mcp.exe"
$builtNoExt = Join-Path $repoRoot "build\c\codebase-memory-mcp"
if (Test-Path $builtExe) {
    $built = $builtExe
} elseif (Test-Path $builtNoExt) {
    $built = $builtNoExt
} else {
    throw "build finished but no binary was found under build\c"
}
Write-Ok "built $built"

Write-Step "Removing old local install..."
$installFull = Resolve-Under -Path $InstallDir -Parent (Join-Path $env:LOCALAPPDATA "Programs")
$destExe = Join-Path $installFull "codebase-memory-mcp.exe"

$running = Get-Process -Name "codebase-memory-mcp" -ErrorAction SilentlyContinue
if ($running) {
    Write-Warn "stopping existing codebase-memory-mcp process(es)"
    $running | Stop-Process -Force
}

if (Test-Path $installFull) {
    Remove-Item -LiteralPath $installFull -Recurse -Force
    Write-Ok "removed $installFull"
} else {
    Write-Ok "no previous install directory"
}

Write-Step "Installing local binary..."
New-Item -ItemType Directory -Path $installFull -Force | Out-Null
Copy-Item -LiteralPath $built -Destination $destExe -Force
Write-Ok "installed $destExe"

Write-Step "Verifying installed binary..."
$version = & $destExe --version 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "installed binary failed to run: $version"
}
Write-Ok "$version"

if (-not $NoPath) {
    Write-Step "Checking user PATH..."
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($userPath) {
        $parts = $userPath -split ';' | Where-Object { $_ -and $_.Trim() -ne "" }
    }
    $alreadyOnPath = $false
    foreach ($part in $parts) {
        if ([System.String]::Equals($part.TrimEnd('\'), $installFull.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            $alreadyOnPath = $true
            break
        }
    }
    if (-not $alreadyOnPath) {
        $newPath = (($parts + $installFull) -join ';')
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$env:Path;$installFull"
        Write-Ok "added install directory to user PATH"
    } else {
        Write-Ok "install directory already on user PATH"
    }
}

if ($ConfigureAgents) {
    Write-Step "Configuring detected coding agents..."
    & $destExe install -y
    if ($LASTEXITCODE -ne 0) {
        throw "agent configuration failed with exit code $LASTEXITCODE"
    }
    Write-Ok "agent configuration complete"
} else {
    Write-Step "Skipping agent configuration."
    Write-Host "  Review planned writes with:" -ForegroundColor Yellow
    Write-Host "    `"$destExe`" install --plan"
    Write-Host "    `"$destExe`" install --dry-run"
    Write-Host "  Configure later with:" -ForegroundColor Yellow
    Write-Host "    `"$destExe`" install"
}

Write-Host ""
Write-Host "Done. Restart your terminal so PATH changes take effect." -ForegroundColor Green
