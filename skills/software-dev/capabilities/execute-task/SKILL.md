---
name: software-dev-execute-task
description: Execute planned development tasks with configurable backend (Claude or Cursor). Processes tasks with status=planned and executes them using unified executor with backend abstraction. State transitions: planned → developing → reviewing. Stops after execution - does not automatically mark tasks as done. Use when users need to execute development tasks, run implementation plans, or perform software development workflows. Automatically triggers when users mention "execute task", "run plan", "develop", "implement", or any execution-related activities for software projects.
metadata: {"openclaw":{"requires":{"anyBins":["node"]},"emoji":"⚡"}}
---

# Execute Task (Skill 3 of 3)

**Executes the Code phase** of planned tasks using configurable backend (Claude or Cursor CLI), via the unified `run-phase` entrypoint. This skill is a thin wrapper over `run-phase <taskId> code`, ensuring all execution goes through the phase pipeline (PhaseOrchestrator + backend factory).

## ⚠️ IMPORTANT: Phase-Scoped Execution
- This skill **only executes the current `code` phase** for a given task.
- It does **not** automatically run `test` or `done` phases.
- It does **not** automatically mark the task as done.
- It should be used when the user explicitly wants to execute the implementation phase, and then manually (or via other skills) trigger later phases like `test` or `done`.

## ⚠️ IMPORTANT: Scope Constraint
**Execute ONLY what the plan specifies.**
- Do NOT add extra features, optimizations, or improvements beyond the plan
- Do NOT expand requirements or add steps not in the plan
- Implement minimal scope when plan is ambiguous

## When to Use (LLM Intent Matching)
- "Execute task", "Run plan", "Develop", "Implement"
- User wants to execute a development plan or run implementation
- User has a planned task and wants to execute it

## Parameters (Required Fields)
- **taskId** (string): Task ID (internal numeric ID or display ID like TASK-YYYYMMDD-NNN)
- **backend** (optional, string): Backend to use, either "claude" (default) or "cursor"

## Command
Execute in **skill repository root directory**:
```bash
# Execute Code phase with default backend (claude)
node openclaw-integration.js run-phase <taskId> code

# Execute Code phase with specific backend
node openclaw-integration.js run-phase <taskId> code --backend cursor
```

## Workflow
1. Validate task has a plan file and current phase is `code` (by PhaseOrchestrator).
2. Execute the Code phase using the configured backend via PhaseExecutor/UnifiedExecutor.
3. Update the plan Execution Log for the Code phase and transition task.phase to `test`.
4. **STOP** – later phases (`test`, `done`) should be triggered via subsequent `run-phase` calls or auto scheduling.

## Output
- Task execution results with stdout/stderr
- Task status updated to `reviewing` or `failed`
- HANDOFF JSON with execution summary

## State Transitions
`planned` → `developing` → `reviewing` (STOP here)
     ↓           ↓          ↓
   `failed`   `failed`   `failed`

## Example
```bash
# Execute Code phase with Cursor backend
node openclaw-integration.js run-phase 123 code --backend cursor

# Execute Code phase with Claude backend
node openclaw-integration.js run-phase TASK-20250302-001 code --backend claude
```

## Backend Configuration
Default backend is set in `config.json`:
```json
{
  "settings": {
    "defaultBackend": "claude",
    "cursorCliCommand": "agent"
  }
}
```