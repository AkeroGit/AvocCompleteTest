# AVoc Uninstall Guide

Use the same terminology on Linux and Windows to reduce confusion:

- **Portable mode**: no shortcut/external artifacts were created.
- **Integrated mode**: installer created artifacts outside `<prefix>` (for example desktop shortcuts).

## Portable mode uninstall
If installed as a self-contained portable prefix, remove the entire `<prefix>` directory directly.

- Linux: `rm -rf <prefix>`
- Windows (PowerShell): `Remove-Item -LiteralPath <prefix> -Recurse -Force`

## Integrated mode uninstall
If shortcut/external artifacts were enabled, run the uninstall helper from inside the install prefix first.
This helper uses `<prefix>/install-manifest.txt` to remove tracked out-of-prefix artifacts, then removes `<prefix>`.

Exact commands:

- Linux:
  - `<prefix>/bin/uninstall`
- Windows:
  - `<prefix>\bin\uninstall.cmd`
  - or PowerShell: `& "<prefix>\bin\uninstall.ps1"`

Do **not** skip the helper in Integrated mode; deleting `<prefix>` first can leave external artifacts behind.

## Non-interactive install reminder (for future uninstall expectations)
In non-interactive installs, external artifacts require explicit acknowledgement:

- Linux: include `--accept-external-artifacts` when enabling shortcut integration.
- Windows: include `-AcceptExternalArtifacts` when enabling shortcut integration.

If shortcuts are not needed, use portable mode flags instead (`--no-shortcuts` / `-NoShortcuts`).

## Leftovers not removed by AVoc uninstaller
AVoc uninstall does **not** remove OS-level dependencies and host system components, including:

- GPU drivers and vendor runtimes
- The operating system audio stack / audio device drivers

Those components are shared system resources and must be managed with your OS or hardware vendor tooling.
