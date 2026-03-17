---
name: software-dev-agent-start
description: Start agents in tmux sessions for task execution. Creates tmux session/window/pane for the specified task and starts the agent command. Automatically tracks tmux metadata (session, window, paneId) in task. Use when users want to run an agent in the background, start a long-running task, or attach to an existing tmux session for monitoring.
metadata: {"openclaw":{"requires":{"anyBins":["tmux","node"]},"emoji":"🚀"}}
---

# Agent Start

**Starts an agent** in a tmux session for the specified task. Creates a tmux session for the project if not exists, allocates a window and pane, then starts the agent command in that pane.

## When to Use (LLM Intent Matching)
- "Start agent", "Run agent in background", "Start development agent"
- User wants to run a task in tmux for long-running execution
- User wants to monitor agent output in terminal
- User wants to start a task that persists across terminal sessions

## Parameters (Required Fields)
- **projectKey** (string): Project key (e.g., xassistant)
- **taskId** (string): Task ID to execute (e.g., TASK-20260304-123)
- **backend** (string): Backend type (tuxme, cursor, claude)

## Parameters (Optional Fields)
- **window** (string): Window name (default: dev, other options: schedule, infra)

## Command
Execute in **skill repository root directory**:
```bash
node agent-start-skill.js start <projectKey> <taskId> <backend> [--window=<windowName>]
```

## Example
```bash
# Start tuxme agent for task
node agent-start-skill.js start xassistant TASK-20260304-123 tuxme

# Start cursor agent in dev window
node agent-start-skill.js start xassistant TASK-20260304-123 cursor --window=dev
```

## TMUX Structure
- Session: `<projectKey>` (e.g., xassistant)
- Window: `<windowName>` (default: dev)
- Pane: `<session>:<windowIndex>.<paneIndex>` (e.g., xassistant:0.1)

## State Transition
Task transitions from `planned` → `developing` (if in planned state)

## Output
Returns tmux metadata:
- session: TMUX session name
- window: TMUX window name
- paneId: Full pane ID for attachment
- logPath: Execution log file path

## HANDOFF Format
```json
{
  "ok": true,
  "skill": "agent.start",
  "version": "1.0",
  "data": {
    "projectKey": "xassistant",
    "taskId": "TASK-20260304-123",
    "backend": "tuxme",
    "tmux": {
      "session": "xassistant",
      "window": "dev",
      "paneId": "xassistant:0.1"
    },
    "logPath": "logs/exec-TASK-20260304-123.log"
  },
  "error": null
}
```