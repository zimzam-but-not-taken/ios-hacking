#! /bin/bash

# GOAL: Move App to AppGroup Download Folder so Trollstore can see it / install
IPA_FILE_PATH=$1
IPA_NAME=$(basename "$IPA_FILE_PATH")   # extract just the filename from ./app.ipa or /full/path/app.ipa

BASE_PATH='/private/var/mobile/Containers/Shared/AppGroup'
# Passwordless auth via the device key, if present (override SSH_KEY="" to skip).
SSH_KEY="${SSH_KEY-$HOME/.ssh/ios_devices}"
KEY_OPT=""; [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ] && KEY_OPT="-i $SSH_KEY"
SSH_OPTS="-p 2222 $KEY_OPT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Find the helper (as root) and the Downloads folder — one match each
TROLL_STORE_HELPER=$(ssh $SSH_OPTS root@localhost "find /private/var/containers/Bundle/Application -path '*/TrollStore.app/trollstorehelper' 2>/dev/null | head -1")
COPY_TO=$(ssh $SSH_OPTS root@localhost "find '$BASE_PATH' -type d -name Downloads 2>/dev/null | head -1")

# Copy unsigned app into that folder (as mobile, which owns it — no root needed)
scp -P 2222 $KEY_OPT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$IPA_FILE_PATH" "mobile@localhost:$COPY_TO/"

# Install (must be root)
ssh $SSH_OPTS root@localhost "'$TROLL_STORE_HELPER' install force '$COPY_TO/$IPA_NAME'" \
    && echo "IPA File installed with Trollstore"
