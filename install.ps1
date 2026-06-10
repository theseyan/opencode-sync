#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$Repo = "theseyan/opencode-sync"
$Branch = if ($env:BRANCH) { $env:BRANCH } else { "main" }
$Base = "https://raw.githubusercontent.com/$Repo/$Branch"
$InstallDir = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "bin" }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git is required"
    exit 1
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$localPs1 = Join-Path $scriptRoot "opencode-sync.ps1"
$localCmd = Join-Path $scriptRoot "opencode-sync.cmd"
$destPs1 = Join-Path $InstallDir "opencode-sync.ps1"
$destCmd = Join-Path $InstallDir "opencode-sync.cmd"

$cmdContent = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0opencode-sync.ps1" %*
"@

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

if (Test-Path $localPs1) {
    Copy-Item -Path $localPs1 -Destination $destPs1 -Force
    if (Test-Path $localCmd) {
        Copy-Item -Path $localCmd -Destination $destCmd -Force
    } else {
        Set-Content -Path $destCmd -Value $cmdContent -Encoding ASCII
    }
} else {
    Invoke-WebRequest -Uri "$Base/opencode-sync.ps1" -OutFile $destPs1
    Invoke-WebRequest -Uri "$Base/opencode-sync.cmd" -OutFile $destCmd
}

$pathEntries = $env:PATH -split ';'
if ($InstallDir -notin $pathEntries) {
    Write-Host "note: add $InstallDir to your user PATH (Settings > System > About > Advanced system settings > Environment Variables),"
    Write-Host "      or run: [Environment]::SetEnvironmentVariable('PATH', `"$env:PATH;$InstallDir`", 'User')"
}

Write-Host "installed opencode-sync to $InstallDir"
Write-Host "run: opencode-sync init"
