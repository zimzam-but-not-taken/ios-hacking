#! /bin/bash

# GOAL: Script the whole decrypt-and-pull loop with no on-device UI.
#       Enumerate the apps installed on the device, pick one or many from a
#       numbered menu, then decrypt each and drop the resulting .ipa straight
#       into the working directory.
#
#       This replaces the TrollDecrypt (GUI) + pull_from_device.sh two-step.
#       TrollDecrypt 1.2.4 has no CLI and no URL scheme -- it can only be driven
#       by tapping in the app -- so decryption here is done with frida-ios-dump
#       (AloneMonkey), which decrypts and copies the IPA back in one shot.
#
# Usage:
#   decrypt_and_pull.sh [local_dest]
#   decrypt_and_pull.sh -t <bundleid|name> [-t ...] [local_dest]   # non-interactive
#
#   local_dest   where to drop the .ipa file(s)   (default: current directory)
#   -t TARGET    skip the menu, dump this bundle id or display name (repeatable)
#   -l           just list installed apps and exit
#
# Examples:
#   decrypt_and_pull.sh                         # menu -> ./
#   decrypt_and_pull.sh ~/Target_IPAs           # menu -> ~/Target_IPAs
#   decrypt_and_pull.sh -t com.apple.Maps       # dump one app -> ./
#
# Env overrides (defaults match the rest of host_scripts/):
#   SSH_PORT   device SSH port        (default: 2222, via iproxy/connect.sh)
#   SSH_HOST   device SSH host        (default: localhost)
#   SSH_USER   device SSH user        (default: root)
#   SSH_KEY    SSH private key for passwordless auth
#              (default: ~/.ssh/ios_devices; used if the file exists)
#   SSH_PASS   device SSH password    (fallback if no key; else dump.py's 'alpine')
#   DUMP_PY    path to frida-ios-dump dump.py
#              (default: <repo>/frida/ios-dump/dump.py, the frida-17 port in this repo)
#   PYTHON     python interpreter with frida+paramiko+scp+tqdm
#              (default: python3, else the python behind the `frida` CLI)

set -euo pipefail

# --- config ------------------------------------------------------------------
SSH_HOST="${SSH_HOST:-localhost}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_USER="${SSH_USER:-root}"
# Passwordless by default: the device's key. frida-server runs as root, so root
# is the safe default user (can read every app container). SSH_USER=mobile works
# too. Override SSH_KEY="" to force password auth.
SSH_KEY="${SSH_KEY-$HOME/.ssh/ios_devices}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Runnable frida-ios-dump tool (built agent + driver) lives in frida/ios-dump/.
# Rebuild its agent with: cd frida/ios-dump && npm run build
DUMP_PY="${DUMP_PY:-$REPO_ROOT/frida/ios-dump/dump.py}"

PYTHON="${PYTHON:-python3}"
# True if "$1" is a python with the real frida module. (Checks __version__ so
# the repo's own frida/ folder, which python picks up as an empty package when
# run from the repo root, doesn't count.)
has_frida() { "$1" -c 'import frida; frida.__version__' >/dev/null 2>&1; }
# If $PYTHON lacks frida, fall back to whichever python the frida CLI tools
# were installed into (pip/pipx/brew all leave a shebang).
if ! has_frida "$PYTHON"; then
    for tool in frida frida-ps; do
        tool_path="$(command -v "$tool" 2>/dev/null)" || continue
        cand="$(sed -n '1s/^#! *//p' "$tool_path")"
        if [ -x "$cand" ] && has_frida "$cand"; then
            PYTHON="$cand"; break
        fi
    done
fi
if ! has_frida "$PYTHON"; then
    echo "!! No python with the frida module found. Install the deps:"
    echo "   pip install -r '$REPO_ROOT/frida/ios-dump/requirements.txt'"
    echo "   or set PYTHON=/path/to/python that has them."
    exit 1
fi

# --- args --------------------------------------------------------------------
TARGETS=()          # explicit -t targets (non-interactive)
LIST_ONLY=0
LOCAL_DEST=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        -t) shift; [ "$#" -gt 0 ] || { echo "!! -t needs a value"; exit 2; }; TARGETS+=("$1") ;;
        -l) LIST_ONLY=1 ;;
        -h|--help) sed -n '3,40p' "$0"; exit 0 ;;
        -*) echo "!! unknown option: $1"; exit 2 ;;
        *)  LOCAL_DEST="$1" ;;
    esac
    shift
done
LOCAL_DEST="${LOCAL_DEST:-$PWD}"

# --- preflight ---------------------------------------------------------------
if [ ! -f "$DUMP_PY" ]; then
    echo "!! dump.py not found at: $DUMP_PY"
    echo "   Build the agent:  cd '$REPO_ROOT/frida/ios-dump' && npm install && npm run build"
    echo "   or point DUMP_PY at another copy."
    exit 1
fi

# Build the auth + connection args passed to dump.py.
DUMP_ARGS=(-H "$SSH_HOST" -p "$SSH_PORT" -u "$SSH_USER")
if [ -n "${SSH_KEY:-}" ] && [ -f "$SSH_KEY" ]; then
    DUMP_ARGS+=(-K "$SSH_KEY")           # passwordless: key auth
    echo ">> Auth   : key ${SSH_KEY}"
elif [ -n "${SSH_PASS:-}" ]; then
    DUMP_ARGS+=(-P "$SSH_PASS")          # password auth
    echo ">> Auth   : password"
else
    echo ">> Auth   : dump.py default password ('alpine')"
fi
# (SSH_KEY set but missing file -> fall through to password; SSH_KEY="" forces it.)

# --- make sure the device is reachable on SSH_PORT --------------------------
ensure_connected() {
    if nc -z "$SSH_HOST" "$SSH_PORT" 2>/dev/null; then
        return 0
    fi
    echo ">> Port ${SSH_PORT} not open; trying connect.sh (iproxy)..."
    if [ -x "$SCRIPT_DIR/connect.sh" ]; then
        "$SCRIPT_DIR/connect.sh" || true
    fi
    if ! nc -z "$SSH_HOST" "$SSH_PORT" 2>/dev/null; then
        echo "!! Can't reach ${SSH_HOST}:${SSH_PORT}. Is the device plugged in and iproxy running?"
        exit 1
    fi
}

echo ">> Device : ${SSH_USER}@${SSH_HOST} (port ${SSH_PORT})"
echo ">> dump.py: ${DUMP_PY}"
echo ">> Save to: ${LOCAL_DEST}"
echo
ensure_connected
mkdir -p "$LOCAL_DEST"

# --- enumerate installed apps (via dump.py -l) -------------------------------
# dump.py -l prints:  PID  Name  Identifier   (columns space-padded).
# The bundle id never contains spaces, so it is reliably the last field.
LISTING="$("$PYTHON" "$DUMP_PY" "${DUMP_ARGS[@]}" -l 2>/dev/null || true)"
if [ -z "$LISTING" ]; then
    echo "!! Got no app list back from dump.py."
    echo "   Check that frida-server is running on the device and that its"
    echo "   version matches the host frida ($("$PYTHON" -c 'import frida;print(frida.__version__)' 2>/dev/null || echo '?'))."
    exit 1
fi

if [ "$LIST_ONLY" -eq 1 ]; then
    echo "$LISTING"
    exit 0
fi

# Parse the listing into parallel arrays (skip the 2 header lines).
NAMES=()
IDS=()
while IFS= read -r line; do
    [ -n "$line" ] || continue
    # dump.py right-justifies the PID column, so the header can start with
    # spaces (" PID ..."). Trim before testing so the header row is skipped.
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in PID*) continue ;; esac   # header row
    # Separator row is only dashes and spaces; a not-running app's PID is a
    # lone "-" followed by its name, so match the all-dashes line exactly.
    [[ "$trimmed" =~ ^[-\ ]+$ ]] && continue
    # id = last whitespace-delimited field; name = everything between col 1 and id.
    id="$(awk '{print $NF}' <<<"$line")"
    name="$(awk '{ $1=""; $NF=""; sub(/^ +/,""); sub(/ +$/,""); print }' <<<"$line")"
    [ -n "$id" ] || continue
    IDS+=("$id")
    NAMES+=("$name")
done <<<"$LISTING"

if [ "${#IDS[@]}" -eq 0 ]; then
    echo "!! No apps parsed from the device listing."
    exit 1
fi

# --- decrypt one target: runs dump.py with cwd = LOCAL_DEST so the IPA lands there
dump_one() {
    local target="$1" label="$2" safe
    safe="$(printf '%s' "$label" | tr ' /:' '___')"
    echo
    echo ">> Decrypting: ${label}  (${target})"
    # dump.py writes "<-o name>.ipa" into its CWD, so run it inside LOCAL_DEST.
    # dump.py exits 0 even when the dump fails on-device, so check the file too.
    if ( cd "$LOCAL_DEST" && "$PYTHON" "$DUMP_PY" "${DUMP_ARGS[@]}" -o "$safe" "$target" ) \
        && [ -s "$LOCAL_DEST/$safe.ipa" ]; then
        echo ">> OK: ${LOCAL_DEST}/${safe}.ipa"
        return 0
    else
        echo "!! FAILED: ${label} (${target}) -- no IPA written"
        return 1
    fi
}

# --- non-interactive path (-t) ----------------------------------------------
if [ "${#TARGETS[@]}" -gt 0 ]; then
    ok=0; fail=0
    for t in "${TARGETS[@]}"; do
        if dump_one "$t" "$t"; then ok=$((ok+1)); else fail=$((fail+1)); fi
    done
    echo
    echo ">> Done. ${ok} decrypted, ${fail} failed -> ${LOCAL_DEST}"
    exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
fi

# --- interactive menu --------------------------------------------------------
echo "Installed apps:"
for i in "${!IDS[@]}"; do
    printf "   [%3d] %-38s %s\n" "$((i + 1))" "${NAMES[i]}" "${IDS[i]}"
done
echo "   [  a] all"
echo
read -rp "Select app(s) to decrypt (e.g. 1 4 7) or 'a': " -a CHOICES

if [ "${#CHOICES[@]}" -eq 0 ]; then
    echo ">> Nothing selected."
    exit 0
fi
if [ "${#CHOICES[@]}" -eq 1 ] && [ "${CHOICES[0]}" = "a" ]; then
    CHOICES=(); for i in "${!IDS[@]}"; do CHOICES+=("$((i + 1))"); done
fi

ok=0; fail=0
for n in "${CHOICES[@]}"; do
    if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt "${#IDS[@]}" ]; then
        echo "   -- skipping invalid choice: $n"
        continue
    fi
    idx=$((n - 1))
    if dump_one "${IDS[idx]}" "${NAMES[idx]}"; then ok=$((ok+1)); else fail=$((fail+1)); fi
done

echo
echo ">> Done. ${ok} decrypted, ${fail} failed -> ${LOCAL_DEST}"
ls -lht "$LOCAL_DEST"/*.ipa 2>/dev/null | head -n "$((ok + 1))" | sed 's/^/   /' || true
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
