#!/bin/bash
# 手动签名 hm-agent HAP（复用 pi-tv-scan 的 auto-sign 材料）
set -x
CFG="C:/Users/sunfx/.ohos/config"
JAVA="C:/Program Files/Huawei/DevEco Studio/jbr/bin/java.exe"
JAR="C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"
HAP="entry/build/default/outputs/default/entry-default-unsigned.hap"
OUT="entry/build/default/outputs/default/entry-default-signed.hap"
BASE="$CFG/default_pi-tv-scan_1hdep72fXORSfDmWe91PLi6-DGp41bocRnL1vb5r4JY="

for pwd in "123456" "123456Abc" "ide123456" "huawei123"; do
  echo "== try: $pwd =="
  "$JAVA" -jar "$JAR" sign-app \
    -keyAlias "debug_ohos" -keyPwd "$pwd" -keystorePwd "$pwd" \
    -signAlg SHA256withECDSA -mode localSignature \
    -signCert "${BASE}.cer" -profileFile "${BASE}.p7b" \
    -inFile "$HAP" -outFile "$OUT" 2>&1 | tail -3
  if [ -f "$OUT" ]; then echo "SIGNED_OK with $pwd"; break; fi
done
