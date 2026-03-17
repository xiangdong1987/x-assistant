---
summary: "App 作为统一入口，仅通过 main 会话与 Gateway 通信（下发任务、执行任务、同步日程）"
read_when:
  - 第三方 App 对接 OpenClaw，只使用 main 会话
  - 以 App 为唯一入口，不依赖 Telegram/Discord 等通道
title: "App 对接 main 会话（统一入口）"
---

# App 对接 main 会话（统一入口）

本文描述如何让你的 **App 作为统一入口**，仅通过 **main 会话**与 OpenClaw Gateway 通信，实现下发任务、执行任务、同步日程等。OpenClaw 侧无需改动，仅需在 App 端实现 Gateway WebSocket 客户端。

## 目标

- 只使用 **main 会话**（默认会话，`sessionKey: "main"`）。
- **App 为唯一入口**：用户通过 App 与 OpenClaw 交互。
- 通过 Gateway 与 main 通信：**下发任务、执行任务、同步日程**。

## 架构概览

- **入口**：仅你的 App（WebSocket 连 Gateway，只操作 main）。
- **下发任务 / 执行任务**：App 调用 `chat.send`，把任务描述或指令发给 main 会话；Agent 与 tools/skills 执行后，通过 **chat 事件** 把结果流式推回 App。
- **同步日程**：日程可经自然语言与日程类 skill/tool 在 main 会话里维护；App 用 `chat.history` 拉取 main 的近期记录做展示或同步。

## 一、连接 Gateway

与 [Gateway 协议](/gateway/protocol) 一致，首帧为 **connect**。使用 **operator** 角色以便调用 `chat.*`、`sessions.*` 等。

```json
{
  "type": "req",
  "id": "c1",
  "method": "connect",
  "params": {
    "minProtocol": 3,
    "maxProtocol": 3,
    "client": { "id": "your-app", "version": "1.0", "platform": "ios", "mode": "operator" },
    "role": "operator",
    "scopes": ["operator.read", "operator.write"],
    "auth": { "token": "<device-token 或配置中的 token>" }
  }
}
```

鉴权使用设备配对得到的 `deviceToken` 或配置中 operator 用 token。连接成功后所有请求统一使用 `sessionKey: "main"`。

## 二、仅用 main 会话通信

### 下发任务 / 执行任务：`chat.send`

- **方法名**：`chat.send`
- **必填参数**：`sessionKey: "main"`、`message`（任务或指令）、`idempotencyKey`（建议 UUID）
- **可选**：`thinking`（如 `"auto"`）、`timeoutMs`、`attachments`

请求示例：

```json
{
  "type": "req",
  "id": "r1",
  "method": "chat.send",
  "params": {
    "sessionKey": "main",
    "message": "明天上午 10 点提醒我开会，并加入日程",
    "idempotencyKey": "550e8400-e29b-41d4-a716-446655440000",
    "thinking": "auto",
    "timeoutMs": 30000
  }
}
```

服务端会立即返回 `{ ok: true, payload: { runId, status: "started" } }`。**实际执行结果**通过 **chat 事件** 流式推送，不是本条响应的 body。

### 接收执行结果与回复：订阅 `chat` 事件

连接后需**订阅 `chat` 事件**才能收到 main 会话的流式输出。事件 payload 包含 `runId`、`sessionKey`、`state`（如 `delta` / `final`）、`message` 等；用 `runId` 与 `chat.send` 对应，用 `state === "final"` 判断一轮结束。协议细节见 [TypeBox 与 Gateway 事件](/concepts/typebox)。

### 同步日程 / 历史：`chat.history`

- **方法名**：`chat.history`
- **参数**：`sessionKey: "main"`，可选 `limit`

```json
{
  "type": "req",
  "id": "r2",
  "method": "chat.history",
  "params": { "sessionKey": "main", "limit": 50 }
}
```

用于拉取 main 会话近期对话与结果，便于 App 展示历史或日程同步。

### 中止执行：`chat.abort`

取消某次任务时，传入 `sessionKey: "main"` 与对应 `runId`（从 chat 事件或 `chat.send` 返回获取）：

```json
{
  "type": "req",
  "id": "r3",
  "method": "chat.abort",
  "params": { "sessionKey": "main", "runId": "<对应 runId>" }
}
```

## 三、能力映射

| 需求     | Gateway 用法 |
|----------|--------------|
| 下发任务 | `chat.send`(sessionKey: "main", message: 任务描述) |
| 执行任务 | 同上；执行结果通过 **chat 事件** 流式返回 |
| 同步日程 | main 内用日程类 skill/tool 维护；App 用 `chat.history`(main) 拉取并解析/展示 |
| 统一入口 | 仅 App 连 Gateway，只操作 sessionKey: "main" |

任务/日程的具体执行由 OpenClaw 侧 main 会话的 Agent 与已配置的 skills/tools 完成；App 只负责把用户意图发到 main 并展示 chat 事件与 history。

## 四、App 端实现清单

| 项目           | 说明 |
|----------------|------|
| WebSocket 连接 | 连 OpenClaw Gateway，首帧 `connect`，role: operator，带 auth.token |
| 只认 main      | 所有 `chat.send` / `chat.history` / `chat.abort` 均使用 `sessionKey: "main"` |
| chat.send      | 下发任务/指令，带 `idempotencyKey`；处理返回的 `runId` |
| 订阅 chat 事件 | 根据 `runId` 与 `state` 处理流式结果与最终结果，更新 UI / 同步日程 |
| chat.history   | 按需拉取 main 历史，用于展示或日程同步 |
| chat.abort     | 需要时根据 `runId` 取消执行 |

无需新建插件或修改 OpenClaw 核心；现有 Gateway 与 main 会话即可支持「App 为统一入口、仅 main 通道」的用法。

## 相关文档

- [Gateway 协议](/gateway/protocol)：握手、帧格式、鉴权
- [TypeBox 与协议 schema](/concepts/typebox)：方法列表与 Chat 事件
- [Control UI 与 WebChat](/web/control-ui)：`chat.send` 非阻塞与 chat 事件行为
