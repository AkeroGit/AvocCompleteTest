# AVoc Uninstall Guide

## Portable mode
If you installed AVoc as a self-contained portable prefix, remove the entire `<prefix>` directory.

- Linux: `rm -rf <prefix>`
- Windows (PowerShell): `Remove-Item -LiteralPath <prefix> -Recurse -Force`

## Integrated mode
If you enabled installer integration features that create artifacts outside `<prefix>` (for example desktop shortcuts), run the uninstall helper from the install prefix so tracked artifacts are cleaned up first:

- Linux: `<prefix>/bin/uninstall`
- Windows: `<prefix>\bin\uninstall.cmd` (or `uninstall.ps1`)

The uninstall helper reads `<prefix>/install-manifest.txt`, removes each listed external artifact, and then deletes `<prefix>`.

## Leftovers not removed by AVoc uninstaller
AVoc uninstall does **not** remove OS-level dependencies and host system components, including:

- GPU drivers and vendor runtimes
- The operating system audio stack / audio device drivers

Those components are shared system resources and must be managed with your OS or hardware vendor tooling.
