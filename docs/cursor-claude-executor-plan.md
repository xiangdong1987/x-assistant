# Cursor 与 Claude Code 任务执行方案

## 现状

- **任务创建/同步**：Proxy `/api/tasks`、`/api/projects` 已有，Flutter App 可创建、查看任务
- **技能**：`skills/software-dev/` 含 `execute-plan`（Claude Code）、`execute-plan-cursor`（Cursor CLI）
- **CapabilitiesScreen**：执行「自动开发」时，Proxy 创建任务 + 发到 OpenClaw，由 OpenClaw 再调用技能
- **问题**：已有任务（planned）无法从 App 直接触发执行；技能仍依赖本地 `config.json`，未统一用 Proxy 任务/项目接口

## 目标架构

```mermaid
flowchart TB
    subgraph App[xassistant App]
        TaskDetail[任务详情]
        Capabilities[开发能力]
    end

    subgraph Proxy
        ExecuteAPI[POST /api/tasks/:id/execute]
        TaskAPI[/api/tasks]
        ProjectAPI[/api/projects]
        SpawnSkill[spawn node run.js --run taskId]
    end

    subgraph Skills[xassistant/skills/software-dev]
        ClaudeRun[execute-plan/run.js]
        CursorRun[execute-plan-cursor/run.js]
    end

    TaskDetail -->|选择执行器| ExecuteAPI
    Capabilities -->|create+execute| TaskAPI
    ExecuteAPI --> SpawnSkill
    SpawnSkill -->|executor=claude| ClaudeRun
    SpawnSkill -->|executor=cursor| CursorRun
    ClaudeRun --> TaskAPI
    ClaudeRun --> ProjectAPI
    CursorRun --> TaskAPI
    CursorRun --> ProjectAPI
```

## 1. Proxy 新增执行接口

在 `proxy/server/server.go` 增加：

**`POST /api/tasks/:id/execute`**

- 参数：`executor=cursor|claude`（query 或 body）
- 逻辑：
  1. 校验任务存在、有 `planPath`、`projectKey`
  2. 查找项目
  3. 根据 workDir 定位技能路径：`{workDir}/skills/software-dev/` 或可配置 `skillBasePath`
  4. `exec.Command("node", "capabilities/execute-plan-cursor/run.js", "--run", taskId)` 或 `execute-plan/run.js`
  5. 异步执行（goroutine），立即返回 `{"success": true, "pid": ...}`
  6. 环境变量传入 `TASK_API_URL`、`TASK_API_TOKEN`，供技能用 tasks-store-remote

## 2. 技能适配 Proxy 任务源

`skills/software-dev/` 中 `cursor-executor.js`、`claude-executor.js` 当前使用：

- `resolveProject()`：读 `config.json` 的 `projects.registry`
- `tasks-store`：本地或 tasks-store-remote（依赖 `taskApiUrl`）

**改造**：

- 新增 `project-resolver-remote.js`：当存在 `taskApiUrl` 时，从 `GET {taskApiUrl}/api/projects` 解析项目
- `cursor-executor`、`claude-executor` 的 `resolveProject` 改为优先使用 remote
- 确保 `config.json` 中 `settings.taskApiUrl` 指向 Proxy；执行时由 Proxy 通过环境变量注入 `TASK_API_URL`，覆盖 config

## 3. App 执行器选择入口（两处）

### 3.1 任务详情：执行已有计划

`lib/presentation/screens/tasks/task_detail_screen.dart`：

- 当任务有 `planPath` 且状态为 `planned` 时，菜单增加：
  - 「用 Cursor 执行」
  - 「用 Claude Code 执行」
- 调用 `taskApiService.executeTask(taskId, executor: 'cursor'|'claude')`

### 3.2 开发能力：创建并执行时的执行器选择

`lib/presentation/screens/capabilities/capabilities_screen.dart`：

**方案 A（推荐）**：合并为单一「自动开发」能力，弹窗内增加执行器选择

- 将 `execute-plan` 与 `execute-plan-cursor` 合并为一条「自动开发」卡片
- 弹窗内增加 **执行器选择**：`SegmentedButton` 或 `Radio`，选项为「Cursor」「Claude Code」
- 选择项目、标题、描述后，根据所选执行器调用 `execute-plan-cursor` 或 `execute-plan`

**方案 B**：保留两条卡片，仅优化文案

- 保留「自动开发 (Claude)」「自动开发 (Cursor)」两张卡片
- 用户通过点击不同卡片选择执行器（已实现）

建议采用方案 A，使「选择 Cursor 还是 Claude Code」在单一流程中清晰可见。

## 4. 技能路径配置

Proxy 需知道 skills 目录：

- 方案 A：`workDir` 即 xassistant 根，skills 在 `{workDir}/skills/`
- 方案 B：新增配置 `skillBasePath`（如 `proxy/config/skill_paths.json` 或单独配置）
- 建议：优先用 `workDir`，若不存在则从启动参数读取 `--skills-path`

## 5. 执行状态同步

- 技能执行时通过 `tasks-store-remote` 调用 `PUT /api/tasks/:id` 更新 status（developing → completed）
- Flutter 任务列表已有轮询或 WebSocket，可继续沿用，确保能拿到最新状态

## 6. 关键文件清单

| 模块 | 文件 | 变更 |
|------|------|------|
| Proxy | `proxy/server/server.go` | 新增 `POST /api/tasks/:id/execute?executor=cursor\|claude` |
| 技能 | `skills/software-dev/project-resolver-remote.js` | 新建，从 Proxy 拉取项目 |
| 技能 | `cursor-executor.js`、`claude-executor.js` | `resolveProject` 支持 remote |
| Flutter | `lib/services/task_api_service.dart` | 新增 `executeTask(id, executor)` |
| Flutter | `lib/presentation/screens/tasks/task_detail_screen.dart` | 菜单增加「用 Cursor 执行」「用 Claude Code 执行」 |
| Flutter | `lib/presentation/screens/capabilities/capabilities_screen.dart` | 自动开发弹窗增加执行器选择（Cursor / Claude Code） |
| Flutter | `lib/models/capability_model.dart` | 若采用方案 A：合并为单条「自动开发」，capability 传 executor 参数 |

## 7. 数据流示例

1. **从任务详情执行**：用户打开任务详情 → 点击「用 Cursor 执行」→ Flutter `POST /api/tasks/TASK-xxx/execute?executor=cursor` → Proxy 启动 `node capabilities/execute-plan-cursor/run.js --run TASK-xxx`，注入 `TASK_API_URL` → 技能用 tasks-store-remote 更新状态 → App 刷新任务列表看到 developing/completed

2. **从 Capabilities 执行**：现有流程保持不变，创建任务后发往 OpenClaw，由 OpenClaw 调用技能（或可改为直接 spawn 技能，视需求调整）
