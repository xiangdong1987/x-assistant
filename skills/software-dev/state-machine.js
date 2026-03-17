#!/usr/bin/env node

/**
 * State Machine for Software Development Tasks
 *
 * Complete state machine with explicit state tracking:
 * pending → planned → developing → reviewing → done
 *     ↓         ↓           ↓          ↓
 *   failed   failed      failed     failed
 *
 * State Definitions:
 * - pending: Task created, no plan file
 * - planned: Plan file generated (docs/plan-{taskId}.md exists)
 * - developing: Execution started (explicitly tracked in task store)
 * - reviewing: Execution complete, awaiting review/verification
 * - done: Task completed and verified
 * - failed: Any step fails
 */

const fs = require('fs');

// ---------- State Constants ----------

const TaskStates = {
    PENDING: 'pending',
    PLANNED: 'planned',
    DEVELOPING: 'developing',
    REVIEWING: 'reviewing',
    DONE: 'done',
    FAILED: 'failed'
};

// Define state transitions
const StateTransitions = {
    [TaskStates.PENDING]: [TaskStates.PLANNED, TaskStates.FAILED],
    [TaskStates.PLANNED]: [TaskStates.DEVELOPING, TaskStates.FAILED],
    [TaskStates.DEVELOPING]: [TaskStates.REVIEWING, TaskStates.FAILED],
    [TaskStates.REVIEWING]: [TaskStates.DONE, TaskStates.DEVELOPING, TaskStates.FAILED],
    [TaskStates.DONE]: [], // Terminal state
    [TaskStates.FAILED]: [TaskStates.PLANNED] // 允许 failed → planned 以重试执行
};

// Terminal states (cannot transition from)
const TerminalStates = [TaskStates.DONE, TaskStates.FAILED];

// Active states (can receive work)
const ActiveStates = [
    TaskStates.PENDING,
    TaskStates.PLANNED,
    TaskStates.DEVELOPING,
    TaskStates.REVIEWING
];

// Initial state
const InitialState = TaskStates.PENDING;

// ---------- State Machine Class ----------

class TaskStateMachine {
    constructor(task = null) {
        this.task = task;
        this.currentStatus = task?.status || InitialState;
        this.history = [];
    }

    /**
     * Get current state
     */
    getCurrentState() {
        return this.currentStatus;
    }

    /**
     * Check if a transition is valid
     */
    canTransitionTo(newState) {
        // If same state, allow (no-op)
        if (newState === this.currentStatus) {
            return true;
        }

        // Check if current state allows this transition
        const allowedTransitions = StateTransitions[this.currentStatus] || [];
        return allowedTransitions.includes(newState);
    }

    /**
     * Transition to new state with validation
     */
    transitionTo(newState, metadata = {}) {
        // Validate state
        if (!Object.values(TaskStates).includes(newState)) {
            throw new Error(`Invalid state: ${newState}`);
        }

        // Check if transition is valid
        if (!this.canTransitionTo(newState)) {
            throw new Error(
                `Invalid state transition: ${this.currentStatus} → ${newState}`
            );
        }

        // If same state, just return
        if (newState === this.currentStatus) {
            return {
                success: true,
                currentState: this.currentStatus,
                skipped: true
            };
        }

        // Record transition
        const transition = {
            from: this.currentStatus,
            to: newState,
            timestamp: new Date().toISOString(),
            metadata
        };

        this.history.push(transition);
        this.currentStatus = newState;

        return {
            success: true,
            currentState: this.currentStatus,
            transition
        };
    }

    /**
     * Check if current state is terminal
     */
    isTerminal() {
        return TerminalStates.includes(this.currentStatus);
    }

    /**
     * Check if current state is active (can receive work)
     */
    isActive() {
        return ActiveStates.includes(this.currentStatus);
    }

    /**
     * Get transition history
     */
    getHistory() {
        return [...this.history];
    }

    /**
     * Get possible next states
     */
    getNextPossibleStates() {
        return StateTransitions[this.currentStatus] || [];
    }

    /**
     * Get state information
     */
    getStateInfo() {
        return {
            currentState: this.currentStatus,
            isTerminal: this.isTerminal(),
            isActive: this.isActive(),
            possibleNextStates: this.getNextPossibleStates(),
            transitionCount: this.history.length
        };
    }
}

// ---------- State Management Functions ----------

/**
 * Update task status with state machine validation
 */
function updateTaskStatus(task, newStatus, metadata = {}) {
    const stateMachine = new TaskStateMachine(task);

    try {
        const result = stateMachine.transitionTo(newStatus, metadata);

        if (result.success) {
            // Update task with new state and timestamps
            const updatedTask = { ...task };

            // Update status
            updatedTask.status = newStatus;
            updatedTask.updatedAt = new Date().toISOString();

            // Add timestamps based on state
            switch (newStatus) {
                case TaskStates.PLANNED:
                    if (!updatedTask.plannedAt) {
                        updatedTask.plannedAt = new Date().toISOString();
                    }
                    break;

                case TaskStates.DEVELOPING:
                    updatedTask.developingStartTime = new Date().toISOString();
                    break;

                case TaskStates.REVIEWING:
                    updatedTask.developingEndTime = new Date().toISOString();
                    updatedTask.reviewingStartTime = new Date().toISOString();
                    break;

                case TaskStates.DONE:
                    updatedTask.reviewingEndTime = new Date().toISOString();
                    updatedTask.completedAt = new Date().toISOString();
                    break;

                case TaskStates.FAILED:
                    updatedTask.failedAt = new Date().toISOString();
                    updatedTask.error = metadata.error || 'Task failed';
                    break;
            }

            // Add transition history
            if (!result.skipped && result.transition) {
                if (!updatedTask.transitions) {
                    updatedTask.transitions = [];
                }
                updatedTask.transitions.push(result.transition);
            }

            return {
                success: true,
                task: updatedTask,
                stateResult: result
            };
        }
    } catch (error) {
        return {
            success: false,
            error: error.message,
            currentStatus: stateMachine.getCurrentState(),
            attemptedStatus: newStatus
        };
    }
}

/**
 * Batch update multiple task statuses
 */
function updateTaskStatuses(tasks, statusUpdates) {
    const results = [];
    const failures = [];

    for (const task of tasks) {
        const update = statusUpdates.find(s => s.taskId === task.id || s.taskId === task.taskId);

        if (!update) {
            continue;
        }

        const result = updateTaskStatus(task, update.status, update.metadata || {});

        if (result.success) {
            results.push({
                taskId: task.id || task.taskId,
                task: result.task
            });
        } else {
            failures.push({
                taskId: task.id || task.taskId,
                error: result.error
            });
        }
    }

    return {
        success: failures.length === 0,
        results,
        failures,
        total: results.length,
        failed: failures.length
    };
}

/**
 * Validate task status
 */
function validateTaskStatus(task) {
    if (!task || !task.status) {
        return {
            valid: false,
            error: 'Task missing status'
        };
    }

    if (!Object.values(TaskStates).includes(task.status)) {
        return {
            valid: false,
            error: `Invalid task status: ${task.status}`
        };
    }

    const stateMachine = new TaskStateMachine(task);

    return {
        valid: true,
        currentState: stateMachine.getCurrentState(),
        isTerminal: stateMachine.isTerminal(),
        isActive: stateMachine.isActive(),
        stateInfo: stateMachine.getStateInfo()
    };
}

/**
 * Get tasks by state
 */
function getTasksByState(tasks, state) {
    return tasks.filter(task => task.status === state);
}

/**
 * Get active tasks
 */
function getActiveTasks(tasks) {
    return tasks.filter(task => ActiveStates.includes(task.status));
}

/**
 * Get terminal state tasks
 */
function getTerminalTasks(tasks) {
    return tasks.filter(task => TerminalStates.includes(task.status));
}

/**
 * Calculate task statistics
 */
function calculateTaskStats(tasks) {
    const stats = {};

    for (const state of Object.values(TaskStates)) {
        stats[state] = 0;
    }

    for (const task of tasks) {
        if (task.status && stats[task.status] !== undefined) {
            stats[task.status]++;
        }
    }

    stats.total = tasks.length;
    stats.active = getActiveTasks(tasks).length;
    stats.terminal = getTerminalTasks(tasks).length;

    return stats;
}

/**
 * Get state description
 */
function getStateDescription(state) {
    const descriptions = {
        [TaskStates.PENDING]: 'Task created, no plan file',
        [TaskStates.PLANNED]: 'Plan file generated',
        [TaskStates.DEVELOPING]: 'Execution in progress',
        [TaskStates.REVIEWING]: 'Execution complete, awaiting review',
        [TaskStates.DONE]: 'Task completed and verified',
        [TaskStates.FAILED]: 'Task failed'
    };

    return descriptions[state] || 'Unknown state';
}

// ---------- State Schema Utilities ----------

/**
 * Get schema for task with state machine fields
 */
function getTaskSchema() {
    return {
        id: 'string',
        taskId: 'string|null',
        title: 'string',
        description: 'string',
        projectKey: 'string',
        status: Object.values(TaskStates).join('|'),
        planPath: 'string|null',
        priority: 'string',
        assignee: 'string',
        createdAt: 'ISO string',
        updatedAt: 'ISO string',
        plannedAt: 'ISO string|null',
        developingStartTime: 'ISO string|null',
        developingEndTime: 'ISO string|null',
        reviewingStartTime: 'ISO string|null',
        reviewingEndTime: 'ISO string|null',
        completedAt: 'ISO string|null',
        failedAt: 'ISO string|null',
        error: 'string|null',
        transitions: 'array|null'
    };
}

/**
 * Validate task schema
 */
function validateTaskSchema(task) {
    const schema = getTaskSchema();
    const errors = [];

    for (const [field, type] of Object.entries(schema)) {
        if (task[field] === undefined || task[field] === null) {
            if (!type.includes('null')) {
                errors.push(`Missing required field: ${field}`);
            }
        }
    }

    if (task.status && !Object.values(TaskStates).includes(task.status)) {
        errors.push(`Invalid status: ${task.status}`);
    }

    return {
        valid: errors.length === 0,
        errors
    };
}

// ---------- Migration Utilities ----------

/**
 * Migrate old task schema to new schema
 */
function migrateTaskSchema(oldTask) {
    const newTask = { ...oldTask };

    // Add missing state machine fields
    if (!newTask.plannedAt) {
        newTask.plannedAt = newTask.planPath ? oldTask.updatedAt : null;
    }

    // Map old states to new states if needed
    if (newTask.status === 'todo' || newTask.status === 'todo') {
        newTask.status = TaskStates.PENDING;
    }

    // Ensure transitions array exists
    if (!newTask.transitions) {
        newTask.transitions = [];
    }

    return newTask;
}

/**
 * Migrate multiple tasks
 */
function migrateTaskSchemas(tasks) {
    return tasks.map(task => migrateTaskSchema(task));
}

// ---------- Exports ----------

module.exports = {
    TaskStates,
    StateTransitions,
    TerminalStates,
    ActiveStates,
    InitialState,
    TaskStateMachine,
    updateTaskStatus,
    updateTaskStatuses,
    validateTaskStatus,
    getTasksByState,
    getActiveTasks,
    getTerminalTasks,
    calculateTaskStats,
    getStateDescription,
    getTaskSchema,
    validateTaskSchema,
    migrateTaskSchema,
    migrateTaskSchemas
};

// ---------- CLI Interface ----------

if (require.main === module) {
    (async () => {
        const args = process.argv.slice(2);
        const command = args[0];

        if (command === 'validate') {
            const taskData = args[1];
            if (!taskData) {
                console.log('Usage: node state-machine.js validate <task-json>');
                process.exit(1);
            }

            try {
                const task = JSON.parse(taskData);
                const result = validateTaskStatus(task);

                if (result.valid) {
                    console.log('✅ Task status is valid');
                    console.log(`   Current state: ${result.currentState}`);
                    console.log(`   State: ${getStateDescription(result.currentState)}`);
                    console.log(`   Is terminal: ${result.isTerminal}`);
                    console.log(`   Is active: ${result.isActive}`);
                    process.exit(0);
                } else {
                    console.error(`❌ Task status validation failed: ${result.error}`);
                    process.exit(1);
                }
            } catch (error) {
                console.error(`❌ Invalid JSON: ${error.message}`);
                process.exit(1);
            }
        } else if (command === 'transition') {
            const currentStatus = args[1];
            const newStatus = args[2];

            if (!currentStatus || !newStatus) {
                console.log('Usage: node state-machine.js transition <currentStatus> <newStatus>');
                process.exit(1);
            }

            const task = { status: currentStatus };
            const result = updateTaskStatus(task, newStatus);

            if (result.success) {
                console.log('✅ Transition successful');
                console.log(`   From: ${result.stateResult.transition.from}`);
                console.log(`   To: ${result.stateResult.transition.to}`);
                console.log(`   At: ${result.stateResult.transition.timestamp}`);
                process.exit(0);
            } else {
                console.error(`❌ Transition failed: ${result.error}`);
                process.exit(1);
            }
        } else if (command === 'stats') {
            const taskFile = args[1];
            if (!taskFile) {
                console.log('Usage: node state-machine.js stats <tasks-json-file>');
                process.exit(1);
            }

            try {
                const data = JSON.parse(fs.readFileSync(taskFile, 'utf-8'));
                const tasks = data.tasks || [];

                const stats = calculateTaskStats(tasks);

                console.log('📊 Task Statistics:');
                console.log('='.repeat(40));
                for (const [state, count] of Object.entries(stats)) {
                    if (state !== 'total' && state !== 'active' && state !== 'terminal') {
                        const description = getStateDescription(state);
                        console.log(`  ${state.padEnd(12)}: ${count.toString().padStart(3)} - ${description}`);
                    }
                }
                console.log('='.repeat(40));
                console.log(`  ${'Total'.padEnd(12)}: ${stats.total}`);
                console.log(`  ${'Active'.padEnd(12)}: ${stats.active}`);
                console.log(`  ${'Terminal'.padEnd(12)}: ${stats.terminal}`);
            } catch (error) {
                console.error(`❌ Failed to load tasks: ${error.message}`);
                process.exit(1);
            }
        } else if (command === 'schema') {
            console.log('📋 Task Schema:');
            console.log('='.repeat(40));
            const schema = getTaskSchema();
            for (const [field, type] of Object.entries(schema)) {
                console.log(`  ${field.padEnd(25)}: ${type}`);
            }
        } else {
            console.log('📋 State Machine CLI');
            console.log('='.repeat(40));
            console.log('Available commands:');
            console.log('  validate <task-json>           - Validate task status');
            console.log('  transition <from> <to>         - Test state transition');
            console.log('  stats <tasks-json-file>        - Show task statistics');
            console.log('  schema                         - Show task schema');
            console.log('');
            console.log('States:');
            for (const state of Object.values(TaskStates)) {
                console.log(`  ${state.padEnd(12)} - ${getStateDescription(state)}`);
            }
        }
    })().catch(error => {
        console.error(`❌ CLI error: ${error.message}`);
        process.exit(1);
    });
}