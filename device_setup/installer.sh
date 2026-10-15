#!/bin/bash
# Push the TrollDecrypt .deb, tool_install.sh and the zsh/p10k dotfiles to the
# device over SSH, then open a shell as mobile so you can run ~/tool_install.sh.
#
# Env overrides:
#   SSH_HOST  device SSH host  (default: localhost, via iproxy/connect.sh)
#   SSH_PORT  device SSH port  (default: 2222)
#   SSH_USER  device SSH user  (default: mobile)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_HOST="${SSH_HOST:-localhost}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_USER="${SSH_USER:-mobile}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

DEB="$SCRIPT_DIR/device_tools/com.fiore.trolldecrypt_1.2.4_iphoneos-arm64.deb"

# Copy over TrollDecrypt, the install script and the dotfiles (all land in ~).
scp -P "$SSH_PORT" "${SSH_OPTS[@]}" -r \
    "$DEB" \
    "$SCRIPT_DIR/tool_install.sh" \
    "$SCRIPT_DIR/dotfiles" \
    "$SSH_USER@$SSH_HOST:~/"

# SSH to the device to run tool_install.sh as the mobile user.
echo ">> Now run on the device:  bash ~/tool_install.sh"
ssh -p "$SSH_PORT" "${SSH_OPTS[@]}" "$SSH_USER@$SSH_HOST"
