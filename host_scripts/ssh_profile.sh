#!/bin/bash
# One-time setup: install an SSH key for mobile + root on the iOS test device
# (localhost:2222 over iproxy) and add scoped ~/.ssh/config aliases, so you
# never type the device password again.
#
# Usage:
#   ssh_profile.sh                 # prompts for the device password (hidden)
#   IOS_SSH_PASS=xxxx ssh_profile.sh   # non-interactive
#
# After running:   ssh phone        (mobile)      ssh phone-root   (root)
#                  scp file phone:/path/...
set -euo pipefail

# --- config -----------------------------------------------------------------
HOST=localhost
PORT=2222
KEY="$HOME/.ssh/ios_devices"
USERS=(mobile root)
SSH_CFG="$HOME/.ssh/config"
BEGIN="# >>> ios_devices (ssh_profile.sh) >>>"
END="# <<< ios_devices (ssh_profile.sh) <<<"

# password auth only for the install step (key isn't there yet)
PW_OPTS=(-p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         -o PubkeyAuthentication=no -o PreferredAuthentications=password \
         -o ConnectTimeout=8)

# --- prerequisites ----------------------------------------------------------
command -v sshpass >/dev/null 2>&1 || { echo "ssh_profile: sshpass not found — run 'brew install sshpass' first." >&2; exit 1; }
nc -z "$HOST" "$PORT" 2>/dev/null || { echo "ssh_profile: nothing on $HOST:$PORT — start the tunnel (usb_connect_port) first." >&2; exit 1; }

# --- password ---------------------------------------------------------------
PASS="${IOS_SSH_PASS:-}"
if [ -z "$PASS" ]; then
  read -r -s -p "Device SSH password (same for mobile & root): " PASS; echo
fi
[ -n "$PASS" ] || { echo "ssh_profile: no password given." >&2; exit 1; }

# --- key --------------------------------------------------------------------
if [ ! -f "$KEY" ]; then
  echo "ssh_profile: generating key $KEY"
  ssh-keygen -t ed25519 -N "" -C "ios-testing" -f "$KEY" >/dev/null
fi
PUBKEY=$(cat "$KEY.pub")

# --- install key for each user ---------------------------------------------
for u in "${USERS[@]}"; do
  echo "ssh_profile: installing key for $u@$HOST:$PORT"
  sshpass -p "$PASS" ssh "${PW_OPTS[@]}" "$u@$HOST" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && grep -qxF '$PUBKEY' ~/.ssh/authorized_keys || echo '$PUBKEY' >> ~/.ssh/authorized_keys"
done
unset PASS   # don't keep the password around

# --- write scoped ssh config block (idempotent) -----------------------------
touch "$SSH_CFG"; chmod 600 "$SSH_CFG"
if grep -qF "$BEGIN" "$SSH_CFG"; then
  awk -v b="$BEGIN" -v e="$END" '$0==b{s=1} s==0{print} $0==e{s=0}' "$SSH_CFG" > "$SSH_CFG.tmp" && mv "$SSH_CFG.tmp" "$SSH_CFG"
fi
printf '\n%s\n' "$BEGIN" >> "$SSH_CFG"
cat >> "$SSH_CFG" <<EOF
# iOS test device over iproxy — $HOST:$PORT. Key: $KEY
# Attaching the key to the hostname means your normal commands just work, no alias:
#   ssh -p $PORT ... mobile@$HOST   and   root@$HOST
Host $HOST
    IdentityFile $KEY
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# Optional shortcuts that also set the port + user: 'ssh phone' / 'ssh phone-root'
Host phone
    HostName $HOST
    Port $PORT
    User mobile
    IdentityFile $KEY
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host phone-root
    HostName $HOST
    Port $PORT
    User root
    IdentityFile $KEY
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
$END
EOF

# --- verify keyless login ---------------------------------------------------
echo "ssh_profile: verifying keyless login..."
for a in phone phone-root; do
  if ssh -o BatchMode=yes -o ConnectTimeout=8 "$a" 'echo ok' >/dev/null 2>&1; then
    echo "  $a: OK (no password)"
  else
    echo "  $a: FAILED — key auth not working" >&2
  fi
done

echo "ssh_profile: done. Use 'ssh phone' (mobile) or 'ssh phone-root' (root)."
