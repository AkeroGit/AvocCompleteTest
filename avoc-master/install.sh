#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREFIX=""
CREATE_DESKTOP_SHORTCUT=0

usage() {
  cat <<USAGE
Usage: ./install.sh --prefix <folder> [--desktop-shortcut]

Installs AVoc into an isolated prefix:
  <prefix>/bin     launchers
  <prefix>/.venv   Python virtual environment
  <prefix>/app     AVoc sources
  <prefix>/data    writable runtime data

Options:
  --prefix <folder>     Target install folder (required)
  --desktop-shortcut    Also create a .desktop launcher in ~/.local/share/applications
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
  echo "Created desktop shortcut: ${DESKTOP_FILE}"
fi

echo "Installed AVoc into ${PREFIX}"
echo "Run: ${BIN_DIR}/avoc"
