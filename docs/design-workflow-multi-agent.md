# 可配置流程 + 多 Agent 团队：详细设计

## 0. 核心关切：OpenClaw 能否智能、持续调用多 Agent？

**问题**：OpenClaw 能不能智能地调用多个 agent？如何让 OpenClaw 长时间、反复调用直到实现目标？

**结论**：可以，但需满足一定条件。OpenClaw 通过 **技能 + exec 工具** 实现多步调用。

### 0.1 OpenClaw 的调用机制（基于官方文档）

| 机制 | 说明 |
|------|------|
| **技能即 prompt 注入** | 每个 skill 的 SKILL.md 被注入系统 prompt，Agent 据此知道何时、如何调用 |
| **Agent 用 exec 工具** | Agent 通过 `exec` / `bash` 执行命令（如 `node openclaw-integration.js create-task-json ...`）|
| **多轮 tool call** | 一次对话中 Agent 可多次调用 exec，每次拿到 stdout 后决定下一步 |
| **command-dispatch: tool** | 可选：slash 命令绕过模型，直接调工具，无「智能」 |

### 0.2 两种实现路径

| 路径 | 谁来编排 | 智能程度 | 可靠性 |
|------|----------|----------|--------|
| **A. Agent 驱动** | OpenClaw Agent 根据 SKILL.md 反复调用 exec | 高（可应变、可重试）| 中（依赖模型理解与执行）|
| **B. 脚本驱动** | 一个技能命令内部跑完整脚本（create→plan→execute）| 低（固定流程）| 高（ deterministic）|

### 0.3 让 OpenClaw「智能长时间调用」的关键

1. **编排技能 SKILL.md 写清流程**：明确写「步骤 1 → 2 → 3，每步用 exec 运行 xxx，从输出解析 taskId，再执行下一步」  
2. **子技能输出结构化**：每步最后一行输出 `HANDOFF:{"taskId":"TASK-xxx","status":"planned"}` 便于 Agent 解析  
3. **确保 exec 工具可用**：`tools.profile: "coding"` 或 `tools.allow` 包含 `exec` / `group:runtime`  
4. **配置 loop-detection**：若开启，需调大阈值或对编排技能豁免，避免误判为坏循环  
5. **会话/超时**：确保单次对话可发起足够多 tool call（通常支持 10+ 次）

### 0.4 编排技能 SKILL.md 示例（Agent 驱动多步调用）

```markdown
---
name: auto-dev-orchestrator
description: 自动开发流程编排，按顺序调用创建任务、生成计划、执行开发，直到完成或失败
metadata: {"openclaw":{"requires":{"anyBins":["node"]},"emoji":"🔄"}}
---

# 自动开发编排

当用户请求「自动开发」并给出标题、描述、项目时，**你必须按顺序执行以下步骤，不得跳过**：

## 步骤 1：创建任务
使用 exec 工具运行（替换 {title} {description} {projectKey}）：
```
node openclaw-integration.js create-task-json "{title}" "{description}" {projectKey}
```
从 stdout 最后一行查找 `HANDOFF:` 或 `taskId:`，提取 taskId（格式 TASK-YYYYMMDD-xxx）。

## 步骤 2：生成计划
使用 exec 工具运行：
```
node openclaw-integration.js process-pending
```
等待完成。若无错误，继续步骤 3。

## 步骤 3：执行开发
使用 exec 工具运行（用上一步的 taskId）：
```
node openclaw-integration.js execute-plan-cursor --run {taskId}
```
此步骤耗时较长，需等待完成。

## 终止条件
- 任一步骤返回非零退出码或包含 "Error"/"失败" → 向用户报告错误并停止
- 步骤 3 完成后 → 向用户报告「自动开发完成」

**重要**：每步必须等待 exec 返回后再执行下一步。不可并行，不可猜测结果。
```

### 0.5 子技能输出约定（便于 Agent 解析）

在 `create-task-json`、`process-pending` 等脚本末尾追加一行：

```
HANDOFF:{"taskId":"TASK-20260228-001","status":"task_created"}
```

或

```
TASK_ID=TASK-20260228-001
```

Agent 可从 stdout 最后几行解析，减少依赖自然语言理解。

### 0.6 若 Agent 驱动不稳定：兜底方案

若 Agent 时常漏步骤、解析错误或提前停止，可改用 **command-dispatch: tool**：

```markdown
---
name: auto-dev
command-dispatch: tool
command-tool: auto_dev_workflow
---
```

并注册 `auto_dev_workflow` 工具，内部直接执行 `node openclaw-integration.js run-workflow auto-dev ...`。用户触发一次，脚本跑完全流程，无 Agent 多步决策，稳定性高。

---

## 1. 概述

**目标**：可配置的流程编排 + 按 plan 状态分工的多 Agent，减少上下文、节省 token。

**核心**：
- 流程 = 有序的步骤，每步对应一个 **Agent**（或纯逻辑）
- 每个 Agent 只接收**当前阶段所需的最小输入**，不携带历史对话
- 步骤间通过 **Handoff 结构** 传递状态

---

## 2. 状态模型

### 2.1 Plan 状态枚举

```
no_task       → 无任务，需创建
task_created  → 任务已创建，待生成 plan
planned       → plan 已生成，待执行
executing     → 执行中
done          → 完成
failed        → 某步失败
```

### 2.2 状态 → Agent 映射

| 状态 | 负责 Agent | 输入 | 输出 |
|------|-----------|------|------|
| no_task | Creator | 用户原始请求 | Handoff |
| task_created | Planner | Handoff | Handoff |
| planned | Executor | Handoff | Handoff |
| executing | Executor | Handoff | Handoff（或 done/failed）|
| failed | Fixer（可选） | Handoff | Handoff 或 重试 |

### 2.3 状态转换

```
no_task --[Creator]--> task_created
task_created --[Planner]--> planned
planned --[Executor 开始]--> executing
executing --[Executor 完成]--> done
任意 --[出错]--> failed
failed --[Fixer/人工]--> task_created | planned | 终止
```

---

## 3. Handoff 结构（步骤间传递的数据）

### 3.1 完整 Schema

```json
{
  "runId": "run-20260228-abc123",
  "workflow": "auto-dev",
  "currentStep": 2,
  "status": "planned",
  "taskId": "TASK-20260228-001",
  "projectKey": "xassistant",
  "projectPath": "/path/to/xassistant",
  "title": "写一个功能文档",
  "description": "总结当前系统功能",
  "planPath": "/path/to/docs/plan-TASK-20260228-001.md",
  "planSummary": "3 steps: 1. 分析结构 2. 编写文档 3. 评审",
  "currentPlanStep": 1,
  "lastError": null,
  "createdAt": "2026-02-28T10:00:00Z"
}
```

### 3.2 各 Agent 实际使用的字段

| Agent | 必需字段 | 可选 | 说明 |
|-------|----------|------|------|
| Creator | runId, workflow, title, description, projectKey | projectPath | 从 projectKey 解析 path |
| Planner | runId, taskId, projectPath, title, description | planPath | 生成 plan 后写入 planPath |
| Executor | runId, taskId, planPath, projectPath, currentPlanStep | planSummary | 只读 plan 中 currentPlanStep 那一段 |

### 3.3 Handoff 文件存储

每次 handoff 写入文件，便于调试和断点续跑：

```
{workDir}/.workflow-runs/{runId}/
  handoff.json      # 当前 handoff（每次步骤完成覆盖）
  step-1-out.json   # Creator 输出
  step-2-out.json   # Planner 输出
  ...
  run.log           # 执行日志
```

---

## 4. Agent 定义（每个 Agent 的职责与调用方式）

### 4.1 Creator Agent

**职责**：根据用户请求创建任务，写入 tasks-store，返回 taskId。

**是否用 LLM**：可选。当前实现可直接调 API 创建任务（无 LLM）；若需「从自然语言提炼结构化任务」可加一层 LLM。

**输入**（由 Orchestrator 构造）：
```
workflow: auto-dev
userRequest: "写一个功能文档，总结当前系统功能"
projectKey: xassistant
```

**输出**（写入 handoff）：
```json
{
  "taskId": "TASK-20260228-001",
  "status": "task_created",
  "planPath": null,
  ...
}
```

**调用方式**：
- 无 LLM：`node openclaw-integration.js create-task-json "标题" "描述" xassistant`，或直接调 `POST /api/tasks`
- 有 LLM：OpenClaw skill `creator`，prompt = `根据用户请求创建任务，返回 JSON: { taskId, title, description, projectKey }`

---

### 4.2 Planner Agent

**职责**：根据 taskId、title、description、projectPath 生成 plan 文件。

**是否用 LLM**：是（Cursor/Claude 分析项目并生成 plan）。

**输入**（Orchestrator 从 handoff 取出，构造最小 prompt）：
```
你只负责生成开发计划，不执行开发。

## 任务
- taskId: TASK-20260228-001
- title: 写一个功能文档
- description: 总结当前系统功能
- projectPath: /path/to/xassistant

## 要求
1. 分析项目结构
2. 生成 docs/plan-TASK-20260228-001.md
3. 严格按 plan 模板格式输出

请生成计划并保存到指定路径。不要执行任何开发步骤。
```

**系统 prompt 长度**：~500 token（无历史对话）。

**输出**：plan 文件路径写入 handoff.planPath，status=planned。

**调用方式**：
- `node cursor-executor.js plan TASK-20260228-001`（需新增 plan 子命令，只做 generatePlan）
- 或 OpenClaw skill `planner`，Agent 调 `generatePlan` 技能

---

### 4.3 Executor Agent

**职责**：根据 plan 执行当前 step，不参与「创建任务」「生成计划」。

**是否用 LLM**：是（Cursor/Claude 执行开发）。

**输入**（关键：只传当前 step，不传完整对话）：
```
你只负责执行开发计划的【当前步骤】，不做规划、不创建任务。

## 任务
- taskId: TASK-20260228-001
- planPath: /path/to/docs/plan-xxx.md
- 当前步骤: 2/3

## 当前步骤内容（从 plan 中截取）
### Step 2: 编写功能文档
- 读取 README、核心模块
- 按模板输出 docs/features.md

## 项目路径
/path/to/xassistant

## 要求
1. 仅完成当前步骤
2. 完成后更新 plan 的 Execution Log
3. 输出 JSON: { "ok": true, "nextStep": 3 } 或 { "ok": false, "error": "..." }
```

**系统 prompt 长度**：~800 token + 当前 step 内容（通常 < 2k），无历史。

**输出**：更新 plan、更新 task status，handoff.currentPlanStep++ 或 status=done。

**调用方式**：
- `node cursor-executor.js run-step TASK-20260228-001 2`（需新增 run-step，只执行指定 step）
- 或 OpenClaw skill `executor`，每次调用只执行一个 step

---

### 4.4 Fixer Agent（可选）

**职责**：当某步失败时，分析 lastError，决定重试、跳过或终止。

**输入**：
```
任务 TASK-xxx 在步骤 2 失败。
lastError: "xxx"
handoff: { ... }

请分析并输出: { "action": "retry"|"skip"|"abort", "reason": "..." }
```

---

## 5. 流程配置格式

### 5.1 YAML 示例

```yaml
# workflows/auto-dev.yaml
name: 自动开发
id: auto-dev

steps:
  - id: create
    agent: creator
    # 无 LLM 时用 command 直接执行
    command: create-task
    input:
      title: "{{userRequest.title}}"
      description: "{{userRequest.description}}"
      projectKey: "{{userRequest.projectKey}}"

  - id: plan
    agent: planner
    skill: planner  # 有 LLM 时，OpenClaw 调用的 skill id
    input_from: handoff
    # 或明确指定 prompt 模板
    prompt_template: |
      你只负责生成开发计划。任务: {{handoff.taskId}} {{handoff.title}}
      项目路径: {{handoff.projectPath}}

  - id: execute
    agent: executor
    skill: executor
    input_from: handoff
    loop: plan_steps  # 对 plan 的每个 step 循环调用
```

### 5.2 精简版（第一版用）

```json
{
  "auto-dev": {
    "steps": [
      { "agent": "creator", "command": "create-task" },
      { "agent": "planner", "skill": "planner" },
      { "agent": "executor", "skill": "executor", "loop": "plan_steps" }
    ]
  }
}
```

---

## 6. 编排器（Orchestrator）逻辑

### 6.1 位置（推荐：OpenClaw 技能内）

**推荐**：编排放在 **OpenClaw 技能** 内，作为技能的一个 command。

- 在 `openclaw-skill.json` 中新增技能：`auto-dev` 或 `run-workflow`
- 对应 command：`node openclaw-integration.js run-workflow auto-dev "标题" "描述" projectKey`
- `openclaw-integration.js` 内实现 `runWorkflow('auto-dev', title, description, projectKey)`，内部顺序调用：
  - `createTaskJson()` → `processPending()` 或 `generatePlan()` → `executePlanCursor()`
- OpenClaw 只需调用这一个技能，脚本负责编排，无需 Proxy、无单独 workflow-engine

**优势**：
- 技能自包含：编排逻辑与子技能同属 software-dev 技能包
- 用户选「自动开发」即选编排技能，体验一致
- 无需新增 API、无需改 Proxy

### 6.2 伪代码

```
func RunWorkflow(workflowID string, userRequest UserRequest) error {
    runId := genRunId()
    handoff := Handoff{RunId: runId, Workflow: workflowID, ...}
    
    config := loadWorkflowConfig(workflowID)
    for i, step := range config.Steps {
        handoff.CurrentStep = i + 1
        
        if step.Command != "" {
            // 无 LLM：直接调 node 或 API
            out, err := runCommand(step.Command, handoff)
            if err != nil { return err }
            handoff = mergeHandoff(handoff, out)
        } else {
            // 有 LLM：构造 prompt，调 OpenClaw 或 Cursor CLI
            prompt := renderPrompt(step.PromptTemplate, handoff)
            out, err := callAgent(step.Skill, prompt)
            if err != nil { return err }
            handoff = mergeHandoff(handoff, out)
        }
        
        saveHandoff(runId, handoff)
    }
    return nil
}
```

### 6.3 与 OpenClaw 的集成方式

**方案 A（推荐）：编排作为 OpenClaw 技能**

- 在 `openclaw-skill.json` 新增 `auto-dev` 技能，command 为 `run-workflow auto-dev`
- OpenClaw 调用 `node openclaw-integration.js run-workflow auto-dev "标题" "描述" projectKey`
- `openclaw-integration.js` 内 `runWorkflow()` 按顺序调用子逻辑：create-task-json → process-pending / generatePlan → execute-plan-cursor
- 编排逻辑与子技能同包，用户选「自动开发」即选该技能

**方案 B：编排器在 Proxy，Agent 调 OpenClaw**

- Proxy 的 `POST /workflows/auto-dev/run` 启动流程
- 遇到需 LLM 的 step，Proxy 调 `OpenClaw.SendTask(prompt, skill)`，等待响应
- 需约定 Agent 输出结构化 handoff，实现复杂

**方案 C：编排器独立 Node，不经过 OpenClaw**

- `node workflow-engine.js run auto-dev ...`，直接调 Cursor CLI / API
- OpenClaw 仅做对话入口时，把用户话转成对 workflow API 的调用

---

## 7. Token 消耗对比（估算）

### 7.1 单 Agent 全流程

- 系统 prompt：~2k（覆盖创建、规划、执行）
- 用户多轮：~3k
- Plan 全文：~4k
- 执行中多轮：~10k
- 小计：~19k token/次

### 7.2 多 Agent 分阶段

- Creator：0（无 LLM）或 ~1k（若用 LLM 提炼）
- Planner：~0.5k 系统 + ~2k 输入 + ~3k 输出 ≈ 5.5k
- Executor 每 step：~0.8k 系统 + ~2k 当前 step + ~2k 输出 ≈ 4.8k × N 步
- 3 步执行：5.5k + 4.8k×3 ≈ 19.9k

**单次总量接近**，但：
- 各 Agent 的 context 独立，无历史累积
- 执行 step 可并行/缓存项目上下文
- 长任务时，单 Agent 会持续膨胀，多 Agent 每步 reset，更稳定

---

## 8. 实现清单（按优先级）

### P0：最小可跑通

| 项 | 说明 |
|----|------|
| Handoff 结构体 | Go 或 JS 定义，含 taskId/planPath/currentPlanStep 等 |
| workflow 配置 | `workflows/auto-dev.json`，3 步：create / plan / execute |
| workflow-engine.js | 读配置，顺序调 createTask、generatePlan、executePlan（复用 cursor-executor 现有函数）|
| 入口 | `node workflow-engine.js auto-dev "标题" "描述" projectKey` |

### P1：拆出 Planner / Executor 独立 prompt

| 项 | 说明 |
|----|------|
| cursor-executor plan 子命令 | 只做 generatePlan，不执行 |
| cursor-executor run-step 子命令 | 只执行指定 step，prompt 仅含当前 step |
| workflow-engine 调 run-step 循环 | 替代一次 run 全流程 |

### P2：流程 API + 多流程

| 项 | 说明 |
|----|------|
| POST /workflows/:id/run | Proxy 启动 workflow-engine |
| plan-only 流程 | create + plan，不 execute |
| execute-only 流程 | 输入 taskId，只 execute |

### P3：OpenClaw 技能对接

| 项 | 说明 |
|----|------|
| planner skill | SKILL.md 约束「只生成计划」 |
| executor skill | SKILL.md 约束「只执行当前 step」 |
| 约定 handoff 输出格式 | Agent 末尾输出 `<handoff>{"taskId":"..."}</handoff>` |

---

## 9. 文件结构建议

### 9.1 编排在 OpenClaw 技能内（推荐）

```
xassistant/skills/software-dev/
├── openclaw-skill.json           # 新增 auto-dev 技能
├── openclaw-integration.js       # 新增 runWorkflow() 及 run-workflow 分支
├── cursor-executor.js            # 可选：增加 plan, run-step 子命令
├── workflows/
│   └── auto-dev.json             # 流程配置（步骤列表）
└── .workflow-runs/               # 可选：handoff 与日志
```

**openclaw-skill.json 新增：**

```json
{
  "id": "auto-dev",
  "name": "自动开发",
  "description": "创建任务 → 生成 plan → 执行开发，全流程编排",
  "command": "run-workflow",
  "usage": "node openclaw-integration.js run-workflow auto-dev \"标题\" \"描述\" <projectKey>"
}
```

**openclaw-integration.js 新增分支：**

```javascript
// 在 main/parseArgs 中
if (cmd === 'run-workflow') {
  const workflowId = args[1];  // auto-dev
  const title = args[2];
  const description = args[3];
  const projectKey = args[4];
  return this.runWorkflow(workflowId, title, description, projectKey);
}

async runWorkflow(workflowId, title, description, projectKey) {
  if (workflowId === 'auto-dev') {
    // 复用 cursor-executor 的完整流程
    const { autoDevWorkflow } = require('./cursor-executor.js');
    return await autoDevWorkflow(title, description || title, projectKey);
  }
  // 其他 workflow 可读 config 逐步执行
}
```

### 9.2 独立编排器（备选）

```
xassistant/
├── workflows/
│   └── auto-dev.json
├── skills/software-dev/
│   ├── workflow-engine.js
│   └── ...
└── proxy/server/workflows.go     # 可选
```

---

## 10. 总结

| 维度 | 设计要点 |
|------|----------|
| 状态 | 6 种 plan 状态，每状态对应一 Agent |
| Handoff | 统一 JSON，每步只传必要字段 |
| Agent | Creator/Planner/Executor（+Fixer），各自独立 prompt |
| 流程配置 | JSON/YAML，steps 数组 |
| 编排器 | Node workflow-engine.js，顺序执行，调现有 skills |
| 与 OpenClaw | 第一版可不用；后续可把 planner/executor 做成 skill |
| Token | 每 Agent 独立 context，无历史累积 |
