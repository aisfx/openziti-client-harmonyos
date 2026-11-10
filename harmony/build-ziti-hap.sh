#!/bin/bash
# Build the HAP. Usage: ./build-ziti-hap.sh [clean]
cd "$(dirname "$0")"
export DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
export PATH="/c/Program Files/Huawei/DevEco Studio/jbr/bin:$PATH"
NODE="/c/Program Files/Huawei/DevEco Studio/tools/node/node.exe"
HVIGOR="/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js"

if [ "$1" = "clean" ]; then
  "$NODE" "$HVIGOR" clean --no-daemon >/dev/null 2>&1
fi

"$NODE" "$HVIGOR" --mode module -p module=entry@default assembleHap --no-daemon 2>&1 | grep -E "Error Message|BUILD"
ls -la entry/build/default/outputs/default/entry-default-signed.hap 2>/dev/null
