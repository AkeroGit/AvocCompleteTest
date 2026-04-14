# AVoc: Local Realtime Voice Changer for Desktop

A speech-to-speech converter that uses AI models locally to convert microphone audio to a different voice in near-realtime.

Suitable for gaming and streaming.

# Quick Start

Drag your voice model files into the window.

![screenshot](doc/screenshot.png)

# Features

- [X] Import of the voice models provided by the user
- [X] Switching between voices
- [X] Pitch adjustments
- [X] Hotkeys and popup notifications for the ease of use in the background
- [X] Pass Through

# Platforms

All desktops.

Linux is the priority.

# Goal

Make voice changing more developer-friendly by creating
  - a voice conversion library
  - a simple voice changer desktop application
  - a command-line voice changer program

Open Source and Free for modification.

# Installation

## Canonical install layout

AVoc now supports a single install root (`AVOC_HOME`) with this layout:

```text
<root>/bin     launchers (for example, bin/avoc)
<root>/.venv   Python virtual environment
<root>/app     package/runtime files
<root>/data    models, pretrain, voice cards, settings, cache, logs
```

The `bin/avoc` launcher sets:

- `AVOC_HOME=<root>`
- `AVOC_DATA_DIR=<root>/data`

and redirects runtime write locations (`QSettings`, model storage, cache/state homes) into `<root>/data`.

## For Arch-based Linux Distributions - from AUR

No cloning of this repo needed.

```
yay -S avoc
```

or for Manjaro

```
pamac build avoc
```

Launch from the menu or by running:

```sh
gio launch /usr/share/applications/AVoc.desktop
```

## For other Linuxes

Requires Python 3.12 (or compatible), `venv`, and build tools needed by the pinned dependencies.

Install AVoc into any target folder:

```sh
git clone https://github.com/develOseven/avoc
cd avoc
./install.sh --prefix "$HOME/.local/opt/avoc"
```

Optionally create a desktop shortcut:

```sh
./install.sh --prefix "$HOME/.local/opt/avoc" --desktop-shortcut
```

For pure portability (recommended), explicitly disable desktop/start-menu add-ons:

```sh
./install.sh --prefix "$HOME/.local/opt/avoc" --no-shortcuts
```

Run with:

```sh
$HOME/.local/opt/avoc/bin/avoc
```

For Windows PowerShell:

```powershell
.\install.ps1 -Prefix "$env:LOCALAPPDATA\AVoc"
```

You can also explicitly keep the install fully portable with:

```powershell
.\install.ps1 -Prefix "$env:LOCALAPPDATA\AVoc" -NoShortcuts
```

## Uninstall modes

### 1) Pure portable install (no shortcuts)

Delete the install root directory (`<root>`).

### 2) Install with shortcuts

Use the helper script generated at `<root>/bin/remove-shortcuts` (Linux) or
`<root>\bin\remove-shortcuts.cmd` (Windows), then remove `<root>`.

Shortcut paths created by the installers are also recorded in
`<root>/install-manifest.txt`, so they can be removed manually if preferred.

If you also copied desktop/icon files into `~/.local/share`, remove them too:

```sh
rm ~/.local/share/applications/AVoc.desktop ~/.local/share/icons/hicolor/scalable/apps/AVoc.svg
rm -rf <root>
```

## (Optional) Virtual Microphone

The voice changer will latch to the actual default microphone, so a virtual microphone isn't needed.

But there are cases when you would want to configure your operating system to provide a virtual microphone:

- When you absolutely don't want to be heard without the voice changer when something crashes and reverts to the direct microphone input.
- When you want to use the AVoc's QtMultimedia backend instead of its PipeWire backend (by uninstalling the pipewire-filtertools package from the Python environment).
- When you're not on the Linux operating system.

## (Optional) EasyEffects

It's fine to use with EasyEffects: put "Noise Reduction" and "Autogain" as the input effects there.

# Development

## Python Environment

Assign a compatible Python version to this directory using pyenv:

```sh
pyenv local 3.12.3
```

Create an environment using venv:

```sh
python -m venv .venv
```

or through VSCode with `~/.pyenv/shims/python` as the Python interpreter.

Install the dependencies:

```sh
source .venv/bin/activate
pip install -r requirements-3.12.3.txt
```

Run:

```sh
./bin/avoc
```

(Optional) Get sources of the voice conversion library and install it in developer mode:

```sh
(cd .. && git clone https://github.com/develOseven/voiceconversion)
source .venv/bin/activate
pip uninstall voiceconversion
pip install -e ../voiceconversion --config-settings editable_mode=strict
```

It allows to work on the voice conversion library.

(Optional) Add to the "configurations" in the VSCode's launch.json:

```json
{
    "name": "Python Debugger: Module",
    "type": "debugpy",
    "request": "launch",
    "module": "main",
}
```
