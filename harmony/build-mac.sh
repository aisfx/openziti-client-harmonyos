#!/bin/bash
# macOS 一键构建 + 签名 + 安装到鸿蒙平板
# 用法:
#   ./build-mac.sh            # 编译 + 签名（DevEco 自动签名材料）
#   ./build-mac.sh install    # 再安装到 192.168.18.32:41285 并启动
#   ./build-mac.sh clean      # 先 clean 再编译
set -e
cd "$(dirname "$0")"

export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
NODE=/Applications/DevEco-Studio.app/Contents/tools/node/bin/node
HVIGOR=/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js

# 平板连接（hdc 无线）
export HDC_SERVER_PORT=7035
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
TARGET=${PAD_TARGET:-192.168.18.32:41285}

if [ "$1" = "clean" ]; then
  "$NODE" "$HVIGOR" clean --no-daemon >/dev/null 2>&1
fi

echo "== 编译 =="
"$NODE" "$HVIGOR" --mode module -p module=entry@default assembleHap --no-daemon 2>&1 | grep -E "BUILD|ERROR"
HAP=entry/build/default/outputs/default/entry-default-signed.hap
ls -la "$HAP"

if [ "$1" = "install" ] || [ "$2" = "install" ]; then
  echo "== 连接平板 =="
  "$HDC" tconn "$TARGET" || true
  echo "== 安装 =="
  "$HDC" -t "$TARGET" install -r "$HAP"
  echo "== 启动 =="
  "$HDC" -t "$TARGET" shell "aa start -a EntryAbility -b com.example.myapplication"
fi
