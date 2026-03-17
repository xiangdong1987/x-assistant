---
name: software-dev-generate-plan
description: Generate plan files for pending tasks. Processes all tasks with status=pending (or specific taskId) and generates docs/plan-{taskId}.md files, updating status to planned. Stops after plan generation - does not execute development or mark tasks as complete. Use when users need to generate implementation plans, process pending tasks, or create development roadmaps. Automatically triggers when users mention "generate plan", "process pending", "create plan", or any planning-related activities for software projects.
metadata: {"openclaw":{"requires":{"anyBins":["node"]},"emoji":"📋"}}
---

# Generate Plan (Skill 2 of 3)

**Processes all pending tasks** (or specific taskId) → Generate taskId, create `plan-{taskId}.md` in project `docs/` directory, change status to `planned`.

## ⚠️ IMPORTANT: Single-Step Execution
**This skill ONLY generates plan files and STOPS.**
- Do NOT automatically execute the task
- Do NOT call execute-task skill
- Do NOT perform any development work
- Wait for user to explicitly request execution

## When to Use (LLM Intent Matching)
- "Process pending", "Generate plans", "Create development plan"
- User wants to create plans without executing development
- User has created tasks and now wants to generate plan files

## Parameters
- **taskId** (optional, string): Specific task ID to process, or omit for all pending tasks

## Command
Execute in **skill repository root directory**:
```bash
# Generate plans for all pending tasks
node openclaw-integration.js generate-plan

# Generate plan for specific task
node openclaw-integration.js generate-plan <taskId>
```

## Example
```bash
# Process all pending
node openclaw-integration.js generate-plan

# Process specific task
node openclaw-integration.js generate-plan TASK-20250302-001
```

## State Transition
`pending` → `planned` (plan file generated)

## Output
Returns plan file path and confirmation. User must explicitly invoke execute-task skill if they want to proceed.
