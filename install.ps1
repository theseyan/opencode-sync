#Requires -Version 5.1
param(
    [switch]$NoPathUpdate
)

$ErrorActionPreference = "Stop"

$Repo = "theseyan/opencode-sync"
$Branch = if ($env:BRANCH) { $env:BRANCH } else { "main" }
$Base = "https://raw.githubusercontent.com/$Repo/$Branch"
$InstallDir = if ($env:INSTALL_DIR) {
    $env:INSTALL_DIR
} else {
    Join-Path $env:USERPROFILE ".opencode-sync\bin"
}

function Publish-Env {
    if (-not ("Win32.NativeMethods" -as [Type])) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
    }
    $result = [UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout(
        [IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result
    ) | Out-Null
}

function Get-UserPath {
    $key = Get-Item -Path 'HKCU:\Environment'
    $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
}

function Add-UserPathEntry([string]$Dir) {
    $path = Get-UserPath
    $parts = @()
    if ($path) { $parts = $path -split ';' | Where-Object { $_ } }
    if ($parts -contains $Dir) { return $false }
    $parts += $Dir
    Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value ($parts -join ';')
    Publish-Env
    $env:PATH = ($env:PATH.TrimEnd(';') + ';' + $Dir)
    return $true
}

function Save-RemoteFile([string]$Url, [string]$OutFile) {
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -#SfLo $OutFile $Url
        if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFile)) { return }
    }
    Invoke-RestMethod -Uri $Url -OutFile $OutFile
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git is required"
    exit 1
}

$destPs1 = Join-Path $InstallDir "opencode-sync.ps1"
$destCmd = Join-Path $InstallDir "opencode-sync.cmd"

$cmdContent = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0opencode-sync.ps1" %*
"@

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

$scriptPath = $MyInvocation.MyCommand.Path
$useLocal = $false
if ($scriptPath) {
    $scriptRoot = Split-Path -Parent $scriptPath
    $localPs1 = Join-Path $scriptRoot "opencode-sync.ps1"
    $localCmd = Join-Path $scriptRoot "opencode-sync.cmd"
    $useLocal = Test-Path $localPs1
}

if ($useLocal) {
    Copy-Item -Path $localPs1 -Destination $destPs1 -Force
    if (Test-Path $localCmd) {
        Copy-Item -Path $localCmd -Destination $destCmd -Force
    } else {
        Set-Content -Path $destCmd -Value $cmdContent -Encoding ASCII
    }
} else {
    Save-RemoteFile "$Base/opencode-sync.ps1" $destPs1
    Save-RemoteFile "$Base/opencode-sync.cmd" $destCmd
}

$pathAdded = $false
if (-not $NoPathUpdate) {
    $pathAdded = Add-UserPathEntry $InstallDir
} else {
    Write-Host "skipped adding $InstallDir to PATH"
}

Write-Host "installed opencode-sync to $InstallDir"
if ($pathAdded) {
    Write-Host "added to user PATH - open a new terminal, then run: opencode-sync init"
} else {
    Write-Host "run: opencode-sync init"
}
