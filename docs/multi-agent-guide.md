# 多 Agent 协作指南

本文档描述 xassistant 项目中的多 Agent 角色、职责边界、阶段流转和协作方式。

## 概述

xassistant 支持两种多 Agent 模式：

| 模式 | 描述 | 适用场景 |
|------|------|----------|
| **单会话流水线** | 一个执行流程按阶段依次调用不同能力 | 当前默认模式，适合大多数任务 |
| **多会话 Team** | Lead 协调多个独立会话，各自负责不同阶段 | 复杂任务、并行开发、未来扩展 |

## Agent 角色

### Lead / 编排者 (Orchestrator)

**职责**：
- 维护共享任务/阶段状态（plan 文件中的 phase + Execution Log）
- 负责任务分配与阶段推进：Plan → Code → Test → Done
- 实现渐进式披露：每个阶段只向执行 Agent 传入当前阶段所需信息

**实现**：
- `phase-orchestrator.js`：阶段流水线协调器
- OpenClaw 主会话中的「主 agent」

### Plan Agent（做 Plan）

**职责**：
- 只读：探索代码库、收集需求与约束
- 产出：生成/更新 plan 文件（generate-plan）
- 可选「Plan 确认」人工或 Lead 审批后再进入 Code 阶段

**对应**：
- `generate-plan` capability
- Gateway 的 `generate_plan` tool（未来）
- Claude Code 的 Plan subagent 式只读研究

**输入**：
- 任务目标
- 项目约束
- 可探索的代码库

**输出**：
- 完整的开发计划文档
- Plan 阶段 Execution Log 勾选完成

### Code Agent（做 Coding）

**职责**：
- 可写：按 plan 实现代码
- 产出：代码变更
- 完成后阶段推进为 `phase = test`

**对应**：
- `execute-task` / `execute-plan` capability
- Gateway 的 `execute_code` tool（未来）
- agent.start + backend (tuxme/cursor/claude)

**输入（渐进式披露）**：
- Plan 中「Implementation (Code)」块
- 本阶段涉及文件列表
- 不包含后续 Test 阶段细节

**输出**：
- 代码实现
- Code 阶段 Execution Log 勾选完成

### Test Agent（做 Test）

**职责**：
- 只跑测试、汇总结果
- 不改业务代码（或仅改测试代码）
- 产出：测试通过/失败
- 通过则阶段推进为 `phase = done`

**对应**：
- `run_tests` 能力（npm test / pytest 等）
- Gateway 的 `run_tests` tool（未来）

**输入**：
- 测试范围
- 通过标准
- 运行命令

**输出**：
- 测试结果
- Test 阶段 Execution Log 勾选完成

### 自动提交

**触发条件**：`phase = done` 且测试通过

**职责**：
- `git add` 约定范围
- `git commit -m "<message>"`
- 仅本地提交，是否 push 可配置

**对应**：
- `phase-orchestrator.js` 的 `autoCommit` 方法
- Gateway 的 `git_commit` tool（未来）

## 阶段流转

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│  Plan   │───▶│  Code   │───▶│  Test   │───▶│  Done   │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
     │              │              │              │
     ▼              ▼              ▼              ▼
 Plan Agent    Code Agent    Test Agent    auto-commit
```

### 阶段状态字段

任务和 plan 文件中的 `phase` 字段表示当前阶段：

| Phase | 含义 | 下一步 |
|-------|------|--------|
| `plan` | 生成/确认计划中 | → `code` |
| `code` | 代码实现中 | → `test` |
| `test` | 测试验证中 | → `done` |
| `done` | 完成，待提交 | → commit |

### 任务状态映射

| Task Status | Phase | 说明 |
|-------------|-------|------|
| `pending` | - | 待生成 plan |
| `planned` | `plan` | Plan 完成，待执行 |
| `inProgress` / `developing` | `code` / `test` | 执行中 |
| `completed` | `done` | 已完成 |
| `failed` | - | 执行失败 |
| `cancelled` | - | 已取消 |

## 渐进式披露

**目标**：每个 Agent 只看到其当前阶段所需的信息，避免上下文歧义。

### 披露原则

1. **按阶段披露**：
   - Plan Agent：任务目标 + 约束 + 可探索的代码库
   - Code Agent：Plan 的 Code 段 + 本阶段文件/范围
   - Test Agent：测试范围 + 通过标准 + 运行命令
   - 提交步骤：变更列表 + commit message 规则

2. **不提前暴露**：
   - 不把「后续阶段的 plan 细节」传给 Code Agent
   - 不把「代码实现细节」传给 Plan Agent
   - 不把「未完成阶段的勾选」当作已完成

3. **契约边界**：
   - 阶段之间通过「plan 文件中该阶段的输入/输出」和 meta 的 phase 状态通信
   - 编排者负责「从 plan 中裁剪出当前阶段的 view」再下发

### 实现方式

```javascript
// phase-orchestrator.js 中的 getPhasePlanContent 方法
const content = orchestrator.getPhasePlanContent(planPath, 'code');
// 只返回 Code 阶段所需的内容，不包含 Plan/Test 阶段细节
```

## 使用指南

### 运行完整流水线

```bash
# 通过 openclaw-integration.js
node openclaw-integration.js phase-pipeline TASK-20260305-001

# 或直接调用 phase-orchestrator.js
node phase-orchestrator.js run TASK-20260305-001

# 跳过自动提交
node phase-orchestrator.js run TASK-20260305-001 --skip-commit

# 模拟运行
node phase-orchestrator.js run TASK-20260305-001 --dry-run
```

### 单独执行某阶段

```bash
# 生成 Plan
node openclaw-integration.js generate-plan TASK-20260305-001

# 执行 Code（使用指定 backend）
node openclaw-integration.js execute-task TASK-20260305-001 --backend=cursor

# 推进阶段
node openclaw-integration.js phase-advance TASK-20260305-001 code
```

### 获取阶段内容

```bash
# 获取 Code 阶段所需的 plan 片段
node openclaw-integration.js phase-content /path/to/plan.md code
```

## 与 Gateway 的对应关系

当 Gateway 支持多 tool 注册时，各阶段对应：

| Tool 名称 | 功能 | Agent |
|-----------|------|-------|
| `generate_plan` | 生成开发计划 | Plan Agent |
| `execute_code` | 执行代码实现 | Code Agent |
| `run_tests` | 运行测试 | Test Agent |
| `git_commit` | 提交代码 | auto-commit |
| `advance_phase` | 推进阶段 | Lead/Orchestrator |

## 未来扩展：多会话 Team

当需要真正的多 Agent 并行时：

1. **Lead 进程**：在 OpenClaw 或本地协调多个 Teammate 进程
2. **Teammate 进程**：每个 Teammate 一个 tmux pane 或 Cursor/Claude Code 会话
3. **共享状态**：store 或 plan 文件
4. **任务领取**：Lead 通过 API 或消息把「当前可领任务」发给 Teammate
5. **Plan 审批**：Plan Agent 产出 plan 后，Lead 或人工 approve 再开放 code 任务

---

## 相关文件

- `phase-orchestrator.js`：阶段流水线协调器
- `openclaw-integration.js`：OpenClaw 集成接口
- `proxy/tasks/model.go`：Task 结构定义（含 Phase 字段）
- `templates/plan-template.md`：Plan 模板（含阶段化 Execution Log）
