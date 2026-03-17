# XAssistant

[中文](README.zh-CN.md) | English

Unified AI Agent entry: Flutter app for task management, multi-phase automated execution, and real-time feedback, with a Go proxy backend.

## Overview

XAssistant is a task assistant that creates tasks from natural language, generates execution plans, and runs them automatically via Claude Code, Claude Code Remote (ccr), or Cursor IDE. Tasks progress through a multi-phase pipeline (plan → code → test → done) with full automation support. Frontend and backend are separate; the app runs on iOS, Android, macOS, Windows, and Linux.

## Features

### 1. Task Management
- **Lifecycle**: `pending` → `confirmed` → `planning` → `planned` → `coding` → `testing` → `submitting` → `done` (or `failed`)
- **Priority**: P0 / P1 / P2 / P3
- **Sources**: Manual, OpenClaw gateway, Cursor IDE
- **Executors**: Claude Code (`claude`), Claude Code Remote (`ccr`), Cursor

### 2. Multi-Phase Automated Pipeline
Each task progresses through four phases automatically:
- **plan**: Generate execution plan via AI agent
- **code**: Implement code changes
- **test**: Run tests
- **done**: Review, commit, and finalize

The `phaseWatcher` monitors tasks and triggers the appropriate phase. Phase execution can run inline or in a **tmux pane** (async, configurable).

### 3. Dashboard
- Today's tasks, stats (pending / in progress / waiting feedback / completed), quick access to projects

### 4. Projects
- Config (path, tech stack, owner, status), skill association, recent projects

### 5. Skills
- Per-project skills with WebSocket-based execution
- Built-in skills: `create-task`, `execute-task`, `generate-plan`, `agent-start`, `agent-stop`, `agent-status`, `tmux-focus`
- Additional skills: `schedule`, `shutdown`, `db-query`, `italia-company-lookup`

### 6. Real-time
- WebSocket (heartbeat, reconnect), OpenClaw task push, connection status

## Tech Stack

| Layer    | Tech |
|----------|------|
| Frontend | Flutter 3.16+, Riverpod, GoRouter, Hive, WebSocket, Dio |
| Backend  | Go 1.21+, MCP, REST + WebSocket, JWT |
| Skills   | Node.js 18+, tmux |

## Project Layout

```
xassistant/
├── lib/          # Flutter app
├── proxy/        # Go server (MCP, tasks, skills, phase watcher)
├── skills/       # Skill scripts
│   ├── software-dev/   # Core dev automation (plan/code/test/done pipeline)
│   ├── schedule/       # Schedule management
│   ├── shutdown/       # Shutdown automation
│   └── db-query/       # Database query
└── docs/         # Design docs and task plans
```

## Quick Start

### Requirements
- Flutter SDK >= 3.16.0, Dart >= 3.2.0
- Go 1.21+, Node.js >= 18.0
- `jq`, `cursor` / `claude` / `ccr` CLI, `tmux` (for async phase execution)

### Install and Run

```bash
# Frontend
flutter pub get
flutter run

# Backend (from repo root)
cd proxy
go mod download
go run main.go --skills-path="../skills"
```

### Proxy Options

```bash
go run main.go \
  --port 8443 \
  --workdir "/path/to/workspace" \
  --skills-path="../skills" \
  --openclaw \
  --openclaw-url="ws://127.0.0.1:18789" \
  --openclaw-token="your-token" \
  --allow-local-no-auth
```

### Build Release

```bash
flutter build apk --release
flutter build macos --release
```

### macOS Installation & Deployment (Release builds)

GitHub Actions on `release/*` branches will automatically produce a macOS archive that already contains the Go `proxy` binary: `XAssistant-macos.zip`. It is recommended to install from this Release build instead of running `flutter run` directly.

**Steps:**

1. **Download the app bundle**
   - Go to this project's GitHub **Releases** page.
   - Find the target version (usually corresponding to a `release/x.y.z` branch).
   - Download the asset `XAssistant-macos.zip`.

2. **Install the app**
   - Unzip `XAssistant-macos.zip` to get `XAssistant.app`.
   - Drag `XAssistant.app` into `/Applications` (or any folder you prefer).
   - On first launch, macOS Gatekeeper may block the app:
     - Right‑click the app and choose **Open** once, or
     - Run this in a terminal (optional):
       ```bash
       xattr -d com.apple.quarantine /Applications/XAssistant.app
       ```

3. **Start the built‑in proxy (backend)**
   - The Go `proxy` binary is embedded at:
     ```text
     XAssistant.app/Contents/MacOS/proxy
     ```
   - **Recommended way** is to configure and start it via the macOS client's **Proxy Config** screen (界面同时支持 **中文 / English**):
     - In the app, open: `Settings → Proxy Config`.
     - Fill in the form:
       - **Workdir** (工作目录): e.g. `/Volumes/external/code/ai/projects/siyou/xassistant` (contains `proxy/config`, `skills`, etc.)
       - **Skills Path** (技能路径): e.g. `../skills`
       - **Port / OpenClaw / Token** and any other options you need.
     - Click **“Start Proxy / 启动代理”** and the app will launch the embedded `proxy` in the background with the configured parameters.
   - For manual debugging, you can also run it directly in a terminal:
     ```bash
     /Applications/XAssistant.app/Contents/MacOS/proxy \
       --port 8443 \
       --workdir "/Volumes/external/code/ai/projects/siyou/xassistant" \
       --skills-path "../skills" \
       --allow-local-no-auth
     ```
   - It is recommended that `--workdir` points to the repo root so that no extra config files need to be copied.

4. **Configure the frontend to talk to the proxy**
   - Launch `XAssistant.app`.
   - In Settings, set:
     - **HTTP Base URL** → `http://127.0.0.1:8443`
     - **WebSocket URL** → `ws://127.0.0.1:8443/ws`
   - After saving, the task list and phase execution will use the locally running `proxy` and skills.

5. **Upgrade to a new version**
   - For each new Release:
     - Download the new `XAssistant-macos.zip` from GitHub Releases.
     - Replace `/Applications/XAssistant.app` (the embedded `proxy` is updated together).
   - Backend configuration (`projects.json`, `skill_paths.json`, etc.) continues to live under the directory pointed to by `--workdir`, and usually does **not** need to change when you upgrade the app.


## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| /api/tasks | GET/POST | List / create tasks |
| /api/tasks/:id | GET/PUT/DELETE | Task CRUD |
| /api/tasks/:id/plan | GET | Get plan |
| /api/tasks/:id/execute | POST | Execute task |
| /api/tasks/:id/phase/complete | POST | Mark phase complete |
| /ws | WebSocket | Real-time updates |

### Task Status Flow

```
pending → confirmed → planning → planned → coding → testing → submitting → done
                                                                          ↘ failed
```

The proxy syncs task status from plan file meta every 5 seconds and broadcasts changes via WebSocket.

## Configuration

- **App**: In Settings, set HTTP base URL, WebSocket URL, and optional token.
- **Proxy projects**: Copy `proxy/config/projects.example.json` to `projects.json` and set your project paths.
- **Skill paths** (no hardcoded absolute paths):
  - **Env**: `XASSISTANT_SKILL_PATHS=/path/to/skills` (or `path1:path2` on Unix).
  - **File**: Copy `skill_paths.example.json` to `skill_paths.json`. Use relative paths (e.g. `["skills"]`, `["../skills"]`), `~/...`, or `$HOME/...`; they are resolved at runtime using `--workdir`.
- **Skill config**: In `skills/software-dev/config.json`, set `projectBasePath` to your projects root, and `settings.executor` to `cursor`, `ccr`, or `claude`.

## Skills

Each skill has `SKILL.md` and a `run.js` (or similar). Example:

```bash
cd skills/software-dev
node openclaw-integration.js generate-plan <taskId>
node openclaw-integration.js run-phase <taskId> code
```

## Docs

- [Phase flow & state machine](docs/phase-flow.md)
- [Task status states](docs/task-status-states.md)
- [tmux agent usage](docs/tmux-agent-usage.md)
- [Cursor executor plan](docs/cursor-claude-executor-plan.md)
- [Multi-agent workflow](docs/design-workflow-multi-agent.md)
- [OpenClaw integration](docs/openclaw-unified-ui-skills.md)
- [Skills redesign](docs/skills-task-redesign.md)

## Sponsor / Donate

If XAssistant is useful to you, consider supporting the project:

- **[Buy Me a Coffee](https://buymeacoffee.com/xiangdong14)** — one-time or monthly support

Thank you.

## License

MIT
