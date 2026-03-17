# 阶段流水线使用示例

本文档提供完整的使用示例，展示如何使用新的阶段流水线完成开发任务。

## 快速开始

### 1. 创建任务并生成计划

```bash
# 进入 skills/software-dev 目录
cd skills/software-dev

# 创建任务（会自动生成 plan 文件）
node openclaw-integration.js create-task-json "实现用户登录功能" "实现用户登录功能，支持邮箱和手机号登录" xassistant
```

**输出示例**：
```
✅ 任务已创建: id=abc123 projectKey=xassistant status=pending
✅ 已联动生成 plan: /path/to/docs/plan-TASK-20260305-001.md → status=planned

HANDOFF:{"ok":true,"taskId":"TASK-20260305-001","task":{...}}
```

### 2. 查看生成的计划

```bash
# 查看任务详情
node openclaw-integration.js list-tasks-json planned

# 查看 plan 文件
cat /path/to/project/docs/plan-TASK-20260305-001.md
```

**Plan 文件结构**：
```markdown
# Task Plan

## Overview
**任务ID:** TASK-20260305-001
**任务标题:** 实现用户登录功能
**项目:** xassistant
**状态:** planning

## Execution Log

### Plan 阶段
- [x] 2026-03-05T10:00:00Z: Plan生成
- [ ] Plan确认（人工审核或自动通过）

### Code 阶段
- [ ] 开发开始（环境准备完成）
- [ ] 代码实现（核心功能完成）

### Test 阶段
- [ ] 测试完成（通过所有测试）

### Done 阶段
- [ ] 代码审查（通过审查）
- [ ] 人工确认完成（最终验收）

---

meta:
  taskId: TASK-20260305-001
  phase: plan
  ...
---
```

---

## 方式一：运行完整流水线

### 基本用法

```bash
# 运行完整流水线 (Plan → Code → Test → Done)
node openclaw-integration.js phase-pipeline TASK-20260305-001

# 使用指定 backend
node openclaw-integration.js phase-pipeline TASK-20260305-001 --backend=cursor

# 模拟运行（不执行实际操作）
node openclaw-integration.js phase-pipeline TASK-20260305-001 --dry-run

# 跳过自动提交
node openclaw-integration.js phase-pipeline TASK-20260305-001 --skip-commit
```

### 流水线执行过程

```
🚀 Starting phase pipeline for task TASK-20260305-001
   Title: 实现用户登录功能
   Current phase: plan

📋 Executing phase: plan
   Generating/confirming plan...
   ✅ Plan already exists, skipping generation

📋 Executing phase: code
   Implementing code...
   Phase: 代码实现
   后端: cursor
   项目路径: /path/to/xassistant
   计划文件: /path/to/docs/plan-TASK-20260305-001.md
   ✅ Code implementation completed

📋 Executing phase: test
   Running tests...
   Trying: npm test
   ✅ npm test passed

📋 Executing phase: done
   Finalizing...
   ✅ Task marked as completed

📝 Auto-committing changes...
   Staged all changes
   Committed: feat(task): 实现用户登录功能 [TASK-20260305-001]

{
  "taskId": "TASK-20260305-001",
  "phases": {
    "plan": { "success": true },
    "code": { "success": true },
    "test": { "success": true },
    "done": { "success": true }
  },
  "success": true,
  "commit": { "success": true, "message": "feat(task): 实现用户登录功能 [TASK-20260305-001]" }
}
```

---

## 方式二：分阶段执行

### 步骤 1：生成/确认 Plan

```bash
# 为 pending 任务生成 plan
node openclaw-integration.js generate-plan TASK-20260305-001

# 或处理所有 pending 任务
node openclaw-integration.js process-pending
```

### 步骤 2：执行 Code 阶段

```bash
# 推荐：通过 run-phase 执行当前 Code 阶段（统一入口）
node openclaw-integration.js run-phase TASK-20260305-001 code --backend=cursor

# （可选）使用 agent.start 在 tmux 中启动，便于观察执行过程
node agent-start-skill.js start xassistant TASK-20260305-001 cursor
```

### 步骤 3：运行测试

```bash
# 推进到 test 阶段
node openclaw-integration.js phase-advance TASK-20260305-001 code

# 测试会自动运行（如果有测试命令）
```

### 步骤 4：完成并提交

```bash
# 推进到 done 阶段并自动提交
node openclaw-integration.js phase-advance TASK-20260305-001 test

# 或手动标记完成
node openclaw-integration.js mark-done TASK-20260305-001
```

---

## 方式三：通过 API 调用

### 创建任务

```bash
curl -X POST http://localhost:3001/api/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "title": "实现用户登录功能",
    "description": "实现用户登录功能，支持邮箱和手机号登录",
    "projectKey": "xassistant",
    "priority": "p1"
  }'
```

### 启动 Agent

```bash
# 通过 API 启动 agent
curl -X POST "http://localhost:3001/api/tasks/TASK-20260305-001/agent-start?backend=cursor"
```

### 查看任务状态

```bash
curl http://localhost:3001/api/tasks/TASK-20260305-001
```

**响应示例**：
```json
{
  "id": "abc123",
  "taskId": "TASK-20260305-001",
  "title": "实现用户登录功能",
  "status": "inProgress",
  "phase": "code",
  "projectKey": "xassistant",
  "planPath": "/path/to/docs/plan-TASK-20260305-001.md",
  "backend": "cursor",
  "tmuxSession": "xassistant",
  "tmuxPaneId": "xassistant:0.1"
}
```

---

## 渐进式披露示例

### 获取特定阶段的 plan 内容

```bash
# 获取 Code 阶段所需的内容
node openclaw-integration.js phase-content /path/to/plan.md code
```

**输出**：
```json
{
  "taskId": "TASK-20260305-001",
  "title": "实现用户登录功能",
  "projectKey": "xassistant",
  "currentPhase": "code",
  "phaseContent": "- [ ] 开发开始（环境准备完成）\n- [ ] 代码实现（核心功能完成）",
  "checklist": [
    { "checked": false, "text": "开发开始（环境准备完成）" },
    { "checked": false, "text": "代码实现（核心功能完成）" }
  ],
  "input": {
    "plan": "Plan 阶段的内容...",
    "constraints": "仅实现计划中的代码部分，不要运行测试或提交"
  }
}
```

---

## 常见场景

### 场景 1：从失败任务恢复

```bash
# 查看失败任务
node openclaw-integration.js list-tasks-json failed

# 重新生成 plan 并执行
node openclaw-integration.js generate-plan TASK-FAILED-001
node openclaw-integration.js phase-pipeline TASK-FAILED-001
```

### 场景 2：只执行代码不提交

```bash
# 跳过自动提交
node openclaw-integration.js phase-pipeline TASK-20260305-001 --skip-commit

# 手动验证后提交
git status
git diff
git add .
git commit -m "feat(task): 实现用户登录功能 [TASK-20260305-001]"
```

### 场景 3：模拟运行验证流程

```bash
# 模拟运行查看将要执行的操作
node openclaw-integration.js phase-pipeline TASK-20260305-001 --dry-run
```

---

## 任务状态流转图

```
┌──────────┐     ┌──────────┐     ┌────────────┐     ┌───────────┐
│ pending  │────▶│ planned  │────▶│ inProgress │────▶│ completed │
└──────────┘     └──────────┘     └────────────┘     └───────────┘
                      │                  │
                      │                  │
                      ▼                  ▼
                 phase=plan        phase=code
                                   phase=test
                                   phase=done
```

---

## 相关命令速查

| 操作 | 命令 |
|------|------|
| 创建任务 | `node openclaw-integration.js create-task-json "标题" "描述" <projectKey>` |
| 生成计划 | `node openclaw-integration.js generate-plan <taskId>` |
| 运行流水线 | `node openclaw-integration.js phase-pipeline <taskId>` |
| 一键自动执行（代码+测试+提交） | `node openclaw-integration.js auto-execute <taskId>` 或 POST /api/tasks/:id/auto-execute |
| 单阶段执行（触发式） | `node openclaw-integration.js run-phase <taskId> <plan\|code\|test\|done>` 或 POST /api/tasks/:id/run-phase?phase=code |
| 触发式流程 | 生成计划后 task.phase=plan；Proxy 每 60 秒扫描，对 phase 为 plan/code/test/done 的任务自动 POST run-phase，阶段完成更新 plan 进度并推进 phase |
| 执行当前 Code 阶段 | `node openclaw-integration.js run-phase <taskId> code --backend=cursor`（或通过 execute-task 能力间接调用） |
| 启动 Agent | `node agent-start-skill.js start <projectKey> <taskId> <backend>` |
| 查看任务 | `node openclaw-integration.js list-tasks-json [status]` |
| 标记完成 | `node openclaw-integration.js mark-done <taskId>` |
| 获取阶段内容 | `node openclaw-integration.js phase-content <planPath> [phase]` |
| 推进阶段 | `node openclaw-integration.js phase-advance <taskId> [currentPhase]` |
| 流程验证（Agent 自验证） | `cd skills/software-dev && npm run verify-flow`（可选 `VERIFY_USE_LOCAL_STORE=1`） |
| Task 端到端验证 | 先启动 Proxy（`cd proxy && go run main.go --allow-local-no-auth`），再 `VERIFY_E2E=1 npm run verify-flow` |
