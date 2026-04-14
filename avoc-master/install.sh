#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREFIX=""
CREATE_DESKTOP_SHORTCUT=0
NO_SHORTCUTS=0
SKIP_CONNECTIVITY_CHECK=0

usage() {
  cat <<USAGE
Usage: ./install.sh --prefix <folder> [--desktop-shortcut] [--no-shortcuts] [--skip-connectivity-check]

Installs AVoc into an isolated prefix:
  <prefix>/bin     launchers
  <prefix>/.venv   Python virtual environment
  <prefix>/app     AVoc sources
  <prefix>/data    writable runtime data

Options:
  --prefix <folder>     Target install folder (required)
  --desktop-shortcut    Also create a .desktop launcher in ~/.local/share/applications
  --no-shortcuts        Skip desktop/start-menu integration add-ons (default)
  --skip-connectivity-check
                        Skip the PyPI connectivity preflight check before pip install
  -h, --help            Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || { echo "error: --prefix requires a value" >&2; exit 1; }
      PREFIX="$2"
      shift 2
      ;;
    --desktop-shortcut)
      CREATE_DESKTOP_SHORTCUT=1
      shift
      ;;
    --no-shortcuts)
      NO_SHORTCUTS=1
      shift
      ;;
    --skip-connectivity-check)
      SKIP_CONNECTIVITY_CHECK=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "${PREFIX}" ]] || { echo "error: --prefix is required" >&2; usage >&2; exit 1; }

if [[ "${CREATE_DESKTOP_SHORTCUT}" -eq 1 && "${NO_SHORTCUTS}" -eq 1 ]]; then
  echo "error: --desktop-shortcut and --no-shortcuts cannot be used together" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  cat >&2 <<'ERR'
error: python3 executable not found.
remediation: install Python 3.12.x and ensure python3 is on PATH, then rerun installer.
ERR
  exit 1
fi

PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')"
if ! python3 -c 'import sys; raise SystemExit(0 if (sys.version_info.major == 3 and sys.version_info.minor == 12) else 1)'; then
  cat >&2 <<ERR
error: incompatible Python version detected (${PYTHON_VERSION}).
remediation: install Python 3.12.x and make it the default python3 for this shell.
ERR
  exit 1
fi

if ! python3 -c 'import venv'; then
  cat >&2 <<'ERR'
error: Python "venv" module is unavailable.
remediation: install your distro's venv package (for example: python3-venv / python312-venv) and rerun.
ERR
  exit 1
fi

CONNECTIVITY_STATUS="skipped"
if [[ "${SKIP_CONNECTIVITY_CHECK}" -eq 0 ]]; then
  if python3 -c 'import socket; s=socket.create_connection(("pypi.org", 443), timeout=5); s.close()'; then
    CONNECTIVITY_STATUS="ok"
  else
    cat >&2 <<'ERR'
error: cannot reach pypi.org:443 (offline or blocked network).
remediation: connect to the internet, configure proxy/firewall access for pip, or rerun with --skip-connectivity-check if you have local/wheel sources prepared.
ERR
    exit 1
  fi
fi

echo "Preflight summary:"
echo "  Python        : ${PYTHON_VERSION} (compatible)"
echo "  venv module   : available"
echo "  Connectivity  : ${CONNECTIVITY_STATUS}"

PREFIX="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$PREFIX")"
VENV_DIR="${PREFIX}/.venv"
APP_DIR="${PREFIX}/app"
BIN_DIR="${PREFIX}/bin"
DATA_DIR="${PREFIX}/data"

mkdir -p "${PREFIX}" "${BIN_DIR}" "${DATA_DIR}"

python3 -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/python" -m pip install --upgrade pip
"${VENV_DIR}/bin/pip" install -r "${SCRIPT_DIR}/requirements-3.12.3.txt"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"
cp -a "${SCRIPT_DIR}/main.py" "${APP_DIR}/main.py"
cp -a "${SCRIPT_DIR}/src" "${APP_DIR}/src"
cp -a "${SCRIPT_DIR}/LICENSE" "${APP_DIR}/LICENSE"
cp -a "${SCRIPT_DIR}/README.md" "${APP_DIR}/README.md"

cat > "${BIN_DIR}/avoc" <<LAUNCHER
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="\$(cd -- "\$(dirname -- "\${BASH_SOURCE[0]}")" && pwd)"
export AVOC_HOME="\${AVOC_HOME:-\$(cd -- "\${SCRIPT_DIR}/.." && pwd)}"
export AVOC_DATA_DIR="\${AVOC_DATA_DIR:-\${AVOC_HOME}/data}"

mkdir -p \
  "\${AVOC_DATA_DIR}" \
  "\${AVOC_DATA_DIR}/settings" \
  "\${AVOC_DATA_DIR}/cache" \
  "\${AVOC_DATA_DIR}/logs" \
  "\${AVOC_DATA_DIR}/models" \
  "\${AVOC_DATA_DIR}/pretrain" \
  "\${AVOC_DATA_DIR}/voice_cards"

export XDG_DATA_HOME="\${AVOC_DATA_DIR}"
export XDG_CONFIG_HOME="\${AVOC_DATA_DIR}/settings"
export XDG_CACHE_HOME="\${AVOC_DATA_DIR}/cache"
export XDG_STATE_HOME="\${AVOC_DATA_DIR}/logs"
export TORCH_HOME="\${AVOC_DATA_DIR}/cache/torch"
export HF_HOME="\${AVOC_DATA_DIR}/cache/huggingface"

# shellcheck disable=SC1091
source "\${AVOC_HOME}/.venv/bin/activate"
cd "\${AVOC_HOME}/app"
exec python -m main "\$@"
LAUNCHER
chmod +x "${BIN_DIR}/avoc"

MANIFEST_PATH="${PREFIX}/install-manifest.txt"
: > "${MANIFEST_PATH}"

cat > "${BIN_DIR}/uninstall" <<UNINSTALL
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="\$(cd -- "\$(dirname -- "\${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="\$(cd -- "\${SCRIPT_DIR}/.." && pwd)"
MANIFEST="\${ROOT_DIR}/install-manifest.txt"

if [[ ! -d "\${ROOT_DIR}" ]]; then
  echo "Install root already missing: \${ROOT_DIR}"
  exit 0
fi

if [[ "\${1:-}" == "--yes" ]]; then
  shift
else
  echo "This will remove shortcuts from \${MANIFEST} and then delete:"
  echo "  \${ROOT_DIR}"
  read -r -p "Type 'yes' to continue: " confirm
  if [[ "\${confirm}" != "yes" ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

removed_any=0
if [[ -f "\${MANIFEST}" ]]; then
  while IFS= read -r shortcut_path || [[ -n "\${shortcut_path}" ]]; do
    [[ -n "\${shortcut_path}" ]] || continue
    if [[ -e "\${shortcut_path}" ]]; then
      rm -f "\${shortcut_path}"
      echo "Removed shortcut: \${shortcut_path}"
      removed_any=1
    else
      echo "Shortcut already missing: \${shortcut_path}"
    fi
  done < "\${MANIFEST}"
else
  echo "No install manifest found at \${MANIFEST}. Skipping shortcut cleanup."
fi

if [[ "\${removed_any}" -eq 0 ]]; then
  echo "No shortcut files were removed."
fi

rm -rf "\${ROOT_DIR}"
echo "Removed install root: \${ROOT_DIR}"
UNINSTALL
chmod +x "${BIN_DIR}/uninstall"

cat > "${PREFIX}/install-metadata.json" <<META
{
  "installer": "install.sh",
  "installed_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "prefix": "${PREFIX}",
  "venv": ".venv",
  "launcher": "bin/avoc",
  "data_dir": "data",
  "requirements": "requirements-3.12.3.txt"
}
META

if [[ "${CREATE_DESKTOP_SHORTCUT}" -eq 1 ]]; then
  DESKTOP_FILE="${HOME}/.local/share/applications/AVoc-$(basename "${PREFIX}").desktop"
  mkdir -p "$(dirname "${DESKTOP_FILE}")"
  cat > "${DESKTOP_FILE}" <<DESKTOP
[Desktop Entry]
Name=AVoc
Exec=${BIN_DIR}/avoc
Icon=${APP_DIR}/src/avoc/AVoc.svg
Type=Application
Categories=AudioVideo;Audio;
Path=${PREFIX}
DESKTOP
  chmod +x "${DESKTOP_FILE}"
  printf '%s\n' "${DESKTOP_FILE}" > "${MANIFEST_PATH}"
  echo "Created desktop shortcut: ${DESKTOP_FILE}"
fi

echo "Installed AVoc into ${PREFIX}"
echo "Run: ${BIN_DIR}/avoc"
