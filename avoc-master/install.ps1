[CmdletBinding()]
param(
    [string]$Prefix,

    [switch]$DesktopShortcut,

    [switch]$NoShortcuts,

    [switch]$SkipConnectivityCheck,
    [switch]$SkipDoctor,

    [switch]$UseSystemPython,
    [switch]$NonInteractive,
    [switch]$AcceptExternalArtifacts,

    [string]$PythonRuntimeUrl,

    [string]$PythonRuntimeSha256
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    @'
Usage:
  .\install.ps1 -Prefix <folder> [-DesktopShortcut] [-NoShortcuts] [-NonInteractive] [-AcceptExternalArtifacts] [-SkipConnectivityCheck] [-SkipDoctor] [-UseSystemPython] [-PythonRuntimeUrl <url-or-file>] [-PythonRuntimeSha256 <sha256>]

Required:
  -Prefix <folder>        Target install folder.

Prompt behavior:
  If -Prefix is missing and stdin/stdout are interactive, installer prompts for it.
  In non-interactive mode (CI/piped input) or with -NonInteractive, required flags must be provided.
'@ | Write-Host
}

$IsInteractive = [System.Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
if ([string]::IsNullOrWhiteSpace($Prefix)) {
    if ($NonInteractive -or -not $IsInteractive) {
        Show-Usage
        throw 'error: -Prefix is required in non-interactive mode.'
    }
    $defaultPrefix = (Get-Location).Path
    $prefixInput = Read-Host "Install prefix folder [$defaultPrefix]"
    $Prefix = if ([string]::IsNullOrWhiteSpace($prefixInput)) { $defaultPrefix } else { $prefixInput }
}
if ([string]::IsNullOrWhiteSpace($Prefix)) {
    Show-Usage
    throw 'error: -Prefix is required.'
}

# Effective config: merge prompted/flag inputs into a single config path.
$EffectiveConfig = [ordered]@{
    Prefix = $Prefix
    DesktopShortcut = [bool]$DesktopShortcut
    NoShortcuts = [bool]$NoShortcuts
}
$Prefix = $EffectiveConfig.Prefix
$DesktopShortcut = $EffectiveConfig.DesktopShortcut
$NoShortcuts = $EffectiveConfig.NoShortcuts

if ($DesktopShortcut -and $NoShortcuts) {
    throw '-DesktopShortcut and -NoShortcuts cannot be used together.'
}

function Confirm-ExternalArtifactsAcknowledgement {
    $HasExternalArtifacts = $DesktopShortcut
    if (-not $HasExternalArtifacts) {
        return
    }

    Write-Warning 'This install creates files outside <prefix>; use <prefix>/bin/uninstall (Linux) or <prefix>\bin\uninstall.cmd (Windows) to clean up fully.'
    Write-Host 'See UNINSTALL.md (Integrated mode): run the uninstall helper from the install prefix so tracked artifacts are cleaned up first.'

    if ($NonInteractive -or -not $IsInteractive) {
        if (-not $AcceptExternalArtifacts) {
            throw "error: external artifacts selected in non-interactive mode.`nremediation: rerun with -AcceptExternalArtifacts, or disable shortcut options (for example -NoShortcuts)."
        }
        return
    }

    $answer = Read-Host "Proceed with external artifacts? Type 'yes' or 'y' to continue"
    if ($answer -notmatch '^(?i:y|yes)$') {
        throw 'aborted by user.'
    }
}

function Confirm-NonEmptyPrefix {
    param([Parameter(Mandatory = $true)][string]$TargetPath)

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        return
    }
    $hasContent = Get-ChildItem -LiteralPath $TargetPath -Force | Select-Object -First 1
    if (-not $hasContent) {
        return
    }
    if ($NonInteractive -or -not $IsInteractive) {
        throw "error: target prefix is not empty: $TargetPath`nremediation: choose an empty prefix, or rerun interactively to confirm overwrite/continue."
    }
    $answer = Read-Host "Target prefix is not empty ($TargetPath). Continue anyway? [y/N]"
    if ($answer -notmatch '^(?i:y|yes)$') {
        throw 'aborted by user.'
    }
}

function Test-PrefixWritable {
    param([Parameter(Mandatory = $true)][string]$TargetPath)

    if (Test-Path -LiteralPath $TargetPath) {
        if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
            throw "error: install prefix exists but is not a directory: $TargetPath"
        }
    }
    else {
        $parentPath = Split-Path -Parent $TargetPath
        if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
            throw "error: parent directory does not exist: $parentPath"
        }
    }

    try {
        New-Item -ItemType Directory -Force -Path $TargetPath, (Join-Path $TargetPath 'bin'), (Join-Path $TargetPath 'data'), (Join-Path $TargetPath 'runtime') | Out-Null
    }
    catch {
        throw "error: unable to create required folders under prefix: $TargetPath`n$($_.Exception.Message)"
    }
}

function Prompt-DesktopShortcutPreference {
    if ($NonInteractive -or -not $IsInteractive) {
        return
    }
    if ($DesktopShortcut -or $NoShortcuts) {
        return
    }

    $answer = Read-Host 'Create desktop shortcut on the Desktop? [y/N]'
    if ($answer -match '^(?i:y|yes)$') {
        $script:DesktopShortcut = $true
        $script:NoShortcuts = $false
    }
    else {
        $script:DesktopShortcut = $false
        $script:NoShortcuts = $true
    }
}

$ResolvedPrefix = [System.IO.Path]::GetFullPath($Prefix)
Confirm-NonEmptyPrefix -TargetPath $ResolvedPrefix
Test-PrefixWritable -TargetPath $ResolvedPrefix

$VenvDir = Join-Path $ResolvedPrefix '.venv'
$AppDir = Join-Path $ResolvedPrefix 'app'
$BinDir = Join-Path $ResolvedPrefix 'bin'
$DataDir = Join-Path $ResolvedPrefix 'data'
$RuntimeDir = Join-Path $ResolvedPrefix 'runtime\python'
Write-Host "Resolved install prefix : $ResolvedPrefix"
Prompt-DesktopShortcutPreference

if ($DesktopShortcut -and $NoShortcuts) {
    throw '-DesktopShortcut and -NoShortcuts cannot be used together.'
}

Confirm-ExternalArtifactsAcknowledgement

if ($DesktopShortcut) {
    Write-Host "External artifacts summary: desktop shortcut will be created on the Desktop and tracked in $(Join-Path $ResolvedPrefix 'install-manifest.txt')."
}
Write-Host 'Info: default installation does not modify global PATH. Use <prefix>\bin\avoc.cmd directly.'

function Get-PlatformTuple {
    if ($IsWindows) {
        switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
            'X64' { return 'win-amd64' }
            'Arm64' { return 'win-arm64' }
            default { throw "Unsupported Windows architecture: $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)" }
        }
    }
    throw 'Unsupported platform.'
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

$InstallMode = if ($UseSystemPython) { 'system-python' } else { 'installer-managed-python' }
$PlatformTuple = Get-PlatformTuple

if (-not $UseSystemPython) {
    $RuntimeVersion = '3.12.3'
    $RuntimeMap = @{
        'win-amd64' = @{
            Url = 'https://www.nuget.org/api/v2/package/python/3.12.3'
            Sha256 = 'f427e6d102ce7a6f0d8cddf5848d95f7e6884bf8b95f5954eb7f22d0f2f85c6e'
        }
        'win-arm64' = @{
            Url = 'https://www.nuget.org/api/v2/package/pythonarm64/3.12.3'
            Sha256 = '90ef215e0e8b6be090e1d30122b2cc86fba12a34fb6f542c92aa15e41da8b307'
        }
    }
    if (-not $RuntimeMap.ContainsKey($PlatformTuple)) {
        throw "Managed runtime is not configured for platform tuple: $PlatformTuple"
    }
    if ($PythonRuntimeUrl -and -not $PythonRuntimeSha256) {
        throw 'error: -PythonRuntimeSha256 is required when -PythonRuntimeUrl is provided.'
    }
    if ($PythonRuntimeUrl) {
        $RuntimeMap[$PlatformTuple] = @{
            Url = $PythonRuntimeUrl
            Sha256 = $PythonRuntimeSha256
        }
    }
    $RuntimeArchive = Join-Path $ResolvedPrefix "runtime\python-$RuntimeVersion-$PlatformTuple.nupkg"
    New-Item -ItemType Directory -Force -Path (Split-Path $RuntimeArchive -Parent), $RuntimeDir | Out-Null
    function Get-RuntimeArchiveWithRetry {
        param(
            [Parameter(Mandatory = $true)][string]$Source,
            [Parameter(Mandatory = $true)][string]$Destination
        )

        if ($Source -match '^https?://') {
            $maxAttempts = 4
            $delaySec = 2
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try {
                    Invoke-WebRequest -Uri $Source -OutFile $Destination -TimeoutSec 60
                    return
                }
                catch {
                    if ($attempt -lt $maxAttempts) {
                        Write-Warning "Runtime download attempt $attempt/$maxAttempts failed: $($_.Exception.Message). Retrying in $delaySec second(s)..."
                        Start-Sleep -Seconds $delaySec
                        $delaySec = $delaySec * 2
                    }
                }
            }
            throw @"
error: failed to download Python runtime from $Source
remediation: verify network/proxy access, or host the runtime on an internal mirror and pass:
  -PythonRuntimeUrl <internal-url-or-local-file>
  -PythonRuntimeSha256 <expected-sha256>
"@
        }

        $localPath = $Source
        if ($Source -like 'file://*') {
            $localPath = $Source.Substring(7)
        }
        if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
            throw "error: Python runtime file not found at $localPath`nremediation: provide a valid local file path or accessible URL via -PythonRuntimeUrl."
        }
        Copy-Item -LiteralPath $localPath -Destination $Destination -Force
    }

    Get-RuntimeArchiveWithRetry -Source $RuntimeMap[$PlatformTuple].Url -Destination $RuntimeArchive
    $ActualHash = (Get-FileHash -Algorithm SHA256 -Path $RuntimeArchive).Hash.ToLowerInvariant()
    if ($ActualHash -ne $RuntimeMap[$PlatformTuple].Sha256.ToLowerInvariant()) {
        throw @"
error: runtime checksum verification failed.
expected=$($RuntimeMap[$PlatformTuple].Sha256)
actual=$ActualHash
remediation: do not continue with an unverified runtime.
re-download the exact Python 3.12.3 runtime artifact from a trusted source,
recompute SHA256, then rerun with -PythonRuntimeUrl and -PythonRuntimeSha256.
"@
    }
    if (Test-Path $RuntimeDir) { Remove-Item -Recurse -Force $RuntimeDir }
    New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
    Expand-Archive -Path $RuntimeArchive -DestinationPath $RuntimeDir -Force
    $ManagedPythonExe = Join-Path $RuntimeDir 'tools\python.exe'
    if (-not (Test-Path $ManagedPythonExe)) {
        throw "error: managed runtime extraction failed; python executable not found at $ManagedPythonExe"
    }
    $ResolvedPython = @{
        Name = 'managed-runtime'
        Launcher = $ManagedPythonExe
        LauncherArgs = @()
        Executable = $ManagedPythonExe
        Version = (& $ManagedPythonExe -c "import sys; print('.'.join(map(str, sys.version_info[:3])))").Trim()
    }
}
else {
    $ResolvedPython = Resolve-PythonInterpreter
    if (-not $ResolvedPython) {
        throw @'
error: no usable Python interpreter found.
resolution order: py -3.12, then python.
remediation: install Python 3.12.x and ensure either "py" or "python" is available on PATH, then rerun installer.
'@
    }
}

$PythonLauncher = $ResolvedPython.Launcher
$PythonLauncherArgs = $ResolvedPython.LauncherArgs
$PythonExecutable = $ResolvedPython.Executable
$PythonVersion = $ResolvedPython.Version

Write-Host "Resolved Python launcher : $($ResolvedPython.Name)"
Write-Host "Resolved Python path     : $PythonExecutable"
Write-Host "Resolved Python version  : $PythonVersion"
Write-Host "Install mode             : $InstallMode"
Write-Host "Platform tuple           : $PlatformTuple"

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

if (-not $SkipDoctor) {
    Write-Host 'Running AVoc doctor checks...'
    Push-Location $ScriptDir
    try {
        & (Join-Path $VenvDir 'Scripts\python.exe') -m main --doctor
        if ($LASTEXITCODE -ne 0) {
            throw 'error: AVoc doctor validation failed after dependency installation.'
        }
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Warning 'Skipping AVoc doctor checks due to -SkipDoctor (advanced override).'
}

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
`$env:HUGGINGFACE_HUB_CACHE = Join-Path `$env:AVOC_DATA_DIR 'cache/huggingface/hub'
`$env:TRANSFORMERS_CACHE = Join-Path `$env:AVOC_DATA_DIR 'cache/huggingface/transformers'
`$env:HF_DATASETS_CACHE = Join-Path `$env:AVOC_DATA_DIR 'cache/huggingface/datasets'
`$env:PIP_CACHE_DIR = Join-Path `$env:AVOC_DATA_DIR 'cache/pip'

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

$Uninstall = @"
param(
    [switch]`$Yes
)

`$ErrorActionPreference = 'Stop'
`$ScriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$RootDir = [System.IO.Path]::GetFullPath((Join-Path `$ScriptDir '..'))
`$Manifest = Join-Path `$RootDir 'install-manifest.txt'

if (-not (Test-Path `$RootDir -PathType Container)) {
    Write-Host "Install root already missing: `$RootDir"
    exit 0
}

if (-not `$Yes) {
    Write-Host "This will remove shortcuts from `$Manifest and then delete:"
    Write-Host "  `$RootDir"
    `$Confirmation = Read-Host "Type 'yes' to continue"
    if (`$Confirmation -ne 'yes') {
        Write-Host 'Cancelled.'
        exit 0
    }
}

`$RemovedAny = `$false
if (Test-Path `$Manifest) {
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
}
else {
    Write-Host "No install manifest found at `$Manifest. Skipping shortcut cleanup."
}

if (-not `$RemovedAny) {
    Write-Host 'No shortcut files were removed.'
}

Remove-Item -LiteralPath `$RootDir -Recurse -Force
Write-Host "Removed install root: `$RootDir"
"@
Set-Content -Path (Join-Path $BinDir 'uninstall.ps1') -Value $Uninstall -NoNewline

$UninstallCmd = @"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
"@
Set-Content -Path (Join-Path $BinDir 'uninstall.cmd') -Value $UninstallCmd -NoNewline

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
    Add-Content -Path $ManifestPath -Value $ShortcutPath
    Write-Host "Created desktop shortcut: $ShortcutPath"
}

Write-Host "Installed AVoc into $ResolvedPrefix"
Write-Host "Installer mode: $InstallMode"
Write-Host "Python path: $PythonExecutable"
Write-Host "Run: $(Join-Path $BinDir 'avoc.ps1')"
