---
name: software-dev-agent-status
description: Query agent status from tmux sessions. Returns running state, pane info, last output lines for debugging. Use when users want to check if an agent is running, see agent output, or list all running agents for a project.
metadata: {"openclaw":{"requires":{"anyBins":["tmux","node"]},"emoji":"📊"}}
---

# Agent Status

**Queries agent status** from tmux sessions. Returns running state, pane information, and last output lines for debugging.

## When to Use (LLM Intent Matching)
- "Check agent status", "Is agent running?", "Show running agents"
- User wants to see agent output or debug issues
- User wants to list all running agents for a project

## Parameters (Required Fields)
- **taskId** (string): Task ID to check (for status query)
- **OR projectKey** (string): Project key (for list query)

## Command
Execute in **skill repository root directory**:
```bash
# Query status of specific task
node agent-status-skill.js status <taskId>

# List all agents for a project
node agent-status-skill.js list <projectKey>
```

## Example
```bash
# Check status of specific task
node agent-status-skill.js status TASK-20260304-123

# List all running agents
node agent-status-skill.js list xassistant
```

## Pane Status Values
- **running**: Process is alive, not active
- **active**: Pane has focus/recent activity
- **stopped**: Process has exited
- **unknown**: Cannot determine status
- **stale**: Task shows "developing" but pane stopped

## Output
Returns:
- task status and metadata
- pane status (running/stopped/active/unknown)
- tmux metadata (session, window, paneId)
- last output lines (for debugging)
- working directory

## HANDOFF Format
```json
{
  "ok": true,
  "skill": "agent.status",
  "version": "1.0",
  "data": {
    "taskId": "TASK-20260304-123",
    "title": "Implement feature X",
    "status": "developing",
    "paneStatus": "running",
    "tmux": {
      "session": "xassistant",
      "window": "dev",
      "paneId": "xassistant:0.1",
      "backend": "tuxme",
      "logPath": "logs/exec-TASK-20260304-123.log"
    }
  },
  "error": null
}
```

## List Command Output
```json
{
  "ok": true,
  "skill": "agent.status",
  "version": "1.0",
  "data": {
    "projectKey": "xassistant",
    "totalAgents": 2,
    "running": 1,
    "stopped": 1,
    "agents": [...]
  },
  "error": null
}
```