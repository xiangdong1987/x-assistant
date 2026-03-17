# OpenClaw 多 Agent 注册（待实施）

## 概述

本文档描述 OpenClaw 多 Agent 注册的实施方案，属于「任务生命周期与多 Agent 整改」计划的第 7 项。

## 当前状态

⏳ **待实施** - 需要 Gateway 侧配合

## 目标

在 Gateway 侧注册多个 tool，由主 agent（Lead）按 phase 调用，实现真正的多 Agent 协作。

## Gateway Tool 注册计划

### Tool 清单

| Tool 名称 | 功能 | 对应角色 | 输入 | 输出 |
|-----------|------|----------|------|------|
| `generate_plan` | 生成开发计划 | Plan Agent | 任务目标、约束 | plan 文件路径 |
| `execute_code` | 执行代码实现 | Code Agent | plan 的 code 段、文件列表 | 代码变更结果 |
| `run_tests` | 运行测试 | Test Agent | 测试范围、通过标准 | 测试结果 |
| `git_commit` | 提交代码 | Lead/Done | 变更列表、commit message | commit hash |

### 注册配置示例

```json
{
  "tools": [
    {
      "name": "generate_plan",
      "description": "生成开发计划。只读：探索代码库、收集需求与约束。",
      "input_schema": {
        "type": "object",
        "properties": {
          "taskId": { "type": "string", "description": "任务 ID" },
          "projectKey": { "type": "string", "description": "项目 Key" },
          "description": { "type": "string", "description": "任务描述" }
        },
        "required": ["taskId", "projectKey"]
      }
    },
    {
      "name": "execute_code",
      "description": "执行代码实现。可写：按 plan 实现代码。",
      "input_schema": {
        "type": "object",
        "properties": {
          "taskId": { "type": "string", "description": "任务 ID" },
          "phase": { "type": "string", "enum": ["code"], "description": "当前阶段" },
          "planSection": { "type": "string", "description": "plan 的 code 段内容" }
        },
        "required": ["taskId"]
      }
    },
    {
      "name": "run_tests",
      "description": "运行测试。只跑测试、汇总结果；不改业务代码。",
      "input_schema": {
        "type": "object",
        "properties": {
          "taskId": { "type": "string", "description": "任务 ID" },
          "testScope": { "type": "string", "description": "测试范围" },
          "passCriteria": { "type": "string", "description": "通过标准" }
        },
        "required": ["taskId"]
      }
    },
    {
      "name": "git_commit",
      "description": "提交代码变更。",
      "input_schema": {
        "type": "object",
        "properties": {
          "taskId": { "type": "string", "description": "任务 ID" },
          "files": { "type": "array", "items": { "type": "string" }, "description": "变更文件列表" },
          "message": { "type": "string", "description": "commit message" }
        },
        "required": ["taskId", "message"]
      }
    }
  ]
}
```

## xassistant 侧对接

### Tool 回调处理

在 `proxy/openclaw/task_bridge.go` 或新建 `proxy/openclaw/tool_handlers.go` 中处理 tool 回调：

```go
// ToolHandler 处理 Gateway tool 回调
type ToolHandler func(params map[string]interface{}) (map[string]interface{}, error)

// RegisterToolHandlers 注册所有 tool 处理器
func (b *TaskBridge) RegisterToolHandlers() map[string]ToolHandler {
    return map[string]ToolHandler{
        "generate_plan": b.handleGeneratePlan,
        "execute_code":  b.handleExecuteCode,
        "run_tests":     b.handleRunTests,
        "git_commit":    b.handleGitCommit,
    }
}

func (b *TaskBridge) handleGeneratePlan(params map[string]interface{}) (map[string]interface{}, error) {
    taskId := params["taskId"].(string)
    projectKey := params["projectKey"].(string)

    // 调用 skills 侧的 generate-plan capability
    result, err := b.skillManager.ExecuteSkill("generate-plan", "generate",
        fmt.Sprintf("--taskId=%s", taskId),
        fmt.Sprintf("--projectKey=%s", projectKey),
    )
    // ... 解析结果并返回
}
```

### 任务 Phase 更新

Tool 执行完成后更新任务 phase：

```go
func (b *TaskBridge) handleExecuteCode(params map[string]interface{}) (map[string]interface{}, error) {
    // ... 执行代码

    // 更新 phase 为 test
    if success {
        b.store.Update(taskId, &UpdateTaskRequest{
            Phase: ptr("test"),
        })
    }
}
```

## 渐进式披露实现

### Plan 内容裁剪

每个 tool 只接收当前阶段的 plan 片段：

```javascript
// phase-orchestrator.js 中的 getPhasePlanContent
function getPhasePlanContent(planPath, phase) {
    const parsed = parsePlanFile(planPath);

    switch (phase) {
        case 'plan':
            return {
                overview: parsed.overview,
                // 不包含 code/test 细节
            };
        case 'code':
            return {
                overview: parsed.overview,
                codeSection: parsed.phases.code,
                // 不包含 test 细节
            };
        case 'test':
            return {
                testSection: parsed.phases.test,
                // 不包含 code 实现细节
            };
        case 'done':
            return {
                summary: parsed.summary,
                // 最小化信息
            };
    }
}
```

## 路径 B：多会话 Team（后续扩展）

当需要真正的多 Agent 并行执行时：

1. **Lead 进程**：在 OpenClaw 或本地协调
2. **Teammate 进程**：每个角色一个 tmux pane 或独立会话
3. **共享状态**：store 或 plan 文件
4. **消息传递**：Lead 通过 API 把任务发给 Teammate

### 多 pane 架构

```
┌─────────────────────────────────────────────────────────┐
│                      tmux session                        │
├──────────────────┬──────────────────┬──────────────────┤
│   Plan Agent     │   Code Agent     │   Test Agent     │
│   (pane 0)       │   (pane 1)       │   (pane 2)       │
│                  │                  │                  │
│   - 只读模式     │   - 可写模式     │   - 测试模式     │
│   - 生成 plan    │   - 实现代码     │   - 运行测试     │
└──────────────────┴──────────────────┴──────────────────┘
```

### agent.start 扩展

扩展 `agent-start-skill.js` 支持按角色启动：

```bash
# 按 role 启动
node agent-start-skill.js start <projectKey> <taskId> <backend> --role=plan
node agent-start-skill.js start <projectKey> <taskId> <backend> --role=code
node agent-start-skill.js start <projectKey> <taskId> <backend> --role=test
```

## 实施依赖

1. **Gateway 支持**：Tool 注册和回调机制
2. **OpenClaw 协议**：支持 tool_call 格式
3. **Proxy 改造**：添加 tool handler 路由

## 下一步行动

1. 与 Gateway 团队确认 tool 注册方式
2. 实现 `proxy/openclaw/tool_handlers.go`
3. 扩展 `agent-start-skill.js` 支持 `--role` 参数
4. 端到端测试多 Agent 协作流程

## 相关文件

- `skills/software-dev/phase-orchestrator.js`：阶段流水线协调器
- `proxy/openclaw/task_bridge.go`：OpenClaw 事件桥接
- `proxy/tasks/model.go`：Task 结构（含 Phase 字段）
- `docs/multi-agent-guide.md`：多 Agent 协作指南
