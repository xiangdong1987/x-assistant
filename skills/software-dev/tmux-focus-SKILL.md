---
name: software-dev-tmux-focus
description: Open iTerm and switch to a specific tmux session/pane to monitor a running agent. Use when user wants to view agent execution in terminal, switch to a task's tmux session in iTerm, or monitor running agents.
metadata: {"openclaw":{"requires":{"anyBins":["tmux","osascript"]},"emoji":"🖥️"}}
---

# Tmux Focus

**Opens iTerm** and switches to a specific tmux session, window, or pane so you can monitor an agent's execution in real time.

## When to Use (LLM Intent Matching)
- "Open iTerm for task X", "Switch to agent session", "Show me the tmux session"
- User wants to monitor a running agent in the terminal
- User wants to see live agent output in iTerm
- User wants to attach to an existing tmux session

## Parameters (Required - one of the following)
- **taskId** (string): Task ID whose tmux metadata will be looked up (e.g., TASK-20260304-123)
- **OR session** (string): Direct tmux session name to focus (e.g., xassistant)

## Parameters (Optional)
- **paneId** (string): Specific pane to focus (e.g., xassistant:0.1). If omitted, focuses the session.
- **window** (string): Window name to focus within session (e.g., dev)

## Command
Execute in **skill repository root directory**:
```bash
# Focus by taskId (looks up tmux metadata from task)
node tmux-focus-skill.js focus --taskId=<taskId>

# Focus by session name directly
node tmux-focus-skill.js focus --session=<sessionName>

# Focus specific pane
node tmux-focus-skill.js focus --session=xassistant --paneId=xassistant:0.1

# List all tmux sessions
node tmux-focus-skill.js list
```

## Example
```bash
# Open iTerm on the task's agent pane
node tmux-focus-skill.js focus --taskId=TASK-20260304-123

# Open iTerm on the xassistant session
node tmux-focus-skill.js focus --session=xassistant
```

## HANDOFF Format
```json
{
  "ok": true,
  "skill": "tmux.focus",
  "version": "1.0",
  "data": {
    "focused": true,
    "session": "xassistant",
    "window": "dev",
    "paneId": "xassistant:0.1"
  },
  "error": null
}
```
