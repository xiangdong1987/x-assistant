## tmux 管理 Agent 会话与 App 集成方案

### 1. 目标

- 使用 `tmux` 作为本地 **Agent 宿主与控制平面**：
  - 各类开发 / 日程 / 运维 Agent 长驻在 `tmux` 会话中运行。
  - 所有 CLI 调用（Cursor、Claude、Tuxme 等）只作为后端实现细节。
- 通过 **技能 + Gateway**，让：
  - OpenClaw 可以启动 / 查询 / 停止这些 tmux Agent。
  - App 可以一键“唤起某个任务的 tmux 执行窗口”，查看实时输出。

---

### 2. tmux 命名与结构约定

#### 2.1 Session 命名（按项目）

- 每个项目一个 `tmux` session：
  - `session = <projectKey>`
  - 例如：`xassistant`。
- 优点：
  - 项目级隔离（不同项目的 Agent 不互相干扰）。
  - 容易在终端直接 `tmux a -t xassistant` 进入该项目的全部 Agent 视图。

#### 2.2 Window / Pane 命名（按能力与后端）

- Window 按“能力域”划分，例如：
  - `dev`：开发相关 Agent（自动计划、自动开发等）。
  - `schedule`：日程同步 / agenda 相关 Agent。
  - `infra`：CI / 健康检查 / 辅助脚本等。

- Pane 用“后端或 Agent 类型”命名标签（可通过环境变量或日志中标记）：
  - `cursor`：基于 Cursor 的自动开发 Agent。
  - `claude`：基于 Claude Code CLI/CCR 的 Agent。
  - `tuxme`：基于 Tuxme 的统一执行 Agent。

> 实际上，tmux 原生 Pane 没有“名字”，这里的“命名”可以通过：
> - 在 Pane 启动命令中写明：`echo "[dev:tuxme TASK-xxx]"`；或
> - 每个 Pane 启动前，在任务存储中记录 `paneId` + 元数据。

---

### 3. Agent 控制技能设计（面向 OpenClaw / App）

为 tmux 管理设计一组“意图明确”的技能（技能内部才真正操作 tmux）：

#### 3.1 `agent.start`（启动 Agent）

- **用途**：在指定项目的 tmux session 中，启动一个执行指定任务的 Agent（Cursor / Claude / Tuxme 等）。
- **推荐输入 JSON**：

```json
{
  "skill": "agent.start",
  "projectKey": "xassistant",
  "agentType": "dev.execute_plan",
  "backend": "tuxme",
  "taskId": "TASK-20260304-...",
  "options": {
    "logPath": "logs/exec-TASK-20260304-....log"
  }
}
```

- **行为约定**：
  - 若 `tmux` 中尚无该项目的 session：
    - `tmux new-session -d -s xassistant`。
  - 在 `dev` window 中新建一个 pane，执行实际命令，例如：
    - `tuxme run --task TASK-20260304-... --backend tuxme`，或
    - `node openclaw-integration.js execute-task <taskId> --backend cursor`。
  - 将以下信息写入任务存储或单独元数据表（例如 `tasks-store` 增加字段）：
    - `tmuxSession`: `"xassistant"`
    - `tmuxWindow`: `"dev"`
    - `tmuxPaneId`: `"xassistant:dev.1"`（或 pane 序号）
    - `backend`: `"tuxme"` / `"cursor"` / `"claude"`

- **HANDOFF 输出示例**：

```json
HANDOFF:{
  "ok": true,
  "skill": "agent.start",
  "version": "1.0",
  "data": {
    "projectKey": "xassistant",
    "taskId": "TASK-20260304-...",
    "backend": "tuxme",
    "tmux": {
      "session": "xassistant",
      "window": "dev",
      "paneId": "xassistant:dev.1"
    }
  },
  "error": null
}
```

#### 3.2 `agent.status`（查询 Agent 状态）

- **用途**：按 `taskId` 或项目列出当前活跃的 Agent，对 OpenClaw / App 提供“有哪些任务在跑”的视图。
- **推荐输入 JSON**：

```json
{
  "skill": "agent.status",
  "projectKey": "xassistant",
  "taskId": "TASK-20260304-..."
}
```

- **HANDOFF 输出要点**：
  - 列出匹配任务的当前状态（任务状态 + tmux session/window/pane）。
  - 若 Pane 已退出但任务未正常标记完成，也要在 `status: "stale"` 里体现出来，便于清理。

#### 3.3 `agent.stop`（停止 Agent）

- **用途**：根据 `taskId` 或 tmux pane 信息，停止某个 Agent 的执行。
- **行为**：
  - 从任务存储中读出对应 `tmuxSession` / `window` / `paneId`；
  - 使用 `tmux kill-pane -t <paneId>` 或向进程发送信号；
  - 更新任务状态为 `failed` / `aborted`，并在日志中记录原因。

---

### 4. 任务存储中的 tmux 元数据扩展

在现有 `tasks-store` 结构基础上（例如 JSON 文件或数据库），为每个任务增加 tmux 相关元数据字段：

- `backend`: `"cursor" | "claude" | "tuxme" | "other"`。
- `tmuxSession`: `string`，如 `"xassistant"`。
- `tmuxWindow`: `string`，如 `"dev"`。
- `tmuxPaneId`: `string`，如 `"xassistant:dev.1"`。
- `lastExecLogPath`: `string`，对应 `logs/exec-*.log` 路径。

这些字段由 `agent.start` / `agent.stop` / `agent.status` 等技能维护，App 和 OpenClaw 都只通过技能访问。

---

### 5. App 如何“唤起 tmux 某个任务的执行情况”

目标：在 App 的任务详情页上，有一个按钮，例如“在终端中查看执行”，点击后：

- 桌面环境下：直接唤起本机终端 + `tmux attach ...`；
- 移动端或 Web：至少返回一条可复制的命令，或提供实时日志视图。

#### 5.1 协议流程（App 侧调用链）

1. **App 请求任务对应的 tmux 信息**
   - 走 Gateway → main 会话 → 调用 `agent.status` 技能，传入 `taskId`。
2. **Agent 返回 tmux 元数据**
   - `HANDOFF.data.tmux = { session, window, paneId }`。
3. **App 根据平台选择唤起方式**：
   - macOS 桌面 App：
     - 通过本地 shell 调用：
       - `tmux attach -t xassistant`（附着到整个项目 session），或
       - 使用支持 `-t` pane 附着的终端策略（如 iTerm 配合 AppleScript）。
   - Web/移动 App：
     - 显示一条“本地命令”供用户复制：
       - `tmux attach -t xassistant`。
     - 或者：发起另一个 skill 请求，比如 `logs.tail`，只看对应 `lastExecLogPath` 的实时内容。

#### 5.2 App 端按钮行为（示例）

- **按钮文案**：`在终端查看执行（tmux）`
- **点击逻辑**：
  1. 调用 `chat.send` 至 main，会话内容类似：`/agent.status TASK-20260304-...`。
  2. 监听 chat 事件，等待包含 `HANDOFF` 的最后一条消息。
  3. 从 `HANDOFF.data.tmux` 中解析出 `session / window / paneId`。
  4. 桌面 App：
     - 若具备本地执行能力，则直接跑：
       - `tmux attach -t <session>`；
       - 或调用一个本地 helper（小 daemon）执行该命令。
  5. 若无法直接执行命令，则在 UI 中显示：
     - “在终端执行：`tmux attach -t xassistant`（该 session 内已有任务执行 Pane）”。

> 关键点：App 不直接操作 tmux，而是通过技能拿到“tmux 目标信息 + 日志路径”。真正的 attach 行为交给本机终端或用户自己选择。

---

### 6. 与现有技能体系的对齐

- **开发域技能**（已存在）：
  - `create-task-skill`：创建任务（pending）。
  - `generate-plan-skill`：生成计划文件（planned）。
  - `execute-task-skill`：执行计划（developing → reviewing → done）。

- **tmux 控制技能**（本方案新增）：
  - `agent.start`：在 tmux 中启动某个任务的 Agent，会自动更新任务中的 tmux 元数据。
  - `agent.status`：查询任务对应的 tmux Pane 和执行状态。
  - `agent.stop`：停止对应 tmux Pane 中的 Agent 执行。

- **组合方式**：
  - 高层意图技能（例如 `dev.execute_plan`）可以选择：
    - 直接同步执行（短任务）；
    - 或设置 `runMode = "tmux-agent"`，内部转为调用 `agent.start`，实现长驻执行与可视化管理。

---

### 7. 总结

- tmux 被视为“Agent 控制台”和“本地执行宿主”，而不是直接暴露给 OpenClaw / App 的底层细节。
- OpenClaw 与 App 只与 **技能（agent.start / agent.status / agent.stop 等）** 对话，通过统一的 HANDOFF 协议获取状态与 tmux 元数据。
- App 可以基于这些元数据，为每个任务提供“在终端中查看执行”的能力，从而在日常开发和多项目管理中，快速定位与观察具体 Agent 的执行情况。

