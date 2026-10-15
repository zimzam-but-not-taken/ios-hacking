#!/bin/bash
# Forward the device's SSH port to the host over USB with iproxy.
#
# Env overrides:
#   SSH_PORT     local port to listen on          (default: 2222)
#   DEVICE_PORT  SSH port on the device           (default: 22)
SSH_PORT="${SSH_PORT:-2222}"
DEVICE_PORT="${DEVICE_PORT:-22}"

command -v iproxy >/dev/null 2>&1 || { echo "connect: iproxy not found — install libimobiledevice (brew install libimobiledevice)." >&2; exit 1; }

# Connect device over USB:
if ! lsof -iTCP:"$SSH_PORT" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
  iproxy "$SSH_PORT" "$DEVICE_PORT" &>/dev/null &
else
  # Kill all iproxy & re-connect
  sudo killall iproxy
  iproxy "$SSH_PORT" "$DEVICE_PORT" &>/dev/null &
fi

# Wait up to ~15s for the port to actually accept connections.
for i in {1..5}; do
  if nc -z localhost "$SSH_PORT" 2>/dev/null; then
    echo "Device Connected"
    exit 0
  fi
  sleep $i
done

exit 1
