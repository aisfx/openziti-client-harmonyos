#!/bin/bash
# hm-agent 调试签名（OpenHarmony hapsigner 官方标准流程）
# 参考 hapsigner README: 用官方 OpenHarmony.p12 + OpenHarmonyProfileDebug.pem
set -e
SDK="C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony"
JAVA="C:/Program Files/Huawei/DevEco Studio/jbr/bin/java.exe"
JAR="$SDK/toolchains/lib/hap-sign-tool.jar"
LIB="$SDK/toolchains/lib"
OUT="build-sign"
BUNDLE="com.example.myapplication"
cd "$(dirname "$0")"
mkdir -p "$OUT"

KEY_ALIAS="openharmony application profile debug"
PEM="$LIB/OpenHarmonyProfileDebug.pem"

# 1. profile p7b（debug 模板 + bundleName）
py - "$LIB/UnsgnedDebugProfileTemplate.json" "$OUT/profile.json" "$BUNDLE" <<'EOF'
import json, sys
tpl = json.load(open(sys.argv[1], encoding='utf-8'))
tpl['bundle-info']['bundle-name'] = sys.argv[3]
json.dump(tpl, open(sys.argv[2], 'w', encoding='utf-8'), indent=2)
print('PROFILE_JSON_OK')
EOF

"$JAVA" -jar "$JAR" sign-profile \
  -mode localSign \
  -keyAlias "$KEY_ALIAS" -keyPwd 123456 \
  -signAlg SHA256withECDSA \
  -profileCertFile "$PEM" \
  -inFile "$OUT/profile.json" \
  -keystoreFile "$LIB/OpenHarmony.p12" -keystorePwd 123456 \
  -outFile "$OUT/hm-debug-profile.p7b" && echo "PROFILE_P7B_OK"

# 2. 签 HAP
"$JAVA" -jar "$JAR" sign-app \
  -mode localSign \
  -keyAlias "$KEY_ALIAS" -keyPwd 123456 \
  -signAlg SHA256withECDSA \
  -appCertFile "$PEM" \
  -profileFile "$OUT/hm-debug-profile.p7b" \
  -inFile "entry/build/default/outputs/default/entry-default-unsigned.hap" \
  -keystoreFile "$LIB/OpenHarmony.p12" -keystorePwd 123456 \
  -compatibleVersion 12 \
  -outFile "entry/build/default/outputs/default/entry-default-signed.hap" && echo "HAP_SIGNED_OK"
