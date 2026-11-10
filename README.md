# hm-agent

鸿蒙手机 App + 内网 pi 智能体网关。手机端通过 Ziti（或直连）访问内网 agent-hub，
hub 用 pi 的 RPC 模式作为大脑，一个 App 侧边栏切换多个智能体。

## 目录结构

```
hm-agent/
├── docs/
│   └── ziti-ohos-feasibility.md  # Ziti 交叉编译 OHOS 可行性研究 ✅
├── hub/                 # 内网网关（Node.js，先跑通这个）
│   ├── agents.yaml      # 智能体配置（title/model/cwd/systemAddendum）
│   ├── src/
│   │   ├── server.mjs       # WebSocket 网关 + 协议
│   │   ├── agent-session.mjs# pi RpcClient 封装（流式事件转发）
│   │   └── config.mjs       # agents.yaml 解析
│   └── SETUP.md
└── harmony/             # 鸿蒙 App（ArkTS，Phase 2）
    └── (见下方规划)
```

## 阶段规划

- [x] **Phase 1 — hub**：WebSocket 网关 + pi RPC 桥 + 多 agent 配置（已验证端到端）
- [x] **Phase 1.5 — Web 调试台**：http://127.0.0.1:8787/ （hub 已内置）
- [x] **Phase 2 — 鸿蒙 App**：ArkTS 侧边栏 + 终端风聊天窗，编译通过（entry-default-unsigned.hap）
- [ ] **Phase 3 — Ziti 接入**：libziti 交叉编译 OpenHarmony（可行性已论证，见 docs/）
- [ ] **Phase 4 — 语音（可选）**：Core Speech Kit 识别 + 可选 TTS

## hub 快速开始

```bash
cd hub
npm install ws
npm start
# 健康检查
curl http://127.0.0.1:8787/health
```

修改 `agents.yaml`：
- 每个 agent 可配置 `model`（`provider:modelId` 格式）、`cwd`（pi 的工作目录）、
  `systemAddendum`（人设附加段）
- `server.token` 是 App 连接令牌，**生产环境必须改**

## WebSocket 协议（v1）

连接：`ws://<内网IP>:8787/ws?token=<token>`

| 客户端 → 服务端 | 说明 |
|---|---|
| `{"type":"list"}` | 列出智能体 |
| `{"type":"connect","agent":"ops"}` | 选中智能体，返回历史消息 |
| `{"type":"prompt","message":"...","id":"c1"}` | 发消息，流式返回 |
| `{"type":"steer","message":"..."}` | 运行中插话 |
| `{"type":"abort"}` | 停止当前生成 |
| `{"type":"history"} / {"type":"state"}` | 拉历史 / 状态 |

服务端 → 客户端主要帧：

- `agents` / `connected` / `accepted` / `done` / `history` / `state` / `ok` / `error`
- `pi_event` — pi 的原始流式事件（`message_update` 的 `text_delta` 用于打字机效果、
  `tool_execution_start/update` 用于终端里展示工具调用）

## 鸿蒙 App（Phase 2 规划）

- `SideBarContainer` 左侧栏（智能体列表，来自 `list`），主区终端风聊天
- WebSocket: `@ohos.net.webSocket`；证书/JWT 存储: `@ohos.security.assetStore`
- 终端风渲染：等宽字体 + Markdown/代码块高亮（自绘或三方组件）
- Ziti: NAPI 封装 libziti，App 内本地代理，UI 层无感知

## 语音（Phase 4，可选项）

鸿蒙 `Core Speech Kit` 提供端侧免费识别（中文识别率高、离线）：
录音 → 识别文本 → 走 `prompt` 帧 → 文字流式回显。朗读用 `textToSpeech` 可选。
建议先做文字版，语音作为增强，不阻塞主线。

## 安全提醒

- token 仅是最低限度防护；上生产前建议套 Ziti/mTLS
- hub 进程会以你的用户权限执行 bash（pi 工具），**不要暴露公网**
