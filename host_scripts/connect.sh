#!/bin/bash

# Connect Device Over USB:
if ! lsof -iTCP:2222 -sTCP:LISTEN -n -P >/dev/null 2>&1; then
  iproxy 2222 22 &>/dev/null &
else
  # Kill all iproxy & Re-connect
  sudo killall iproxy
  iproxy 2222 22 &>/dev/null &
fi

# Wait up to ~5s for the port to actually accept connections.
for i in {1..5}; do
  if nc -z localhost 2222 2>/dev/null; then
    echo "Device Connected"
    exit 0
  fi
  sleep $i
done

exit 1
