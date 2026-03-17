---
name: OpenClaw Schedule Management
description: |
  日程同步、查询与维护技能，支持从 OpenClaw 等来源幂等写入本地日程系统。
---

# OpenClaw Schedule Management

本目录包含日程系统管理的三个核心技能：

## 技能列表

### openclaw-sync-schedule
从 OpenClaw 或其他来源同步日程事件到本地，支持幂等写入和自动创建关联任务。

**用法：**
```bash
# 事件 payload 文件请放在 data/events/ 下（该目录已 .gitignore，不提交）
node openclaw-sync-schedule-skill.js sync --payload-file=data/events/events.json
```

### openclaw-agenda
查询指定日期范围内的日程（含关联任务），返回聚合视图。

**用法：**
```bash
node openclaw-agenda-skill.js agenda --from=2026-03-03 --to=2026-03-03
```

### openclaw-schedule-maintenance
检测重复日程，辅助数据清理。

**用法：**
```bash
node openclaw-schedule-maintenance-skill.js detect-duplicates
```

## 数据存储
- `data/schedules.json`: 日程事件存储
- `data/links.json`: 日程与任务的关联关系
- `data/events/`: 事件 payload 文件目录（sync 的 `--payload-file` 建议指向此目录下文件），已加入 .gitignore，不提交

## 生成/新建说明（事件 payload 文件）
**凡新建或生成供 sync 使用的事件 JSON 文件，必须放在 `data/events/` 下，不要放在本技能根目录。**
- 正确：`data/events/xxx-event.json`、`data/events/events.json`
- 错误：技能根目录下的 `xxx-event.json`（会导致被误提交或路径混乱）
- 调用时可用相对路径或仅文件名，例如：`--payload-file=data/events/events.json` 或 `--payload-file=events.json`（技能会在 `data/events/` 下解析）

## HANDOFF 协议
所有技能均通过 `HANDOFF:{...}` JSON 输出结果，由 Go Proxy 解析并转发给 Flutter 客户端。
