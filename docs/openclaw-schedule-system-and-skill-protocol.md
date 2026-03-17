## OpenClaw 日程系统与技能协议设计

### 1. 目标与约束

- **核心目标**
  - 设计一套本地 **日程系统模型**，支持多项目、多来源（日程源）写入。
  - 让 **OpenClaw 通过技能调用** 将日程安全、可重入地同步到本地日程系统。
  - 同步过程 **幂等、可重入、可去重**，多次调用不会产生重复或脏数据。
  - 设计一套 **通用技能调用协议**，便于未来“任意系统之间”通过技能交互，而不仅限于 OpenClaw。

- **约束**
  - 遵守现有技能风格：独立 `*-skill.js` 文件 + CLI + `HANDOFF:{...}` JSON 输出，位于 `skills/software-dev/` 下。
  - 每个技能域最多 3 个技能：
    - **软件开发域（已存在）**：`create-task-skill`, `generate-plan-skill`, `execute-task-skill`。
    - **OpenClaw / 日程域（本设计）**：`openclaw-sync-schedule-skill`, `openclaw-agenda-skill`, `openclaw-schedule-maintenance-skill`。

---

### 2. 日程系统底层数据模型

建议实现一个独立的“日程域模型”模块（例如未来落在 `skills/software-dev/schedule-store.js` 一类文件中）。

- **实体：ScheduleSource（日程来源）**
  - 作用：标记日程来自哪里，支持多系统并存（OpenClaw、手工创建、其他日历等）。
  - 字段示例：
    - `id`: 内部自增 ID。
    - `key`: 源标识字符串，例如 `openclaw`, `manual`, `google_calendar`。
    - `displayName`: 友好展示名称。
    - `config`: 源级别配置（API endpoint、鉴权方式等）。

- **实体：ScheduleItem（统一日程条目）**
  - 每一条日程（会议、DDL 等）在系统内部都转成该结构：
    - `id`: 内部自增 ID。
    - `sourceKey`: 对应 `ScheduleSource.key`（例如 `openclaw`）。
    - `externalId`: 外部系统的唯一 ID（OpenClaw 提供，作为幂等与去重主键的一部分）。
    - `externalVersion`: 外部版本号或更新时间戳（用于检测是否需要更新）。
    - `domain`: 领域/类型，用于区分开发相关还是生活/其它，例如 `dev`（开发相关）、`work_other`（非编码工作）、`life`（生活相关）。
    - `projectKey`: 关联项目（如 `xassistant`），从标题、标签或显式字段推断/指定。
    - `title`: 标题。
    - `description`: 描述。
    - `startTime`, `endTime`: ISO8601 时间。
    - `allDay`: 是否全天。
    - `status`: 如 `scheduled`, `cancelled`, `completed`。
    - `type`: 类别（`meeting`, `deadline`, `reminder` 等）。
    - `participants`: 可选数组，记录参与者信息。
    - `tags`: 字符串数组，可用于规则引擎（如 `#focus`）。
    - `lastSyncedAt`: 最近同步时间。
    - `hash`: 基于关键字段计算出的哈希，用于快速判断内容是否变化（辅助去重与更新）。

- **实体：ScheduleTaskLink（日程 ↔ 任务 关系）**
  - 为解耦任务系统与日程系统，使用关系实体维护二者关联：
    - `id`: 内部 ID。
    - `scheduleItemId`: 指向 `ScheduleItem.id`。
    - `taskId`: 指向任务存储中的任务 ID（通过 `tasks-store-adapter` 管理）。
    - `linkType`: 关系类型，如 `prep`（会前准备）、`follow_up`、`main_work` 等。
    - `createdAt`, `updatedAt`。

- **幂等 & 去重策略**
  - **单源幂等键**：`(sourceKey, externalId)` 必须唯一，重复同步时以此为依据做 upsert：
    - 若不存在 → 新建 `ScheduleItem`。
    - 若存在 → 比较 `externalVersion` 或 `hash`，决定是否更新。
  - **软删除/取消**：外部日程被取消时，OpenClaw 通过 `status=cancelled` 或 `cancelled=true` 通知；本地仅更新状态而非物理删除，以保留历史及与任务的关系。

---

### 3. OpenClaw 日程同步技能：`openclaw-sync-schedule-skill`

#### 3.1 职责与位置

- 建议位置：`skills/software-dev/openclaw-sync-schedule-skill.js`。
- 职责：
  - 接收 OpenClaw 提供的一批日程（也可以在 skill 内主动调用 OpenClaw API 拉取）。
  - 将日程按 `ScheduleItem` 模型写入/更新（幂等、重入、去重）。
  - 根据规则为日程创建/更新对应任务，并维护 `ScheduleTaskLink`。

#### 3.2 调用方式与输入协议

- **CLI 调用示例**
  - 直接传入 payload 文件（事件文件已统一放在 `data/events/` 下）：
    - `node openclaw-sync-schedule-skill.js sync --payload-file=data/events/events.json`
    - 仅传文件名时技能会到 `data/events/` 下查找，如 `--payload-file=events.json`
  - 或按时间范围由 skill 自行去拉取：
    - `node openclaw-sync-schedule-skill.js sync --from=2026-03-01 --to=2026-03-07`

- **输入 JSON（使用 payload 文件时）**

```json
{
  "sourceKey": "openclaw",
  "requestId": "oc-20260303-001",
  "events": [
    {
      "externalId": "evt_123",
      "externalVersion": "2026-03-03T10:00:00Z",
      "projectKey": "xassistant",
      "domain": "dev",
      "title": "X 助手架构评审",
      "description": "评审当前多项目任务管理方案",
      "startTime": "2026-03-04T10:00:00Z",
      "endTime": "2026-03-04T11:00:00Z",
      "status": "scheduled",
      "type": "meeting",
      "tags": ["review", "#focus"]
    }
  ]
}
```

#### 3.3 输出协议（HANDOFF）

```json
HANDOFF:{
  "ok": true,
  "skill": "openclaw-sync-schedule",
  "version": "1.0",
  "sourceKey": "openclaw",
  "requestId": "oc-20260303-001",
  "data": {
    "syncedCount": 10,
    "created": [
      { "scheduleItemId": 1, "externalId": "evt_123", "taskIds": ["TASK-..."] }
    ],
    "updated": [
      { "scheduleItemId": 2, "externalId": "evt_124", "changes": ["time", "title"] }
    ],
    "skipped": [
      { "externalId": "evt_125", "reason": "no_change" }
    ]
  },
  "error": null
}
```

- **幂等行为**
  - 以 `(sourceKey, externalId)` 查找已存在记录，比较 `externalVersion` 或 `hash`：
    - 内容未变 → 记录在 `skipped`，不改动。
    - 内容变更 → 更新 `ScheduleItem`，并在 `updated` 中返回；如需要，同步调整相关任务（例如时间字段）。

#### 3.4 与任务系统的衔接规则

- 建议通过配置（如 `config.json` 或独立规则文件）定义：
  - 哪些类型/标签/领域的日程需要生成任务（例如 `type=deadline` 或带 `#focus` 标签，且 `domain=dev`）。
  - `domain` 归类策略：
    - 若 payload 中显式提供 `domain`，直接使用。
    - 否则：有 `projectKey` 或包含仓库/项目名、issue 链接等信息 → 默认 `dev`。
    - 标题/描述中出现典型生活关键词（如“吃饭”“健身”“家里”“休息”等）→ 默认 `life`。
    - 其余归为 `work_other`，后续可手动修正。
  - `projectKey` 映射策略：
    - 优先使用 payload 中显式字段；
    - 若缺失，可基于标题正则、标签、默认 project 进行推断。
  - 创建任务时：
    - 通过 CLI 或直接 require 调用现有 `create-task-skill`；
    - 在成功创建后写入一条 `ScheduleTaskLink`。
  - 日程更新时：
    - 时间变更 → 更新相关任务的 `planned_start` / `planned_end`；
    - 日程取消 → 将关联任务标记为 `blocked` 或其他预设状态，并记录原因。

---

### 4. 日程查询技能：`openclaw-agenda-skill`

#### 4.1 职责与位置

- 建议位置：`skills/software-dev/openclaw-agenda-skill.js`。
- 职责：
  - 读取本地 `ScheduleItem` + `ScheduleTaskLink` + 任务存储，汇总出指定时间范围的“日程 + 任务”视图。
  - 为 OpenClaw 或其他系统提供一个“今天/本周要做什么”的统一 JSON 结果。
  - 只读，不修改任何数据。

#### 4.2 调用方式与输出协议

- **CLI 调用示例**
  - 按项目 + 时间范围查询开发相关日程：
    - `node openclaw-agenda-skill.js agenda --from=2026-03-03 --to=2026-03-03 --project=xassistant --domain=dev`
  - 查询生活相关日程：
    - `node openclaw-agenda-skill.js agenda --from=2026-03-03 --to=2026-03-03 --domain=life`

- **输出 HANDOFF 示例**

```json
HANDOFF:{
  "ok": true,
  "skill": "openclaw-agenda",
  "version": "1.0",
  "from": "2026-03-03",
  "to": "2026-03-03",
  "projectKey": "xassistant",
  "data": {
    "agenda": [
      {
        "time": "2026-03-03T10:00:00Z",
        "title": "X 助手代理集成调试",
        "projectKey": "xassistant",
        "type": "meeting",
        "scheduleItemId": 1,
        "linkedTasks": [
          { "taskId": "TASK-...", "status": "planned" }
        ]
      },
      {
        "time": null,
        "title": "修复 proxy / OpenClaw 400 错误处理",
        "projectKey": "xassistant",
        "type": "task",
        "taskId": "TASK-...",
        "status": "pending"
      }
    ]
  },
  "error": null
}
```

- OpenClaw 基于 `agenda` 结果，可以实现“今日工作安排”“每周计划生成”等高层能力，而无需直接访问本地存储。

---

### 5. 日程维护技能：`openclaw-schedule-maintenance-skill`

> 此技能用于“数据质量维护”，而不是系统健康检测。

#### 5.1 职责与位置

- 建议位置：`skills/software-dev/openclaw-schedule-maintenance-skill.js`。
- 职责：
  - 检查并列出疑似重复或异常的 `ScheduleItem`（如时间/标题高度相似但 externalId 不同）。
  - 提供批量或按 ID 的“合并 / 标记 superseded / 修正 projectKey / 重建 ScheduleTaskLink”等操作。
  - 为长期运行的日程系统提供简单的“整理”和“纠偏”能力。

#### 5.2 调用方式与输出协议

- **CLI 调用示例**
  - 仅列出疑似重复：
    - `node openclaw-schedule-maintenance-skill.js detect-duplicates --source=openclaw`
  - 执行合并 / 修正：
    - `node openclaw-schedule-maintenance-skill.js fix --payload-file=fixes.json`

- **检测输出 HANDOFF 示例**

```json
HANDOFF:{
  "ok": true,
  "skill": "openclaw-schedule-maintenance",
  "version": "1.0",
  "action": "detect-duplicates",
  "data": {
    "duplicates": [
      {
        "groupId": "dup_001",
        "items": [
          { "scheduleItemId": 10, "externalId": "evt_aaa" },
          { "scheduleItemId": 12, "externalId": "evt_bbb" }
        ],
        "reason": "same_time_and_title"
      }
    ]
  },
  "error": null
}
```

---

### 6. 通用跨系统技能协议（HANDOFF 规范）

在当前 `HANDOFF` 模式基础上，定义一个轻量级通用协议，写入本文档后，可被所有技能复用，任何外部系统按此约定调用即可。

- **标准输出格式（统一字段）**

```json
HANDOFF:{
  "ok": true,
  "skill": "openclaw-sync-schedule",
  "version": "1.0",
  "requestId": "oc-20260303-001",
  "data": { /* 具体业务数据 */ },
  "error": null
}
```

- **失败时示例**

```json
HANDOFF:{
  "ok": false,
  "skill": "openclaw-sync-schedule",
  "version": "1.0",
  "requestId": "oc-20260303-001",
  "data": null,
  "error": {
    "code": "INVALID_PARAMETER",
    "message": "events[0].externalId is required"
  }
}
```

- **调用侧约定**
  - 无论是 OpenClaw 还是其他系统，只需要：
    1. 以 CLI 或子进程方式运行对应 `*-skill.js`，并传入参数或 payload 文件。
    2. 截取标准输出中最后一行以 `HANDOFF:` 开头的 JSON 串。
    3. 解析其中的 `ok / skill / version / requestId / data / error` 字段，作为统一返回结构。

- **技能目录建议**
  - 在单独文档（如 `docs/skills-protocol.md`）维护一个技能清单，约定：
    - `skill: create-task`
      - script: `skills/software-dev/create-task-skill.js`
      - input: `{ title, description, projectKey, ... }`
      - output.data: `{ taskId, task, nextSteps }`
    - `skill: openclaw-sync-schedule`
      - script: `skills/software-dev/openclaw-sync-schedule-skill.js`
      - input: `{ sourceKey, events: [...] }`
      - output.data: `{ syncedCount, created, updated, skipped }`
    - `skill: openclaw-agenda`
      - script: `skills/software-dev/openclaw-agenda-skill.js`
      - input: `{ from, to, projectKey? }`
      - output.data: `{ agenda: [...] }`
    - `skill: openclaw-schedule-maintenance`
      - script: `skills/software-dev/openclaw-schedule-maintenance-skill.js`
      - input: `{ action, ... }`
      - output.data: `{ duplicates?, fixed?, ... }`

---

### 7. 关系与数据流（架构示意）

```mermaid
flowchart LR
  openclaw[OpenClaw]
  syncSkill[openclawSyncScheduleSkill]
  agendaSkill[openclawAgendaSkill]
  maintenanceSkill[openclawScheduleMaintenanceSkill]
  scheduleStore[ScheduleStore]
  taskStore[TaskStore]
  linkStore[ScheduleTaskLinkStore]
  devSkills[DevSkills(create/generate/execute)]

  openclaw -->|"call sync with payload"| syncSkill
  syncSkill -->|"upsert"| scheduleStore
  syncSkill -->|"create/update tasks"| devSkills
  devSkills -->|"tasks"| taskStore
  syncSkill -->|"link tasks"| linkStore

  openclaw -->|"query agenda"| agendaSkill
  agendaSkill --> scheduleStore
  agendaSkill --> linkStore
  agendaSkill --> taskStore
  agendaSkill -->|"HANDOFF agenda"| openclaw

  openclaw -->|"maintenance ops"| maintenanceSkill
  maintenanceSkill --> scheduleStore
  maintenanceSkill --> linkStore
```

该图展示了 OpenClaw 仅通过 3 个技能与本地系统交互：同步日程、查询 agenda 以及日程数据维护；内部则由日程存储、任务存储和技能共同构成一个幂等、可重入、可去重的日程与任务一体化系统。

