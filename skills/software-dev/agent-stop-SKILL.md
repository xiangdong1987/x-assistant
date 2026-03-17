---
name: software-dev-agent-stop
description: Stop agents running in tmux sessions. Kills the tmux pane and updates task status to failed. Use when users want to stop a running agent, terminate a long-running task, or clean up tmux panes.
metadata: {"openclaw":{"requires":{"anyBins":["tmux","node"]},"emoji":"🛑"}}
---

# Agent Stop

**Stops an agent** running in a tmux session. Sends interrupt signal (Ctrl+C) for graceful shutdown by default, or force kills the pane. Updates task status to "failed" after stopping.

## When to Use (LLM Intent Matching)
- "Stop agent", "Kill agent", "Stop running task"
- User wants to terminate a long-running agent
- User wants to clean up tmux panes
- User wants to abort a task

## Parameters (Required Fields)
- **taskId** (string): Task ID to stop

## Parameters (Optional Fields)
- **force** (boolean): Force kill the pane immediately (skip graceful shutdown)
- **no-status-update** (boolean): Do not update task status to failed

## Command
Execute in **skill repository root directory**:
```bash
node agent-stop-skill.js stop <taskId> [--force] [--no-status-update]
```

## Example
```bash
# Gracefully stop agent (send Ctrl+C)
node agent-stop-skill.js stop TASK-20260304-123

# Force kill immediately
node agent-stop-skill.js stop TASK-20260304-123 --force

# Stop without updating task status
node agent-stop-skill.js stop TASK-20260304-123 --no-status-update
```

## Behavior

### Graceful Stop (default)
1. Send Ctrl+C to the pane (SIGINT)
2. Wait up to 5 seconds for graceful shutdown
3. If pane still exists, keep it (or use --force)

### Force Stop
1. Immediately kill the tmux pane
2. No graceful shutdown attempt

### Status Update
- By default, task status changes to `failed` with error message
- Use `--no-status-update` to skip status change
- Clears tmux metadata (session, window, paneId) after stopping

## Output
Returns:
- taskId and title
- paneId that was killed
- killed: boolean (true if pane was terminated)
- newStatus: updated task status

## HANDOFF Format
```json
{
  "ok": true,
  "skill": "agent.stop",
  "version": "1.0",
  "data": {
    "taskId": "TASK-20260304-123",
    "title": "Implement feature X",
    "paneId": "xassistant:0.1",
    "killed": true,
    "newStatus": "failed",
    "message": "Agent stopped successfully"
  },
  "error": null
}
```

## Error Handling
- If no tmux pane associated: Returns success with message "No tmux pane associated"
- If pane already stopped: Returns success with message "Pane already stopped"
- Clears tmux metadata in all cases