#!/bin/bash
# Reverse-forward the host HTTP proxy (Caido by default) to the device, so the
# phone can point its HTTP proxy at 127.0.0.1:DEVICE_PROXY_PORT.
#
# Env overrides:
#   PROXY_APP          macOS app to launch if the proxy isn't up  (default: Caido)
#                      a bare app name or a full /path/to/App.app both work with `open -a`
#   PROXY_PORT         proxy port on the host                     (default: 8181)
#   DEVICE_PROXY_PORT  port the proxy appears on, on the device   (default: 8080)
#   SSH_HOST / SSH_PORT / SSH_USER   device SSH (default: localhost / 2222 / root)
#   SSH_KEY            SSH private key (default: ~/.ssh/ios_devices; used if it exists)
PROXY_APP="${PROXY_APP:-Caido}"
PROXY_PORT="${PROXY_PORT:-8181}"
DEVICE_PROXY_PORT="${DEVICE_PROXY_PORT:-8080}"
SSH_HOST="${SSH_HOST:-localhost}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY-$HOME/.ssh/ios_devices}"
SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
[ -n "${SSH_KEY:-}" ] && [ -f "$SSH_KEY" ] && SSH_OPTS+=(-i "$SSH_KEY")

# Check the HTTP proxy is up before port forwarding:
proxy_up() { lsof -iTCP:"${PROXY_PORT}" -sTCP:LISTEN -n -P >/dev/null 2>&1; }
if ! proxy_up; then
  echo "proxy2phone: nothing listening on ${PROXY_PORT} — launching ${PROXY_APP}..." >&2
  open -a "$PROXY_APP" || { echo "proxy2phone: could not launch ${PROXY_APP} (set PROXY_APP to the app name or path)" >&2; exit 1; }
  echo "You may need to open a workspace in the proxy app to start request capture."
  for i in {1..150}; do proxy_up && break; sleep 0.2; done
  if ! proxy_up; then
    echo "proxy2phone: ${PROXY_APP} never came up on ${PROXY_PORT} (30s); aborting." >&2
    exit 1
  fi
  echo "proxy2phone: ${PROXY_APP} is up on ${PROXY_PORT}." >&2
fi

# Port-forward proxy to phone over SSH (-f -N backgrounds it, otherwise the terminal hangs).
ssh "${SSH_OPTS[@]}" -f -N \
  -o ExitOnForwardFailure=yes \
  -R "${DEVICE_PROXY_PORT}:127.0.0.1:${PROXY_PORT}" "${SSH_USER}@${SSH_HOST}"
rc=$?

if [ $rc -eq 0 ]; then
  echo "proxy2phone: tunnel up (device :${DEVICE_PROXY_PORT} -> host :${PROXY_PORT}), backgrounded." >&2
else
  echo "proxy2phone: ssh failed (rc=$rc) — is device :${DEVICE_PROXY_PORT} already bound by an old tunnel?" >&2
fi
exit $rc
