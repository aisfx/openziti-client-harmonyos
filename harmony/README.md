# openziti — HarmonyOS 客户端（harmony/）

DevEco Studio 工程入口。基于 OpenZiti 的鸿蒙客户端，仅连接 ziti 网络，无其他功能。

## 打开方式

1. DevEco Studio → Open → 本目录（`harmony/`）
2. 等待 Sync（hvigor 自动装 @ohos/hvigor-ohos-plugin）
3. 连接真机（HarmonyOS 5.0.5+），Run 'entry'

## 命令行构建（macOS）

```bash
./build-mac.sh install
```

首次使用需在 DevEco 中完成一次自动签名（File → Project Structure → Signing Configs）。

## 配置

首次启动出现设置面板，填：
- **Identity**: ziti 身份文件（identity.json）内容或路径
- TUN 参数一般用默认值（`100.64.0.1/10`，DNS `100.64.0.2`）

配置存 preferences，下次自动加载。

## 代码结构

```
entry/src/main/ets/
├── entryability/
│   ├── EntryAbility.ets            # UIAbility，加载 pages/Index
│   └── EntryAbilityStage.ets
├── model/
│   └── HubClient.ets               # 传输层抽象（预留）
├── pages/
│   └── Index.ets                   # VPN 开关 + 服务列表 UI
└── vpnextension/
    └── ZitiVpnExtensionAbility.ets # VpnExtensionAbility + TUN + libziti 拦截
```

`libziti_ohos.so`（NAPI 绑定）位于 `entry/oh_modules/`，由 libziti 交叉编译 OpenHarmony 产出。
