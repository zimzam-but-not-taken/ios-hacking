#!/bin/bash
# GOAL: Copy an IPA into TrollStore's app-group Downloads folder on the device
#       and install it with trollstorehelper.
#
# Usage:
#   ts_install.sh <path/to/app.ipa>
#
# Env overrides:
#   SSH_HOST / SSH_PORT   device SSH (default: localhost / 2222)
#   SSH_KEY               SSH private key (default: ~/.ssh/ios_devices; used if it exists)
set -euo pipefail

IPA_FILE_PATH="${1:-}"
[ -n "$IPA_FILE_PATH" ] && [ -f "$IPA_FILE_PATH" ] || { echo "usage: ts_install.sh <path/to/app.ipa>" >&2; exit 2; }
IPA_NAME=$(basename "$IPA_FILE_PATH")

SSH_HOST="${SSH_HOST:-localhost}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_KEY="${SSH_KEY-$HOME/.ssh/ios_devices}"
BASE_PATH='/private/var/mobile/Containers/Shared/AppGroup'

SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
SCP_OPTS=(-P "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
if [ -n "${SSH_KEY:-}" ] && [ -f "$SSH_KEY" ]; then
    SSH_OPTS+=(-i "$SSH_KEY")
    SCP_OPTS+=(-i "$SSH_KEY")
fi

# Find the helper (as root) and the Downloads folder — one match each
TROLL_STORE_HELPER=$(ssh "${SSH_OPTS[@]}" "root@$SSH_HOST" "find /private/var/containers/Bundle/Application -path '*/TrollStore.app/trollstorehelper' 2>/dev/null | head -1")
COPY_TO=$(ssh "${SSH_OPTS[@]}" "root@$SSH_HOST" "find '$BASE_PATH' -type d -name Downloads 2>/dev/null | head -1")
[ -n "$TROLL_STORE_HELPER" ] || { echo "ts_install: trollstorehelper not found on device — is TrollStore installed?" >&2; exit 1; }
[ -n "$COPY_TO" ] || { echo "ts_install: TrollStore Downloads folder not found on device." >&2; exit 1; }

# Copy the app into that folder (as mobile, which owns it — no root needed)
scp "${SCP_OPTS[@]}" "$IPA_FILE_PATH" "mobile@$SSH_HOST:$COPY_TO/"

# Install (must be root)
ssh "${SSH_OPTS[@]}" "root@$SSH_HOST" "'$TROLL_STORE_HELPER' install force '$COPY_TO/$IPA_NAME'" \
    && echo "IPA file installed with TrollStore"
