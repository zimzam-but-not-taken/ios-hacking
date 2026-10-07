#! /bin/bash

# Copy Over Troll Decrypt
scp -P 2222 \
    /Users/voidcl1ck/.tools/ios-hacking/device_setup/device_tools/com.fiore.trolldecrypt_1.2.4_iphoneos-arm64.deb \ 
    mobile@localhost:~/

# Copy Over Install Script
scp -P 2222 \
    /Users/voidcl1ck/.tools/ios-hacking/device_setup/tool_install.sh \
    mobile@localhost:~/

# SSH to Box to Run Tool_Install as mobile user. 
 ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null mobile@localhost
