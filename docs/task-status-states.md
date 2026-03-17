# 任务状态与状态机对齐说明

本文档描述 X 助手前后端任务状态的一致定义与同步机制，确保 App 显示与后端状态机一致。

## 规范状态值（Canonical Status）

前后端共同使用的状态值（camelCase，与 Flutter `TaskStatus` 枚举及 Go 常量一致）：

| 状态值 | 含义 |
|--------|------|
| `pending` | 待确认 |
| `confirmed` | 已确认，等待执行 |
| `planned` | 已生成计划，待执行 |
| `planning` | 计划中 |
| `coding` | 执行中（开发阶段） |
| `testing` | 测试中 |
| `submitting` | 提交中 |
| `inProgress` | 执行中（兼容旧数据） |
| `completed` | 已完成 |
| `cancelled` | 已取消 |
| `failed` | 执行失败，可重试 |

阶段成功结束时脚本直接置为下一阶段状态（code→testing、test→submitting、done→completed），不再使用 `waitingFeedback`。自动化可触发状态含 `testing`、`submitting`。

## 后端（Go）

- **定义位置**: `proxy/tasks/model.go` 常量 `Status*`
- **持久化**: 仅持久化上述规范状态；`Update` 时通过 `normalizeTaskStatus` 规范化，非法状态不写入
- **计划同步**: `taskStatusToMetaStatus` / `metaStatusToTaskStatus` 将任务状态与计划 meta 的 status/phase 互相同步
- **定时同步**: 每 5 秒 `SyncTaskStatus` 根据计划文件 meta 更新任务状态并 WebSocket 广播

## 前端（Flutter）

- **定义位置**: `lib/models/task_enums.dart` 枚举 `TaskStatus`
- **解析**: `TaskApiService._parseStatus` / `_statusToString` 与后端字符串一一对应；`task_provider` 中 WebSocket 使用同一套解析（通过 `taskFromJson`）
- **展示**: 列表与详情均使用 `taskNotifierProvider`，状态来自 API 或 WebSocket 推送

## 同步机制

1. **API**: 列表/详情通过 `getTasks()`、`getTask(id)` 拉取，更新通过 `updateStatus`/`updateTask` 提交
2. **WebSocket**: 后端在任务变更时广播 `openclaw_task`（含完整 task 对象）。前端收到后：
   - 已连接 API 时：先用推送 payload 做**乐观更新**（立即合并到列表），再触发一次 `refresh()` 与服务器对齐
   - 未连接 API 时：用 payload 更新本地 Hive 并刷新列表
3. **计划文件**: 后端根据计划 meta 的 `status`/`phase` 定期同步到任务，并广播更新

## 注意事项

- 前端 `TaskFilter` 中「待办」包含 `pending` 与 `confirmed`；「执行中」包含 `inProgress`、`planning`、`coding`、`testing`、`submitting`、`planned`（已计划待执行）、`failed`（执行失败可重试）；「全部」仅排除 `completed`，包含已取消、失败等
- 计划 meta 的 `status`（如 planning / developing / testing / submitting / implemented）与任务 `status` 的映射见 `proxy/tasks/store.go` 中 `taskStatusToMetaStatus`、`metaStatusToTaskStatus`
- 执行后端（Agent）：支持 `cursor`、`ccr`、`claude` 三种，创建任务与详情页可选择
