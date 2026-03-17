# Software Development Skills - OpenClaw Integration Guide

## 概述

软件开发生态已重组为3个核心技能，并已完成 OpenClaw 系统的集成。

## 技能列表

### 新的3个核心技能（推荐）

1. **software-dev-create-task** (➕)
   - 创建开发任务，状态为 `pending`
   - 不自动生成计划（解耦合）
   - 命令: `create-task-json "Title" "Description" <projectKey>`

2. **software-dev-generate-plan** (📋)
   - 为 pending 任务生成计划文件
   - 状态转换: `pending` → `planned`
   - 命令: `generate-plan [taskId]`

3. **software-dev-execute-task** (⚡)
   - 使用可配置后端（Claude 或 Cursor）执行计划
   - 状态转换: `planned` → `developing` → `reviewing` → `done/failed`
   - 命令: `execute-task <taskId> [--backend claude|cursor]`

### 已弃用的旧技能（向后兼容）

- **software-dev-execute-plan** - 仅支持 Claude 后端
- **software-dev-execute-plan-cursor** - 仅支持 Cursor 后端

> ⚠️ 建议使用新的3个核心技能，以获得更好的状态管理和后端支持

## OpenClaw 配置

### 方式1: 使用 capabilities 目录（推荐）

OpenClaw 可以自动加载 `capabilities/` 目录下的独立技能：

```bash
# 配置 OpenClaw 的 extraDirs 指向 capabilities 目录
# 在 OpenClaw 配置中添加:
{
  "extraDirs": ["/path/to/skills/software-dev/capabilities"]
}
```

### 方式2: 符号链接到 OpenClaw skills 目录

```bash
# 创建符号链接
ln -s /path/to/skills/software-dev/capabilities/* ~/.openclaw/skills/

# 或者链接整个 capabilities 目录
ln -s /path/to/skills/software-dev/capabilities ~/.openclaw/skills/software-dev-capabilities
```

### 方式3: 直接添加技能到 OpenClaw skills 目录

```bash
# 复制技能目录到 OpenClaw
cp -r /path/to/skills/software-dev/capabilities/* ~/.openclaw/skills/
```

## 技能目录结构

```
capabilities/
├── create-task/           # Skill 1: 创建任务
│   ├── SKILL.md           # 技能定义
│   └── run.js             # 执行脚本
├── generate-plan/          # Skill 2: 生成计划
│   ├── SKILL.md           # 技能定义
│   └── run.js             # 执行脚本
├── execute-task/           # Skill 3: 执行任务（新）
│   ├── SKILL.md           # 技能定义
│   └── run.js             # 执行脚本
├── execute-plan/           # 旧技能（已弃用）
│   ├── SKILL.md
│   └── run.js
└── execute-plan-cursor/   # 旧技能（已弃用）
    ├── SKILL.md
    └── run.js
```

## 系统提示词配置

### 推荐的系统提示词

```
软件开发任务必须通过3个解耦的技能按顺序完成：

1. create-task: 创建任务，状态=pending（不自动生成计划）
2. generate-plan: 为 pending 任务生成计划文件，状态=pending → planned
3. execute-task: 使用可配置后端执行计划，状态=planned → developing → reviewing → done/failed

当用户要求创建任务时，使用 create-task 技能。
当用户要求生成计划或处理 pending 时，使用 generate-plan 技能。
当用户要求执行或开发时，使用 execute-task 技能。

后端选择：使用 --backend 标志选择 claude（默认）或 cursor。

execute-task 完成后，任务处于 'reviewing' 状态 - 用户必须验证并手动使用 mark-done 命令标记为完成。

向后兼容：旧命令（process-pending, execute-plan-cursor）仍然有效，但建议迁移到新技能。
```

### 技能触发条件

**create-task**:
- "创建任务", "add task", "register requirement", "new development task"
- 用户指定需要在某个项目中完成某些操作并需要创建任务条目

**generate-plan**:
- "生成计划", "process pending", "create development plan"
- 用户想要创建计划而不执行开发
- 用户已创建任务，现在想要生成计划文件

**execute-task**:
- "执行任务", "run plan", "develop", "implement"
- 用户想要执行开发计划或运行实现
- 用户有计划任务并想要执行它

## 完整工作流示例

### 用户的交互流程

```
用户: "帮我添加一个任务，实现用户登录功能"
LLM: 调用 create-task 技能
→ 创建任务，status=pending

用户: "生成计划"
LLM: 调用 generate-plan 技能
→ 生成计划文件，status=planned

用户: "使用 Cursor 执行这个任务"
LLM: 调用 execute-task 技能，参数: --backend cursor
→ 执行开发，status=developing → reviewing

用户: "任务完成了，标记为完成"
LLM: 调用 mark-done 命令
→ 标记任务，status=done
```

### 直接命令行使用

```bash
# Step 1: 创建任务
node openclaw-integration.js create-task-json "用户登录" "实现OAuth2登录" my-project
# 输出: Task created with status=pending

# Step 2: 生成计划
node openclaw-integration.js generate-plan
# 输出: Plan files created, status=planned

# Step 3: 执行任务
node openclaw-integration.js execute-task <taskId> --backend cursor
# 输出: Task execution, status=reviewing

# Step 4: 标记为完成
node openclaw-integration.js mark-done <taskId>
# 输出: Task completed, status=done
```

## 状态机

```
pending → planned → developing → reviewing → done
     ↓         ↓           ↓          ↓
   failed   failed      failed     failed
```

### 状态说明

- **pending**: 任务已创建，无计划文件
- **planned**: 计划文件已生成（docs/plan-{taskId}.md 存在）
- **developing**: 执行已开始（明确跟踪）
- **reviewing**: 执行完成，等待审核/验证
- **done**: 任务已完成并验证
- **failed**: 任何步骤失败

## 后端支持

### Claude Code CLI

```bash
node openclaw-integration.js execute-task <taskId> --backend claude
```

**要求**:
- 安装 Claude Code CLI
- `claude` 命令在 PATH 中

### Cursor CLI

```bash
node openclaw-integration.js execute-task <taskId> --backend cursor
```

**要求**:
- 安装 Cursor CLI
- `agent` 命令在 PATH 中

**安装**:
```bash
# macOS / Linux / WSL
curl https://cursor.com/install -fsS | bash

# Windows PowerShell
irm 'https://cursor.com/install?win32=true' | iex
```

## 配置文件

### config.json

```json
{
  "name": "software-dev-agent",
  "version": "2.0.0",
  "settings": {
    "defaultBackend": "claude",
    "taskApiUrl": "http://localhost:8443",
    "taskSystemUrl": "http://localhost:3001",
    "pollingInterval": 30000,
    "executionTimeoutMs": 300000,
    "planTimeoutMs": 180000,
    "cursorCliCommand": "agent"
  }
}
```

### 设置说明

- **defaultBackend**: 默认后端（claude 或 cursor）
- **executionTimeoutMs**: 执行超时时间（毫秒）
- **planTimeoutMs**: 计划生成超时时间（毫秒）
- **cursorCliCommand**: Cursor CLI 命令名称（默认为 agent）

## 迁移指南

### 从旧技能迁移

如果你之前使用以下旧命令：

```bash
# 旧方式
node openclaw-integration.js process-pending
node openclaw-integration.js execute-plan-cursor "Title" "Description" projectKey
node openclaw-integration.js run-workflow auto-dev "Title" "Description" projectKey
```

**新方式**（推荐）:

```bash
# 新方式 - 分离的3个步骤
node openclaw-integration.js create-task-json "Title" "Description" projectKey
node openclaw-integration.js generate-plan
node openclaw-integration.js execute-task <taskId> --backend cursor
```

### 迁移优势

✅ **可配置后端**: 在 Claude 和 Cursor 之间选择
✅ **更好的状态跟踪**: 明确的6状态状态机
✅ **解耦的技能**: 清晰的关注点分离
✅ **更好的错误处理**: 带后端抽象的统一执行
✅ **可维护性**: 更容易调试和扩展

## 故障排除

### 技能不被识别

1. 检查 OpenClaw 配置中的 `extraDirs`
2. 验证技能目录包含 `SKILL.md` 和 `run.js`
3. 重启 OpenClaw 以重新加载技能

### 后端验证失败

1. 确认 Claude/Cursor CLI 已安装
2. 验证命令在 PATH 中（运行 `claude --version` 或 `agent --version`）
3. 检查 config.json 中的后端配置

### 状态转换错误

1. 验证任务当前状态（`list-tasks-json`）
2. 确保按正确顺序调用技能
3. 检查 state-machine.js 中的状态转换规则

## 验证

### 测试技能加载

```bash
# 检查技能是否被 OpenClaw 识别
# 在 OpenClaw 中查看已加载的技能列表
```

### 测试完整工作流

```bash
# 测试创建任务
node openclaw-integration.js create-task-json "测试任务" "测试描述" test-project

# 列出 pending 任务
node openclaw-integration.js list-tasks-json pending

# 生成计划
node openclaw-integration.js generate-plan

# 列出 planned 任务
node openclaw-integration.js list-tasks-json planned

# 执行任务
node openclaw-integration.js execute-task <taskId> --backend claude

# 标记为完成
node openclaw-integration.js mark-done <taskId>
```

## 文件清单

### 核心文件
- `/skills/software-dev/SKILL.md` - 主技能定义
- `/skills/software-dev/config.json` - 配置文件
- `/skills/software-dev/openclaw-integration.js` - 集成入口点
- `/skills/software-dev/openclaw-skill.json` - 技能 JSON 定义

### 新架构文件
- `/skills/software-dev/unified-executor.js` - 统一执行器
- `/skills/software-dev/state-machine.js` - 状态机
- `/skills/software-dev/claude-backend.js` - Claude 后端
- `/skills/software-dev/cursor-backend.js` - Cursor 后端
- `/skills/software-dev/create-task-skill.js` - 创建任务技能
- `/skills/software-dev/generate-plan-skill.js` - 生成计划技能
- `/skills/software-dev/execute-task-skill.js` - 执行任务技能
- `/skills/software-dev/tasks-store.js` - 任务存储（已更新）

### 能力（Capabilities）文件
- `/skills/software-dev/capabilities/create-task/SKILL.md`
- `/skills/software-dev/capabilities/create-task/run.js`
- `/skills/software-dev/capabilities/generate-plan/SKILL.md`
- `/skills/software-dev/capabilities/generate-plan/run.js`
- `/skills/software-dev/capabilities/execute-task/SKILL.md`
- `/skills/software-dev/capabilities/execute-task/run.js`
- `/skills/software-dev/capabilities/execute-plan/SKILL.md`（已弃用）
- `/skills/software-dev/capabilities/execute-plan/run.js`（已弃用）
- `/skills/software-dev/capabilities/execute-plan-cursor/SKILL.md`（已弃用）
- `/skills/software-dev/capabilities/execute-plan-cursor/run.js`（已弃用）

## 支持

如需帮助，请参考：

- 实现总结: `/docs/software-dev-reorg-implementation.md`
- OpenClaw 文档（检查 OpenClaw 系统文档）
- 技能定义文件（每个 capability 目录下的 SKILL.md）
