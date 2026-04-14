[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Prefix,

    [switch]$DesktopShortcut
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ResolvedPrefix = [System.IO.Path]::GetFullPath($Prefix)
$VenvDir = Join-Path $ResolvedPrefix '.venv'
$AppDir = Join-Path $ResolvedPrefix 'app'
$BinDir = Join-Path $ResolvedPrefix 'bin'
$DataDir = Join-Path $ResolvedPrefix 'data'

New-Item -ItemType Directory -Force -Path $ResolvedPrefix, $BinDir, $DataDir | Out-Null

python -m venv $VenvDir
& (Join-Path $VenvDir 'Scripts\python.exe') -m pip install --upgrade pip
& (Join-Path $VenvDir 'Scripts\pip.exe') install -r (Join-Path $ScriptDir 'requirements-3.12.3.txt')

if (Test-Path $AppDir) {
    Remove-Item -Recurse -Force $AppDir
}
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
Copy-Item -Recurse -Force (Join-Path $ScriptDir 'src') (Join-Path $AppDir 'src')
Copy-Item -Force (Join-Path $ScriptDir 'main.py') (Join-Path $AppDir 'main.py')
Copy-Item -Force (Join-Path $ScriptDir 'LICENSE') (Join-Path $AppDir 'LICENSE')
Copy-Item -Force (Join-Path $ScriptDir 'README.md') (Join-Path $AppDir 'README.md')

$PsLauncher = @"
`$ErrorActionPreference = 'Stop'
`$ScriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
if (-not `$env:AVOC_HOME) {
    `$env:AVOC_HOME = [System.IO.Path]::GetFullPath((Join-Path `$ScriptDir '..'))
}
if (-not `$env:AVOC_DATA_DIR) {
    `$env:AVOC_DATA_DIR = Join-Path `$env:AVOC_HOME 'data'
}

New-Item -ItemType Directory -Force -Path `$(Join-Path `$env:AVOC_DATA_DIR 'settings'), `
    `$(Join-Path `$env:AVOC_DATA_DIR 'cache'), `
    `$(Join-Path `$env:AVOC_DATA_DIR 'logs'), `
    `$(Join-Path `$env:AVOC_DATA_DIR 'models'), `
    `$(Join-Path `$env:AVOC_DATA_DIR 'pretrain'), `
    `$(Join-Path `$env:AVOC_DATA_DIR 'voice_cards') | Out-Null

`$env:XDG_DATA_HOME = `$env:AVOC_DATA_DIR
`$env:XDG_CONFIG_HOME = Join-Path `$env:AVOC_DATA_DIR 'settings'
`$env:XDG_CACHE_HOME = Join-Path `$env:AVOC_DATA_DIR 'cache'
`$env:XDG_STATE_HOME = Join-Path `$env:AVOC_DATA_DIR 'logs'
`$env:TORCH_HOME = Join-Path `$env:AVOC_DATA_DIR 'cache/torch'
`$env:HF_HOME = Join-Path `$env:AVOC_DATA_DIR 'cache/huggingface'

& (Join-Path `$env:AVOC_HOME '.venv\Scripts\python.exe') -m main `$args
"@
Set-Content -Path (Join-Path $BinDir 'avoc.ps1') -Value $PsLauncher -NoNewline

$CmdLauncher = @"
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if not defined AVOC_HOME set "AVOC_HOME=%SCRIPT_DIR%.."
if not defined AVOC_DATA_DIR set "AVOC_DATA_DIR=%AVOC_HOME%\data"
powershell -ExecutionPolicy Bypass -File "%~dp0avoc.ps1" %*
"@
Set-Content -Path (Join-Path $BinDir 'avoc.cmd') -Value $CmdLauncher -NoNewline

$Metadata = [ordered]@{
    installer         = 'install.ps1'
    installed_at_utc  = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    prefix            = $ResolvedPrefix
    venv              = '.venv'
    launcher          = 'bin/avoc.ps1'
    data_dir          = 'data'
    requirements      = 'requirements-3.12.3.txt'
} | ConvertTo-Json
Set-Content -Path (Join-Path $ResolvedPrefix 'install-metadata.json') -Value $Metadata -NoNewline

if ($DesktopShortcut) {
    $DesktopPath = [Environment]::GetFolderPath('Desktop')
    $ShortcutPath = Join-Path $DesktopPath 'AVoc.lnk'
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = Join-Path $BinDir 'avoc.cmd'
    $Shortcut.WorkingDirectory = $ResolvedPrefix
    $Shortcut.IconLocation = (Join-Path $AppDir 'src\avoc\AVoc.svg')
    $Shortcut.Save()
    Write-Host "Created desktop shortcut: $ShortcutPath"
}

Write-Host "Installed AVoc into $ResolvedPrefix"
Write-Host "Run: $(Join-Path $BinDir 'avoc.ps1')"
