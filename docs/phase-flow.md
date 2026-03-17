# 任务阶段流转状态文档

## 概述

本文档描述任务从创建到完成的完整状态/阶段流转逻辑，涵盖 `task.status`、`task.phase`、plan 文件 Execution Log 的协同关系，以及各组件的职责边界。

---

## 状态与阶段对照表

| task.status     | task.phase | 语义                             | 触发来源                        |
|-----------------|------------|----------------------------------|---------------------------------|
| `pending`       | —          | 任务已创建，等待处理             | 创建 API                        |
| `confirmed`     | —          | 任务已确认，等待分配             | 人工确认                        |
| `inProgress`    | —          | 任务进行中（无 plan 时也可能）   | OpenClaw 下发 / 手动触发        |
| `planning`      | `plan`     | 正在生成计划                     | phaseWatcher → agent-start plan |
| `planned`       | `code`     | 计划已生成，等待代码执行         | generate-plan 完成后回写        |
| `coding`        | `code`     | 正在编写代码                     | phaseWatcher → run-phase code   |
| `testing`       | `test`     | 正在测试                         | phaseWatcher → run-phase test   |
| `submitting`    | `done`     | 正在提交/审查                    | phaseWatcher → run-phase done   |
| `done`          | `done`     | 任务完成，已提交                 | autoCommit 完成后               |
| `failed`        | —          | 执行失败                         | 错误处理                        |

---

## 阶段流转图

```
             创建任务
                │
                ▼
          task.status=pending / confirmed / inProgress
          task.phase=""
          task.planPath=""
                │
                │  phaseWatcher 检测到无 plan 文件
                ▼
    ┌─────────────────────────────────┐
    │  agent-start-skill plan 阶段    │  (tmux pane)
    │  openclaw-integration           │
    │    generate-plan <taskId> --agent│
    └─────────────────┬───────────────┘
                      │ plan 生成完成
                      │ task.status → planned
                      │ task.phase  → code
                      │ plan file 写入 docs/plan-TASK-*.md
                      │ Execution Log Plan 阶段: [x]
                      ▼
          task.status=planned
          task.phase=code
          plan.Code 阶段: [ ] (待执行)
                │
                │  phaseWatcher 检测到 phase=code 且 prev(plan) 已完成
                ▼
    ┌─────────────────────────────────┐
    │  run-phase code                 │  (Node.js 进程)
    │  PhaseOrchestrator.runPhaseOnly │
    │    → executeAgentPhase          │
    │    → PhaseExecutor / TmuxPhaseExecutor│
    │    → backend CLI (ccr/cursor/claude)  │
    └─────────────────┬───────────────┘
                      │ 执行完毕
                      │ plan.Code 阶段所有 checkbox → [x]
                      │ advancePhase: task.phase → test
                      │ task.status → testing
                      ▼
          task.status=testing
          task.phase=test
          plan.Test 阶段: [ ] (待执行)
                │
                │  phaseWatcher 检测到 phase=test 且 prev(code) 已完成
                ▼
    ┌─────────────────────────────────┐
    │  run-phase test                 │
    │  PhaseOrchestrator.runPhaseOnly │
    │    → backend CLI                │
    └─────────────────┬───────────────┘
                      │ 执行完毕
                      │ plan.Test 阶段所有 checkbox → [x]
                      │ advancePhase: task.phase → done
                      │ task.status → submitting
                      ▼
          task.status=submitting
          task.phase=done
          plan.Done 阶段: [ ] (待执行)
                │
                │  phaseWatcher 检测到 phase=done 且 prev(test) 已完成
                ▼
    ┌─────────────────────────────────┐
    │  run-phase done                 │
    │  PhaseOrchestrator.runPhaseOnly │
    │    → backend CLI                │
    │    → autoCommit (git commit)    │
    └─────────────────┬───────────────┘
                      │ 执行完毕
                      │ plan.Done 阶段所有 checkbox → [x]
                      │ task.status → done
                      ▼
               task.status=done ✅
```

---

## Plan 文件 Execution Log 与阶段推进关系

```markdown
## Execution Log

### Plan 阶段
- [x] 2026-03-10: Plan生成          ← generate-plan 完成后自动打 [x]

### Code 阶段
- [ ] 开发开始（环境准备完成）      ← agent 执行时逐步打 [x]
- [ ] 代码实现（核心功能完成）

### Test 阶段
- [ ] 测试完成（通过所有测试）

### Done 阶段
- [ ] 代码审查（通过审查）
- [ ] 人工确认完成（最终验收）
```

**规则**：
- `IsPhaseCompleted(planPath, phase)` — 某阶段下**无 `- [ ]` 且存在至少一项**，返回 `true`
- `ParsePlanProgress(planPath)` — 统计全部 Execution Log 下已勾 / 总项数，用于判断"全局完成"

⚠️ **常见问题**：AI agent 执行后把所有 `[ ]` 都改为 `[x]`（包括尚未执行的阶段），导致 phaseWatcher 跳过后续阶段，不触发真正的执行。

---

## 组件职责边界

| 组件 | 文件 | 职责 |
|------|------|------|
| `phaseWatcher` | `proxy/server/server.go` | 定时扫描任务，根据 plan 文件/状态决定触发哪个阶段；**不直接执行业务逻辑** |
| `agent-start-skill` | `skills/software-dev/agent-start-skill.js` | 创建 tmux session/window，在 pane 中启动 plan 生成；手动"启动 Agent"按钮的后端 |
| `openclaw-integration` | `skills/software-dev/openclaw-integration.js` | CLI 入口：`run-phase <taskId> <phase>`、`generate-plan <taskId>` |
| `PhaseOrchestrator` | `skills/software-dev/phase-orchestrator.js` | 解析 plan 文件内容、调用 executor 执行、调用 `advancePhase` 推进状态 |
| `PhaseExecutor` | `skills/software-dev/unified-executor.js` | 直接调用 backend CLI（ccr/cursor/claude）同步执行 |
| `TmuxPhaseExecutor` | `skills/software-dev/unified-executor.js` | 在 tmux pane 中异步运行 `run-phase`（内层带 `AGENT_TMUX_WRAPPED=1`），立即返回 `async:true` |
| `advancePhase` | `phase-orchestrator.js` | 更新 plan meta `phase` 字段 + task DB phase，触发状态机推进 |

---

## TmuxPhaseExecutor 防递归机制

当 `config.settings.useTmuxForBackend = true` 时：

```
外层 run-phase (AGENT_TMUX_WRAPPED 未设置)
    → createPhaseExecutor() → TmuxPhaseExecutor
        → tmux pane: AGENT_TMUX_WRAPPED=1 node openclaw-integration.js run-phase
            → createPhaseExecutor() → PhaseExecutor (直接 CLI)  ← 阻断递归
                → 真正执行 backend CLI
                → advancePhase()
```

---

## phaseWatcher 核心判断逻辑

```
for task in tasks:
  if status 不在可自动化列表 → skip
  if plan 全部勾选完成 → skip（终态）
  
  targetPhase = task.phase
  if task.phase == "":
    → 从 plan meta.phase 读取（如果 != "" && != "plan"）
    → 否则默认 "code"
  if targetPhase == "plan" && planPath exists → advance to "code"
  
  if already running (runningPipelines) → skip
  
  if no planPath:
    → agent-start plan (tmux)
  else:
    sync task.phase = targetPhase to DB  ← 防止 runPhaseOnly 因 phase="" 跳过
    run-phase <targetPhase>
```

> **核心原则**：phaseWatcher **只触发当前 task.phase 对应的 run-phase**，不基于 plan 文件 checkbox 自动推进 phase。
> Phase 推进的唯一路径是 `runPhaseOnly → advancePhase → task.phase = nextPhase`。
> 这防止了 AI agent 预先勾选后续阶段 checkbox 导致阶段"凭空完成"跳过实际执行的问题。

---

## 常见问题排查

| 现象 | 原因 | 解决 |
|------|------|------|
| `skip execution because task.phase(X) != requestedPhase(Y)` | DB 中 `task.phase` 与触发的 phase 不一致；通常是 phaseWatcher 自动推进了 phase 但未实际执行 | server.go 已移除 checkbox-based 自动推进；phase 仅由 `advancePhase` 推进 |
| `task.phase=test` 但 code 未执行（phase 超前） | 旧版 phaseWatcher 看到 `IsPhaseCompleted("code")=true` 自动推进，AI 预填了 checkbox | 手动将 `task.phase` 重置为 `code`，并将 Code 阶段 checkbox 改回 `[ ]` |
| 所有阶段直接跳过，无实际执行 | plan 文件中各阶段 checkbox 均为 `[x]`（AI agent 过早勾选） | 将未执行阶段的 `[x]` 改回 `[ ]`，重置 `task.phase` 到正确的阶段 |
| `Task has no plan file` | `run-phase plan` 时 planPath 为空 | `agent-start-skill` 已适配：plan 阶段改为调用 `generate-plan`，而非 `run-phase plan` |
| run-phase 返回 async:true 但 phase 不推进 | `TmuxPhaseExecutor` 启动 tmux pane，内层进程负责 `advancePhase` | 检查 tmux pane 日志；确认 `AGENT_TMUX_WRAPPED=1` 已设置 |
