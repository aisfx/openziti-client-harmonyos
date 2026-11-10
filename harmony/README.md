# hm-agent HarmonyOS App (harmony/)

DevEco Studio 工程入口。手机直连内网 hub（`D:\workspace\hm-agent\hub`）。

## 打开方式

1. DevEco Studio → Open → `D:\workspace\hm-agent\harmony`
2. 等待 Sync（hvigor 会自动装 @ohos/hvigor-ohos-plugin）
3. 接真机/模拟器（HarmonyOS 5.0.5+），Run 'entry'

## 配置

首次启动出现设置面板，填：
- **服务器**: hub 所在机器的局域网地址，如 `ws://192.168.1.100:8787/ws`
- **token**: agents.yaml 里的 `server.token`（默认 change-me）

配置存在 preferences（hm_agent_store），下次自动重连。

## 代码结构

```
entry/src/main/ets/
├── entryability/
│   ├── EntryAbility.ets      # UIAbility，加载 pages/Index
│   └── EntryAbilityStage.ets
├── model/
│   └── HubClient.ets          # 传输层抽象（WebSocket 实现；未来 Ziti 在此替换）
└── pages/
    └── Index.ets              # 侧边栏 + 终端风聊天 UI
```

## Ziti 替换点

`HubClient` 是唯一的传输依赖。未来接入 Ziti app-embedded 模式时：
- 新增 `ZitiHubClient` 实现（NAPI 调 libziti，本地回环暴露 ws 代理）
- `Index.ets` 里 `new HubClient()` 换成新实现即可，UI 零改动
