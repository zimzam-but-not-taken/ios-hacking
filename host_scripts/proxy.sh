#!/bin/bash


# Check HTTP PROXY IS UP BEFORE PORT FOWARDING:
CAIDO_APP="/Applications/Proxy Tools/Caido.app"
CAIDO_PORT=8181
caido_up() { lsof -iTCP:${CAIDO_PORT} -sTCP:LISTEN -n -P >/dev/null 2>&1; }
if ! caido_up; then
  echo "proxy2phone: Caido not listening on ${CAIDO_PORT} — launching it..." >&2
  open -a "$CAIDO_APP" || { echo "proxy2phone: could not launch Caido ($CAIDO_APP)" >&2; exit 1; }
  echo "Likely need to open caido workspace to start request capture."
  for i in {1..150}; do caido_up && break; sleep 0.2; done
  if ! caido_up; then
    echo "proxy2phone: Caido never came up on ${CAIDO_PORT} (30s); aborting." >&2
    exit 1
  fi
  echo "proxy2phone: Caido is up on ${CAIDO_PORT}." >&2
fi

# Portfoward proxy 2 Phone Over SSH
ssh -p 2222 -f -N \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ExitOnForwardFailure=yes \
  -R 8080:127.0.0.1:${CAIDO_PORT} root@localhost
rc=$?

# Portfoward leaves the terminal hanging, so we background this. 
if [ $rc -eq 0 ]; then
  echo "proxy2phone: tunnel up (device :8080 -> Caido :${CAIDO_PORT}), backgrounded." >&2
else
  echo "proxy2phone: ssh failed (rc=$rc) — is device :8080 already bound by an old tunnel?" >&2
fi
exit $rc
