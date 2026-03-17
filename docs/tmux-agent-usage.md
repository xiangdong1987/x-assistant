# TMUX Agent 管理技能使用指南

## 概述

TMUX Agent 管理技能用于在 tmux 会话中启动、查询和停止 Agent，实现后台任务执行和终端监控。

## 技能列表

| 技能 | 用途 | 命令 |
|------|------|------|
| `agent.start` | 在 tmux 中启动 Agent | `node agent-start-skill.js start <projectKey> <taskId> <backend>` |
| `agent.status` | 查询 Agent 状态 | `node agent-status-skill.js status <taskId>` |
| `agent.stop` | 停止 Agent | `node agent-stop-skill.js stop <taskId>` |

## TMUX 结构

- **Session**: 按项目命名 (e.g., `xassistant`)
- **Window**: 按能力域划分
  - `dev`: 开发相关 Agent
  - `schedule`: 日程同步 Agent
  - `infra`: CI/健康检查 Agent
- **Pane**: 每个 Agent 运行在独立 pane 中

## agent.start - 启动 Agent

### 命令
```bash
node agent-start-skill.js start <projectKey> <taskId> <backend> [--window=<windowName>]
```

### 参数
- `projectKey`: 项目 key (e.g., xassistant)
- `taskId`: 任务 ID (e.g., TASK-20260304-123)
- `backend`: 后端类型 (tuxme, cursor, claude)
- `--window`: 窗口名称 (默认: dev)

### 示例
```bash
# 使用 tuxme 启动
node agent-start-skill.js start xassistant TASK-20260304-123 tuxme

# 使用 cursor 启动
node agent-start-skill.js start xassistant TASK-20260304-123 cursor

# 指定窗口
node agent-start-skill.js start xassistant TASK-20260304-123 tuxme --window=schedule
```

### 输出格式
```json
{
  "ok": true,
  "skill": "agent.start",
  "version": "1.0",
  "data": {
    "projectKey": "xassistant",
    "taskId": "TASK-20260304-123",
    "backend": "tuxme",
    "tmux": {
      "session": "xassistant",
      "window": "dev",
      "paneId": "xassistant:0.1"
    },
    "logPath": "logs/exec-TASK-20260304-123.log"
  },
  "error": null
}
```

---

## agent.status - 查询状态

### 命令
```bash
# 查询单个任务状态
node agent-status-skill.js status <taskId>

# 列出项目所有 Agent
node agent-status-skill.js list <projectKey>
```

### 示例
```bash
# 查看任务状态
node agent-status-skill.js status TASK-20260304-123

# 列出项目所有运行中的 Agent
node agent-status-skill.js list xassistant
```

### Pane 状态
- **running**: 进程存活，非活跃
- **active**: pane 有焦点/最近活动
- **stopped**: 进程已退出
- **unknown**: 无法确定状态
- **stale**: 任务显示 "developing" 但 pane 已停止

### 输出格式
```json
{
  "ok": true,
  "skill": "agent.status",
  "version": "1.0",
  "data": {
    "taskId": "TASK-20260304-123",
    "title": "实现功能 X",
    "status": "developing",
    "paneStatus": "running",
    "tmux": {
      "session": "xassistant",
      "window": "dev",
      "paneId": "xassistant:0.1",
      "backend": "tuxme",
      "logPath": "logs/exec-TASK-20260304-123.log"
    }
  },
  "error": null
}
```

---

## agent.stop - 停止 Agent

### 命令
```bash
node agent-stop-skill.js stop <taskId> [--force] [--no-status-update]
```

### 参数
- `taskId`: 任务 ID
- `--force`: 强制立即终止 (跳过优雅关闭)
- `--no-status-update`: 不更新任务状态

### 示例
```bash
# 优雅停止 (发送 Ctrl+C)
node agent-stop-skill.js stop TASK-20260304-123

# 强制终止
node agent-stop-skill.js stop TASK-20260304-123 --force

# 停止但不更新状态
node agent-stop-skill.js stop TASK-20260304-123 --no-status-update
```

### 行为说明

#### 优雅停止 (默认)
1. 发送 Ctrl+C 到 pane (SIGINT)
2. 等待最多 5 秒让进程优雅退出
3. 如果 pane 仍然存在，使用 `--force` 强制终止

#### 状态更新
- 默认情况下，任务状态变为 `failed`
- 使用 `--no-status-update` 跳过状态更新
- 停止后清除 tmux 元数据

### 自动回收

**重要**: 当任务进入终态（`completed` / `failed` / `cancelled`）时，Proxy 会自动调用 `agent.stop` 回收 tmux pane，无需手动操作。

这一机制确保：
- 任务完成后 tmux pane 不会残留
- 系统资源自动释放
- 用户无需关心清理工作

自动回收由 Proxy 的 `TaskBridge` 在收到 OpenClaw 推送的任务状态变更时触发，使用 `--no-status-update` 参数仅回收 pane 而不覆盖已有的终态状态。

### 输出格式
```json
{
  "ok": true,
  "skill": "agent.stop",
  "version": "1.0",
  "data": {
    "taskId": "TASK-20260304-123",
    "title": "实现功能 X",
    "paneId": "xassistant:0.1",
    "killed": true,
    "newStatus": "failed",
    "message": "Agent stopped successfully"
  },
  "error": null
}
```

---

## 任务存储字段

任务现在包含以下 tmux 相关字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `backend` | string | Agent 后端 (tuxme/cursor/claude) |
| `tmuxSession` | string | tmux 会话名称 |
| `tmuxWindow` | string | tmux 窗口名称 |
| `tmuxPaneId` | string | tmux pane ID |
| `lastExecLogPath` | string | 执行日志路径 |

这些字段由技能自动维护，App 和 OpenClaw 通过技能访问。

---

## 关联技能

TMUX Agent 管理技能与现有技能体系配合使用：

1. **create-task** → 创建任务 (pending)
2. **generate-plan** → 生成计划 (planned)
3. **agent.start** → 在 tmux 启动 Agent (developing)
4. **agent.status** → 查询状态
5. **agent.stop** → 停止 Agent (failed)
6. **execute-task** → 传统同步执行模式

### 测试阶段（Test phase）与 tmux 自动退出

- 在基于 phase orchestrator 的 Plan → Code → **Test** → Done 流水线中：
  - Code / Done 阶段默认保留 tmux pane，便于人工检查和继续交互。
  - **Test 阶段**中，为了让测试命令结束后流水线自动前进到下一阶段，`phase-orchestrator` 在调用 `agent-start-skill` 时会为该阶段设置环境变量：
    - `AGENT_START_AUTO_CLOSE=1`
- 这会触发 `agent-start-skill.js` 中的逻辑，让测试阶段实际执行的命令在完成后自动执行 `exit`，从而关闭对应的 tmux pane。
- Phase Orchestrator 在检测到该 pane 已关闭后，会：
  - 将 Test 阶段在 plan 文件中标记为完成；
  - 推进任务 phase 到 `done`，无需人工在 tmux 中手动退出。

---

## 附加功能

### 终端中查看执行

获取 tmux 元数据后，可在终端中 attach：

```bash
# 附着到项目 session
tmux attach -t xassistant

# 附着到特定 pane
tmux attach -t xassistant:1.1

# 实时查看日志
tail -f logs/exec-TASK-20260304-123.log
```

### App 集成

App 可以通过以下流程"唤起 tmux 某个任务的执行情况"：

1. 调用 `agent.status` 技能获取 `tmux` 元数据
2. 桌面 App: 直接执行 `tmux attach -t <session>`
3. Web/移动 App: 显示可复制的命令供用户执行