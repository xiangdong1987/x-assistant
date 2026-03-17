---
name: software-dev-create-task
description: Create development tasks with status=pending. Adds new tasks to the task repository (requires title, description, projectKey). Does NOT automatically generate plans or execute any follow-up steps. Use when users need to create software development tasks, add tasks to projects, or register requirements. Automatically triggers when users mention "create task", "add task", "register requirement", "new development task", or any task creation requests for software projects.
metadata: {"openclaw":{"requires":{"anyBins":["node"]},"emoji":"➕"}}
---

# Create Task (Skill 1 of 3)

**Adds new tasks** to the task repository with status=pending. Must specify the target project `projectKey`.

## ⚠️ IMPORTANT: Single-Step Execution
**This skill ONLY creates a task and STOPS.**
- Do NOT automatically call generate-plan
- Do NOT automatically execute the task
- Do NOT perform any follow-up actions
- Wait for user to explicitly request the next step

## When to Use (LLM Intent Matching)
- "Create task", "Add a task", "Register requirement", "New development task"
- User specifies something needs to be done in a particular project and needs to create a task entry

## Parameters (Required Fields)
- **title** (string): Task title
- **description** (string): Requirement description, can be same as title
- **projectKey** (string): Project key, must exist in config.json or remote API

## Command
Execute in **skill repository root directory** (or call via run.js):
```bash
node openclaw-integration.js create-task-json "Title" "Description" <projectKey>
```

## Example
```bash
node openclaw-integration.js create-task-json "Inventory Sync API" "Develop inventory synchronization interface" my-project
```

## State Transition
`pending` (task created, no plan file yet)

## Output
Returns task ID and confirmation. User must explicitly invoke generate-plan skill if they want to proceed.
