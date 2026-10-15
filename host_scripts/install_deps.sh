#!/bin/bash
# Install everything the host-side scripts need. macOS + Homebrew only.
#
# Usage:
#   install_deps.sh              # brew formulas + frida tools + agent build toolchain
#   install_deps.sh --caido      # ... and the Caido proxy (brew cask)
#   install_deps.sh -n           # dry run: print what would be done
#
# Env overrides:
#   FRIDA_VERSION   pin the host frida to the device's frida-server version
#                   (e.g. FRIDA_VERSION=17.2.5). Default: whatever pip resolves.
#
# What gets installed:
#   brew   libimobiledevice (iproxy)  sshpass  node  pipx
#   pipx   frida-tools (+ paramiko, scp, tqdm injected for frida/ios-dump/dump.py)
#   npm    frida/ios-dump/ build deps (frida-compile, frida-objc-bridge)
#   cask   caido (only with --caido)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY=0
WITH_CAIDO=0
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY=1 ;;
        --caido)      WITH_CAIDO=1 ;;
        -h|--help)    sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "!! unknown option: $arg"; exit 2 ;;
    esac
done

run() { echo ">> $*"; [ "$DRY" -eq 1 ] || "$@"; }

# --- brew -------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    echo "!! Homebrew not found. Install it first: https://brew.sh"
    exit 1
fi

FORMULAS=(libimobiledevice sshpass node pipx)
for f in "${FORMULAS[@]}"; do
    if brew list --formula "$f" >/dev/null 2>&1; then
        echo "-- $f already installed"
    else
        run brew install "$f"
    fi
done

if [ "$WITH_CAIDO" -eq 1 ]; then
    if brew list --cask caido >/dev/null 2>&1 || [ -d "/Applications/Caido.app" ]; then
        echo "-- caido already installed"
    else
        run brew install --cask caido
    fi
fi

# --- frida + python deps (via pipx so the CLI lands on PATH) ----------------
# decrypt_and_pull.sh finds its python by following the `frida` CLI shebang,
# so anything that puts a working frida-tools on PATH is enough. Skip if one
# already exists with all of dump.py's deps.
has_deps() { "$1" -c 'import frida, paramiko, scp, tqdm; frida.__version__' >/dev/null 2>&1; }
existing_ok=0
if tool_path="$(command -v frida 2>/dev/null)"; then
    cand="$(sed -n '1s/^#! *//p' "$tool_path")"
    if [ -x "$cand" ] && has_deps "$cand"; then
        existing_ok=1
        echo "-- frida $("$cand" -c 'import frida;print(frida.__version__)') + deps already present ($cand)"
    fi
fi
if [ "$existing_ok" -eq 0 ]; then
    run pipx install frida-tools
    if [ -n "${FRIDA_VERSION:-}" ]; then
        run pipx inject --force frida-tools "frida==${FRIDA_VERSION}"
    fi
    run pipx inject frida-tools paramiko scp tqdm
    run pipx ensurepath
fi

# --- node toolchain for rebuilding the frida agent --------------------------
if [ -d "$REPO_ROOT/frida/ios-dump/node_modules" ]; then
    echo "-- frida/ios-dump node_modules already present"
else
    run npm --prefix "$REPO_ROOT/frida/ios-dump" install
fi

echo
echo ">> Done. Next: host_scripts/link_bin.sh, then usb_connect_port with the device plugged in."
[ "$existing_ok" -eq 1 ] || echo "   (open a new shell so pipx's bin dir is on PATH)"
echo "   Host frida must match the device's frida-server; re-run with FRIDA_VERSION=x.y.z to pin it."
