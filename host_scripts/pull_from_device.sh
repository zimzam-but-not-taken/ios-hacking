#! /bin/bash

# GOAL: Browse a folder on the iOS device over SSH, pick file(s), and copy them
#       to a local directory on the host. Defaults to TrollDecrypt's output
#       folder so you can grab decrypted IPAs after decrypting them in the app.
#
# Usage:
#   pull_from_device.sh [remote_dir] [local_dest]
#
#   remote_dir   folder on the device to list   (default: TrollDecrypt output)
#   local_dest   where to drop the file(s)      (default: current directory)
#
# Examples:
#   pull_from_device.sh                         # list decrypted IPAs -> ./
#   pull_from_device.sh /var/mobile/Documents   # list that folder    -> ./
#   pull_from_device.sh "" ~/Target_IPAs        # default folder      -> ~/Target_IPAs

set -euo pipefail

# --- connection (matches ts_install.sh) -------------------------------------
SSH_HOST="${SSH_HOST:-root@localhost}"
SSH_PORT="${SSH_PORT:-2222}"
# Passwordless auth via the device key, if present (override SSH_KEY="" to skip).
SSH_KEY="${SSH_KEY-$HOME/.ssh/ios_devices}"
# -n keeps these remote-command ssh calls from draining our stdin, so the
# interactive selection prompt (read) still gets the user's keystrokes.
SSH_OPTS=(-n -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8)
SCP_OPTS=(-P "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8)
if [ -n "${SSH_KEY:-}" ] && [ -f "$SSH_KEY" ]; then
    SSH_OPTS+=(-i "$SSH_KEY")
    SCP_OPTS+=(-i "$SSH_KEY")
fi

# --- args --------------------------------------------------------------------
REMOTE_DIR="${1:-/private/var/mobile/Documents/TrollDecrypt}"
LOCAL_DEST="${2:-$PWD}"
[ -z "$REMOTE_DIR" ] && REMOTE_DIR="/private/var/mobile/Documents/TrollDecrypt"   # allow "" placeholder

mkdir -p "$LOCAL_DEST"

echo ">> Device : ${SSH_HOST} (port ${SSH_PORT})"
echo ">> Folder : ${REMOTE_DIR}"
echo ">> Save to: ${LOCAL_DEST}"
echo

# --- sanity: does the remote folder exist? ----------------------------------
if ! ssh "${SSH_OPTS[@]}" "$SSH_HOST" "test -d '$REMOTE_DIR'" 2>/dev/null; then
    echo "!! Remote folder not found: $REMOTE_DIR"
    echo "   (If this is the TrollDecrypt folder, decrypt an app in the app first --"
    echo "    it is created on the first successful decryption.)"
    exit 1
fi

# --- show a human-readable listing for context ------------------------------
echo "Contents:"
ssh "${SSH_OPTS[@]}" "$SSH_HOST" "ls -lh '$REMOTE_DIR'" 2>/dev/null | grep -v '^total' | sed 's/^/   /'
echo

# --- collect just the file names (skip subdirectories) ----------------------
#  ls -1p marks directories with a trailing slash; grep -v '/$' drops them.
#  (while-read loop instead of mapfile: macOS ships bash 3.2, which has neither
#   mapfile nor readarray.)
FILES=()
while IFS= read -r line; do
    [ -n "$line" ] && FILES+=("$line")
done < <(ssh "${SSH_OPTS[@]}" "$SSH_HOST" "cd '$REMOTE_DIR' && ls -1p" 2>/dev/null | grep -v '/$')

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "!! No files to copy in $REMOTE_DIR"
    exit 1
fi

# --- numbered menu -----------------------------------------------------------
echo "Select file(s) to copy:"
for i in "${!FILES[@]}"; do
    printf "   [%2d] %s\n" "$((i + 1))" "${FILES[i]}"
done
echo "   [ a] all"
echo
read -rp "Enter number(s) (e.g. 1 3) or 'a': " -a CHOICES

# 'a' expands to every index
if [ "${#CHOICES[@]}" -eq 1 ] && [ "${CHOICES[0]}" = "a" ]; then
    CHOICES=(); for i in "${!FILES[@]}"; do CHOICES+=("$((i + 1))"); done
fi

# --- validate + copy ---------------------------------------------------------
copied=0
for n in "${CHOICES[@]}"; do
    if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt "${#FILES[@]}" ]; then
        echo "   -- skipping invalid choice: $n"
        continue
    fi
    fname="${FILES[$((n - 1))]}"
    echo ">> Copying: $fname"
    # Modern scp (OpenSSH 9+) uses SFTP: pass the remote path as one argument,
    # no extra quoting -- spaces are carried by the double-quoted shell arg.
    scp "${SCP_OPTS[@]}" "$SSH_HOST:$REMOTE_DIR/$fname" "$LOCAL_DEST/"
    copied=$((copied + 1))
done

echo
echo ">> Done. $copied file(s) copied to: $LOCAL_DEST"
# Show what landed, newest first.
ls -lht "$LOCAL_DEST" | grep -v '^total' | head -n $((copied + 1)) | sed 's/^/   /'
