#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREFIX=""
CREATE_DESKTOP_SHORTCUT=0
NO_SHORTCUTS=0
NON_INTERACTIVE=0
SKIP_CONNECTIVITY_CHECK=0
USE_SYSTEM_PYTHON=0
INSTALL_MODE="installer-managed-python"
PYTHON_RUNTIME_URL=""
PYTHON_RUNTIME_SHA256=""
SKIP_DOCTOR=0

usage() {
  cat <<USAGE
Usage: ./install.sh --prefix <folder> [--desktop-shortcut] [--no-shortcuts] [--non-interactive] [--skip-connectivity-check] [--skip-doctor] [--use-system-python] [--python-runtime-url <url-or-file>] [--python-runtime-sha256 <sha256>]

Installs AVoc into an isolated prefix (Linux only):
  <prefix>/bin     launchers
  <prefix>/.venv   Python virtual environment
  <prefix>/runtime/python managed CPython runtime (default mode)
  <prefix>/app            AVoc sources
  <prefix>/data           writable runtime data

Options:
  --prefix <folder>     Target install folder (required)
  --desktop-shortcut    Also create a .desktop launcher in ~/.local/share/applications
  --no-shortcuts        Skip desktop/start-menu integration add-ons (default)
  --non-interactive     Do not prompt; require all required flags to be provided
  --skip-connectivity-check
                        Skip the PyPI connectivity preflight check before pip install
  --skip-doctor         Advanced override: skip post-install GPU/ONNX doctor validation
  --use-system-python   Developer override: use system python3 from PATH
  --python-runtime-url <url-or-file>
                        Override managed runtime source (https://... or file:///... or local file path)
  --python-runtime-sha256 <sha256>
                        Expected SHA256 for --python-runtime-url (required when overriding URL)
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
    --non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    --skip-connectivity-check)
      SKIP_CONNECTIVITY_CHECK=1
      shift
      ;;
    --skip-doctor)
      SKIP_DOCTOR=1
      shift
      ;;
    --use-system-python)
      USE_SYSTEM_PYTHON=1
      INSTALL_MODE="system-python"
      shift
      ;;
    --python-runtime-url)
      [[ $# -ge 2 ]] || { echo "error: --python-runtime-url requires a value" >&2; exit 1; }
      PYTHON_RUNTIME_URL="$2"
      shift 2
      ;;
    --python-runtime-sha256)
      [[ $# -ge 2 ]] || { echo "error: --python-runtime-sha256 requires a value" >&2; exit 1; }
      PYTHON_RUNTIME_SHA256="$2"
      shift 2
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

IS_INTERACTIVE=0
if [[ -t 0 && -t 1 ]]; then
  IS_INTERACTIVE=1
fi

prompt_missing_inputs() {
  if [[ -z "${PREFIX}" ]]; then
    read -r -p "Install prefix folder: " PREFIX
  fi
}

if [[ -z "${PREFIX}" ]]; then
  if [[ "${NON_INTERACTIVE}" -eq 1 || "${IS_INTERACTIVE}" -eq 0 ]]; then
    echo "error: --prefix is required in non-interactive mode." >&2
    usage >&2
    exit 1
  fi
  prompt_missing_inputs
fi

[[ -n "${PREFIX}" ]] || { echo "error: --prefix is required" >&2; usage >&2; exit 1; }

# Effective config: normalize prompted and flag values onto the same variables/path.
EFFECTIVE_PREFIX="${PREFIX}"
EFFECTIVE_CREATE_DESKTOP_SHORTCUT="${CREATE_DESKTOP_SHORTCUT}"
EFFECTIVE_NO_SHORTCUTS="${NO_SHORTCUTS}"
PREFIX="${EFFECTIVE_PREFIX}"
CREATE_DESKTOP_SHORTCUT="${EFFECTIVE_CREATE_DESKTOP_SHORTCUT}"
NO_SHORTCUTS="${EFFECTIVE_NO_SHORTCUTS}"

if [[ "${CREATE_DESKTOP_SHORTCUT}" -eq 1 && "${NO_SHORTCUTS}" -eq 1 ]]; then
  echo "error: --desktop-shortcut and --no-shortcuts cannot be used together" >&2
  exit 1
fi

if [[ "${CREATE_DESKTOP_SHORTCUT}" -eq 1 ]]; then
  cat <<'WARN'
warning: --desktop-shortcut creates an out-of-prefix desktop entry in ~/.local/share/applications.
this artifact is tracked in install-manifest.txt and removed by bin/uninstall.
WARN
fi

echo "Info: default installation does not modify global PATH. Use ${PREFIX}/bin/avoc directly."

uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "${uname_s}" in
  Linux)
    case "${uname_m}" in
      x86_64) PLATFORM_TUPLE="linux-x86_64" ;;
      aarch64|arm64) PLATFORM_TUPLE="linux-aarch64" ;;
      *) echo "error: unsupported architecture: ${uname_m}" >&2; exit 1 ;;
    esac
    ;;
  Darwin)
    echo "error: macOS is unsupported for AVoc CUDA builds. Use Linux (install.sh) or Windows (install.ps1)." >&2
    exit 1
    ;;
  *)
    echo "error: unsupported platform: ${uname_s}" >&2
    exit 1
    ;;
esac

PYTHON_RUNTIME_VERSION="3.12.3"
RUNTIME_ROOT_REL="runtime/python"
PREFIX="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$PREFIX")"
RUNTIME_DIR="${PREFIX}/${RUNTIME_ROOT_REL}"

if [[ "${USE_SYSTEM_PYTHON}" -eq 0 ]]; then
  case "${PLATFORM_TUPLE}" in
    linux-x86_64)
      RUNTIME_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20240415/cpython-${PYTHON_RUNTIME_VERSION}+20240415-x86_64-unknown-linux-gnu-install_only.tar.gz"
      RUNTIME_SHA256="4fa6442ac65cc95ea30ca521ac9d45ec6ff64d1d51f6066e26492876ac7e95d3"
      ;;
    linux-aarch64)
      RUNTIME_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20240415/cpython-${PYTHON_RUNTIME_VERSION}+20240415-aarch64-unknown-linux-gnu-install_only.tar.gz"
      RUNTIME_SHA256="8290fe2f1d7ebf2d2a1cd3d2ed89e7836b6bc4a4ecb63e08e33af16dd4df26f1"
      ;;
    *)
      echo "error: installer-managed runtime not configured for ${PLATFORM_TUPLE}. Use --use-system-python." >&2
      exit 1
      ;;
  esac
  if [[ -n "${PYTHON_RUNTIME_URL}" && -z "${PYTHON_RUNTIME_SHA256}" ]]; then
    echo "error: --python-runtime-sha256 is required when --python-runtime-url is provided." >&2
    exit 1
  fi
  if [[ -n "${PYTHON_RUNTIME_URL}" ]]; then
    RUNTIME_URL="${PYTHON_RUNTIME_URL}"
    RUNTIME_SHA256="${PYTHON_RUNTIME_SHA256}"
  fi
  mkdir -p "${PREFIX}/runtime"
  RUNTIME_ARCHIVE="${PREFIX}/runtime/cpython-${PYTHON_RUNTIME_VERSION}-${PLATFORM_TUPLE}.tar.gz"

  download_runtime_archive() {
    local source="$1"
    local destination="$2"
    if [[ "${source}" =~ ^https?:// ]]; then
      local attempt=1 max_attempts=4 delay=2
      while [[ "${attempt}" -le "${max_attempts}" ]]; do
        if curl -fL --connect-timeout 15 --retry 0 --silent --show-error "${source}" -o "${destination}"; then
          return 0
        fi
        if [[ "${attempt}" -lt "${max_attempts}" ]]; then
          echo "warning: runtime download attempt ${attempt}/${max_attempts} failed; retrying in ${delay}s..." >&2
          sleep "${delay}"
          delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
      done
      cat >&2 <<ERR
error: failed to download Python runtime from ${source}.
remediation: verify network/proxy access, or host the runtime on an internal mirror and pass:
  --python-runtime-url <internal-url-or-local-file>
  --python-runtime-sha256 <expected-sha256>
ERR
      return 1
    fi

    local source_path="${source}"
    if [[ "${source}" =~ ^file:// ]]; then
      source_path="${source#file://}"
    fi
    if [[ ! -f "${source_path}" ]]; then
      echo "error: Python runtime file not found at ${source_path}" >&2
      echo "remediation: provide a valid local file path or accessible URL via --python-runtime-url." >&2
      return 1
    fi
    cp -f "${source_path}" "${destination}"
  }

  download_runtime_archive "${RUNTIME_URL}" "${RUNTIME_ARCHIVE}"
  ACTUAL_SHA256="$(sha256sum "${RUNTIME_ARCHIVE}" | awk '{print $1}')"
  [[ "${ACTUAL_SHA256}" == "${RUNTIME_SHA256}" ]] || {
    echo "error: checksum verification failed for managed runtime archive." >&2
    echo "expected: ${RUNTIME_SHA256}" >&2
    echo "actual  : ${ACTUAL_SHA256}" >&2
    cat >&2 <<'ERR'
remediation: do not continue with an unverified runtime.
re-download the exact Python 3.12.3 runtime artifact from a trusted source,
recompute SHA256, then rerun with --python-runtime-url and --python-runtime-sha256.
ERR
    exit 1
  }
  rm -rf "${RUNTIME_DIR}"
  mkdir -p "${RUNTIME_DIR}"
  tar -xzf "${RUNTIME_ARCHIVE}" -C "${RUNTIME_DIR}" --strip-components=1
  PYTHON_CMD="${RUNTIME_DIR}/bin/python3"
else
  if ! command -v python3 >/dev/null 2>&1; then
    cat >&2 <<'ERR'
error: python3 executable not found.
remediation: install Python 3.12.x and ensure python3 is on PATH, then rerun installer.
ERR
    exit 1
  fi
  PYTHON_CMD="$(command -v python3)"
fi

PYTHON_VERSION="$("${PYTHON_CMD}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')"
if ! "${PYTHON_CMD}" -c 'import sys; raise SystemExit(0 if (sys.version_info.major == 3 and sys.version_info.minor == 12) else 1)'; then
  cat >&2 <<ERR
error: incompatible Python version detected (${PYTHON_VERSION}).
remediation: install Python 3.12.x and make it the default python3 for this shell.
ERR
  exit 1
fi

if ! "${PYTHON_CMD}" -c 'import venv'; then
  cat >&2 <<'ERR'
error: Python "venv" module is unavailable.
remediation: install your distro's venv package (for example: python3-venv / python312-venv) and rerun.
ERR
  exit 1
fi

CONNECTIVITY_STATUS="skipped"
if [[ "${SKIP_CONNECTIVITY_CHECK}" -eq 0 ]]; then
  if "${PYTHON_CMD}" -c 'import socket; s=socket.create_connection(("pypi.org", 443), timeout=5); s.close()'; then
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
echo "  Install mode  : ${INSTALL_MODE}"
echo "  Platform tuple: ${PLATFORM_TUPLE}"
echo "  Python        : ${PYTHON_VERSION} (compatible)"
echo "  Python path   : ${PYTHON_CMD}"
echo "  venv module   : available"
echo "  Connectivity  : ${CONNECTIVITY_STATUS}"

VENV_DIR="${PREFIX}/.venv"
APP_DIR="${PREFIX}/app"
BIN_DIR="${PREFIX}/bin"
DATA_DIR="${PREFIX}/data"

mkdir -p "${PREFIX}" "${BIN_DIR}" "${DATA_DIR}"

"${PYTHON_CMD}" -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/python" -m pip install --upgrade pip
"${VENV_DIR}/bin/python" -m pip install -r "${SCRIPT_DIR}/requirements-3.12.3.txt"
if [[ "${SKIP_DOCTOR}" -eq 0 ]]; then
  echo "Running AVoc doctor checks..."
  (
    cd "${SCRIPT_DIR}"
    "${VENV_DIR}/bin/python" -m main --doctor
  ) || {
    cat >&2 <<'ERR'
error: AVoc doctor validation failed after dependency installation.
remediation:
  1) Verify NVIDIA driver compatibility (run: nvidia-smi).
  2) Reboot after driver updates.
  3) Reinstall dependencies and rerun installer.
  4) Advanced override only: rerun installer with --skip-doctor.
ERR
    exit 1
  }
else
  echo "warning: skipping AVoc doctor checks due to --skip-doctor"
fi

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
export HUGGINGFACE_HUB_CACHE="\${AVOC_DATA_DIR}/cache/huggingface/hub"
export TRANSFORMERS_CACHE="\${AVOC_DATA_DIR}/cache/huggingface/transformers"
export HF_DATASETS_CACHE="\${AVOC_DATA_DIR}/cache/huggingface/datasets"
export PIP_CACHE_DIR="\${AVOC_DATA_DIR}/cache/pip"

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
  printf '%s\n' "${DESKTOP_FILE}" >> "${MANIFEST_PATH}"
  echo "Created desktop shortcut: ${DESKTOP_FILE}"
fi

echo "Installed AVoc into ${PREFIX}"
echo "Installer mode : ${INSTALL_MODE}"
echo "Python path    : ${PYTHON_CMD}"
echo "Run: ${BIN_DIR}/avoc"
