---
name: software-dev-agent
description: Reorganized software development agent with 3 core skills: create-task, generate-plan, execute-task. Provides complete workflow from task creation through execution with configurable backend (Claude/Cursor). Use when users need to create software development tasks, generate implementation plans, execute development workflows, or manage software project tasks. Automatically triggers for task creation, planning, and execution requests.
metadata: {"openclaw":{"requires":{"anyBins":["node"]},"emoji":"🚀"}}
---

# Software Development Agent Skill

**Complete Development Workflow**: Task creation → Plan generation → Execution → Review → Completion. Three decoupled skills with unified execution backend supporting both Claude Code and Cursor CLI.

## Three Core Skills

| Skill Name | Purpose | State | Command (normalized) |
|------------|---------|--------|----------------------|
| **Create Task** | Create development tasks (decoupled from planning) | pending | `create-task-json "Title" "Description" <projectKey>` |
| **Generate Plan** | Generate plan files for pending tasks | pending → planned | `generate-plan [taskId]` |
| **Execute Task** | Execute current phase for planned tasks with configurable backend | phase in {plan,code,test,done} | `run-phase <taskId> <plan\|code\|test\|done> [--backend claude\|cursor]` |

## Complete Workflow

**触发式自动执行（推荐）**：创建任务并生成计划后，由 **Proxy 定时器**（约每 60 秒）分析任务：若任务有 plan 且当前 `phase` 为 plan/code/test/done 之一，则自动触发该阶段的执行。每阶段完成后会更新 plan 的 Execution Log 进度并推进 `task.phase`，下一轮定时器再触发下一阶段，无需一条命令跑到底。

- 流程：创建任务 → 触发「生成计划」→ 计划生成后 `phase=plan` → 定时器触发 `run-phase plan`（空转并推进到 code）→ 定时器触发 `run-phase code` → … → `run-phase done`（提交）。
- 每阶段完成都会在 plan 文件对应阶段下追加 `- [x] 时间: 说明`，便于查看进度。
- 手动触发单阶段：`node openclaw-integration.js run-phase <taskId> <plan|code|test|done>` 或 `POST /api/tasks/:id/run-phase?phase=code`。

**一键跑到底（可选）**：若希望不依赖定时器、一次请求跑完所有阶段，可使用 `auto-execute`（返回 202，后台执行不中断）：

```bash
# 创建任务
node openclaw-integration.js create-task-json "标题" "描述" <projectKey>

# 生成计划（触发式下，此后由定时器自动执行各阶段）
node openclaw-integration.js generate-plan <taskId>

# 或一键执行到底
node openclaw-integration.js auto-execute <taskId>
# 或经 Proxy: POST /api/tasks/:id/auto-execute
```

**分步执行**（可选）：

```bash
# Step 1: Create task (status=pending, no auto-plan generation)
node openclaw-integration.js create-task-json "Title" "Description" <projectKey>

# Step 2: Generate plan (status=planned)
node openclaw-integration.js generate-plan

# Step 3: Execute Code phase (status: phase=code → phase=test)
node openclaw-integration.js run-phase <taskId> code --backend cursor

# Step 4: Mark as done (status=done)
node openclaw-integration.js mark-done <taskId>
```

## State Machine

```
pending → planned → developing → reviewing → done
     ↓         ↓           ↓          ↓
   failed   failed      failed     failed
```

## Independent Skills (Capabilities/)

Load subdirectories under `capabilities/` as independent skills. Skill IDs,入口文件与职责一一对应如下：

| Skill ID                       | Entry File / Command                                              | Purpose                                               |
|--------------------------------|-------------------------------------------------------------------|-------------------------------------------------------|
| `software-dev-create-task`     | `capabilities/create-task/run.js` → `create-task-json`           | Create pending tasks                                  |
| `software-dev-generate-plan`   | `capabilities/generate-plan/run.js` → `generate-plan`            | Generate docs/plan-\{taskId}.md                       |
| `software-dev-execute-task`    | `capabilities/execute-task/run.js` → `run-phase <taskId> code`   | Execute Code phase for planned tasks via backend      |
| `software-dev-agent-start`     | `agent-start-skill.js`                                           | Start agent in tmux               |
| `software-dev-agent-status`    | `agent-status-skill.js`                                          | Query agent status in tmux        |
| `software-dev-agent-stop`      | `agent-stop-skill.js`                                            | Stop agent in tmux                |
| `software-dev-tmux-focus`      | `tmux-focus-skill.js`                                            | Focus iTerm/tmux for given task   |

Point OpenClaw's `extraDirs` to `capabilities`, or symlink these directories (and the four agent/tmux skills above) to `~/.openclaw/skills/` as needed.

## Configuring OpenClaw to Use This Skill

1. **Agent Configuration**: Add skills to skills list:
   ```json
   {
     "skills": [
       "software-dev-create-task",
       "software-dev-generate-plan",
       "software-dev-execute-task"
     ]
   }
   ```
   Or using extraDirs for capabilities directory.

2. **System Prompt Recommendation**:
  ```text
  Software development must be done through 3 decoupled skills in order:
  1. create-task: Creates task with status=pending (does NOT auto-generate plan)
  2. generate-plan: Generates plan files for pending tasks (pending → planned)
  3. execute-task: Advances the task by executing the current phase via run-phase (plan → code → test → done)

  When users ask to create tasks, use create-task skill.
  When users ask to generate plans or process pending, use generate-plan skill.
  When users ask to execute or develop, use execute-task skill to trigger the appropriate run-phase call.

  Backend selection: Use backend parameter to choose between claude (default) or cursor.

  After execute-task completes a phase, the task.phase will be advanced (plan → code → test → done), and the plan's Execution Log will be updated for that phase. Users should still manually verify results and mark tasks as done when appropriate.
  ```

## 数据目录

- `data/tasks.json`: 本地任务存储（已 .gitignore，不提交）
- `data/task-definitions/`: 单次/批量创建任务用的 JSON 定义文件放此目录（如 `create-task-skill.js batch data/task-definitions/xxx.json`），该目录已 .gitignore，不提交。避免在技能根目录堆积 `*-task.json` 等文件

## Dependencies

- Node.js
- Claude Code CLI (optional, default backend)
- Cursor CLI (optional, alternate backend)
- Run `npm install` in repository root directory
- Configure `projects` in `config.json` or via remote API

## Flow verification (Agent 自验证)

开发者或 Agent 可通过流程验证脚本确认「创建任务 → 生成计划 → 阶段流水线」是否通畅，无需人工端到端测试：

```bash
cd skills/software-dev && npm run verify-flow
# 或
cd skills/software-dev && node scripts/verify-flow.js
```

**无 Proxy 时使用本地任务存储：**
```bash
VERIFY_USE_LOCAL_STORE=1 npm run verify-flow
```

**Task 端到端（经 Proxy API）：** 需先启动 Proxy（建议 `--allow-local-no-auth`），再执行：
```bash
VERIFY_E2E=1 npm run verify-flow
```
会依次：检查 Proxy 可达 → POST /api/tasks 创建任务 → GET /api/tasks 校验 → skill generate-plan → skill phase-pipeline --dry-run，覆盖「API → 存储 → Skill」整条链。

可选环境变量：`VERIFY_SKIP_DB=1` 跳过 db-query 冒烟；`VERIFY_SKIP_PROXY=1` 跳过 proxy verify_build。完整流程需 projectKey（默认 `xassistant`）已在 config 的 `projects.registry` 或由 Proxy 提供。在 Cursor 中可给 Agent 权限执行 `Bash(cd skills/software-dev && node scripts/verify-flow.js)` 以自验证。

## Migration Notes

**Old commands deprecated** (still work with warnings):
- `process-pending` → Use `generate-plan`
- `execute-plan-cursor` → Use `execute-task --backend cursor`
- `run-workflow auto-dev` → Chain new skills manually

**Backward compatibility maintained**:
- Old skill names still recognized
- Existing plan files continue to work
- Task schema migration utilities provided
