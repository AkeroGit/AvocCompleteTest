[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Prefix,

    [switch]$DesktopShortcut,

    [switch]$NoShortcuts,

    [switch]$SkipConnectivityCheck
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ResolvedPrefix = [System.IO.Path]::GetFullPath($Prefix)
$VenvDir = Join-Path $ResolvedPrefix '.venv'
$AppDir = Join-Path $ResolvedPrefix 'app'
$BinDir = Join-Path $ResolvedPrefix 'bin'
$DataDir = Join-Path $ResolvedPrefix 'data'

New-Item -ItemType Directory -Force -Path $ResolvedPrefix, $BinDir, $DataDir | Out-Null

if ($DesktopShortcut -and $NoShortcuts) {
    throw '-DesktopShortcut and -NoShortcuts cannot be used together.'
}

function Resolve-PythonInterpreter {
    $Candidates = @(
        @{
            Name = 'py -3.12'
            Command = 'py'
            Args = @('-3.12')
        },
        @{
            Name = 'python'
            Command = 'python'
            Args = @()
        }
    )

    foreach ($Candidate in $Candidates) {
        if (-not (Get-Command $Candidate.Command -ErrorAction SilentlyContinue)) {
            continue
        }

        try {
            $Probe = & $Candidate.Command @($Candidate.Args + @('-c', "import sys, json; print(json.dumps({'executable': sys.executable, 'version': '.'.join(map(str, sys.version_info[:3]))}))"))
            if ($LASTEXITCODE -ne 0) {
                continue
            }
            $Resolved = $Probe.Trim() | ConvertFrom-Json
        }
        catch {
            continue
        }

        return @{
            Name = $Candidate.Name
            Launcher = $Candidate.Command
            LauncherArgs = $Candidate.Args
            Executable = $Resolved.executable
            Version = $Resolved.version
        }
    }

    return $null
}

$ResolvedPython = Resolve-PythonInterpreter
if (-not $ResolvedPython) {
    throw @'
error: no usable Python interpreter found.
resolution order: py -3.12, then python.
remediation: install Python 3.12.x and ensure either "py" or "python" is available on PATH, then rerun installer.
'@
}

$PythonLauncher = $ResolvedPython.Launcher
$PythonLauncherArgs = $ResolvedPython.LauncherArgs
$PythonExecutable = $ResolvedPython.Executable
$PythonVersion = $ResolvedPython.Version

Write-Host "Resolved Python launcher : $($ResolvedPython.Name)"
Write-Host "Resolved Python path     : $PythonExecutable"
Write-Host "Resolved Python version  : $PythonVersion"

& $PythonLauncher @($PythonLauncherArgs + @('-c', 'import sys; raise SystemExit(0 if (sys.version_info.major == 3 and sys.version_info.minor == 12) else 1)'))
if ($LASTEXITCODE -ne 0) {
    throw "error: incompatible Python version detected ($PythonVersion) from $PythonExecutable.`nremediation: install Python 3.12.x and rerun installer."
}

& $PythonLauncher @($PythonLauncherArgs + @('-c', 'import venv'))
if ($LASTEXITCODE -ne 0) {
    throw 'error: Python "venv" module is unavailable.
remediation: reinstall Python with venv support enabled, then rerun installer.'
}

$ConnectivityStatus = 'skipped'
if (-not $SkipConnectivityCheck) {
    try {
        Invoke-WebRequest -Method Head -Uri 'https://pypi.org/simple/' -TimeoutSec 5 | Out-Null
        $ConnectivityStatus = 'ok'
    }
    catch {
        throw 'error: cannot reach https://pypi.org/simple/ (offline or blocked network).
remediation: connect to the internet, configure proxy/firewall access for pip, or rerun with -SkipConnectivityCheck if local package sources are prepared.'
    }
}

Write-Host 'Preflight summary:'
Write-Host "  Python        : $PythonVersion (compatible)"
Write-Host "  Python path   : $PythonExecutable"
Write-Host '  venv module   : available'
Write-Host "  Connectivity  : $ConnectivityStatus"

& $PythonLauncher @($PythonLauncherArgs + @('-m', 'venv', $VenvDir))
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

$ManifestPath = Join-Path $ResolvedPrefix 'install-manifest.txt'
Set-Content -Path $ManifestPath -Value '' -NoNewline

$RemoveShortcuts = @"
`$ErrorActionPreference = 'Stop'
`$ScriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$RootDir = [System.IO.Path]::GetFullPath((Join-Path `$ScriptDir '..'))
`$Manifest = Join-Path `$RootDir 'install-manifest.txt'

if (-not (Test-Path `$Manifest)) {
    Write-Host "No install manifest found at `$Manifest. Nothing to remove."
    exit 0
}

`$RemovedAny = `$false
Get-Content `$Manifest | ForEach-Object {
    `$ShortcutPath = `$_.Trim()
    if ([string]::IsNullOrWhiteSpace(`$ShortcutPath)) {
        return
    }
    if (Test-Path `$ShortcutPath) {
        Remove-Item -Force `$ShortcutPath
        Write-Host "Removed shortcut: `$ShortcutPath"
        `$RemovedAny = `$true
    }
    else {
        Write-Host "Shortcut already missing: `$ShortcutPath"
    }
}

if (-not `$RemovedAny) {
    Write-Host 'No shortcut files were removed.'
}
"@
Set-Content -Path (Join-Path $BinDir 'remove-shortcuts.ps1') -Value $RemoveShortcuts -NoNewline

$RemoveShortcutsCmd = @"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0remove-shortcuts.ps1" %*
"@
Set-Content -Path (Join-Path $BinDir 'remove-shortcuts.cmd') -Value $RemoveShortcutsCmd -NoNewline

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
    Set-Content -Path $ManifestPath -Value $ShortcutPath -NoNewline
    Write-Host "Created desktop shortcut: $ShortcutPath"
}

Write-Host "Installed AVoc into $ResolvedPrefix"
Write-Host "Run: $(Join-Path $BinDir 'avoc.ps1')"
