#!/usr/bin/env node

/**
 * Execute Task Skill (Skill 3 of 3)
 *
 * Purpose: Execute planned tasks with configurable backend
 * Input: taskId or (title, description, projectKey)
 * Backend: Configurable via --backend claude|cursor or config
 * State: planned → developing → reviewing → done/failed
 * Command: execute-task <taskId> [--backend claude|cursor]
 *
 * Handles: Full execution workflow with backend abstraction
 */

const fs = require('fs');
const path = require('path');
const tasksStore = require('./tasks-store-adapter');
const ProjectResolver = require('./project-resolver');
const { UnifiedExecutor, createLogger } = require('./unified-executor.js');

/**
 * Execute task skill - full workflow with backend abstraction
 */
async function executeTaskSkill(taskId, options = {}) {
    const {
        backend = null,
        logPath = null,
        autoReview = false
    } = options;

    console.log(`⚡ Execute Task Skill`);
    console.log('='.repeat(40));
    console.log(`   Task ID: ${taskId}`);
    console.log(`   Backend: ${backend || 'default (from config)'}`);

    try {
        // Get task
        const task = await tasksStore.getTask(taskId);
        if (!task) {
            throw new Error(`Task not found: ${taskId}`);
        }

        console.log(`   Title: ${task.title}`);
        console.log(`   Project: ${task.projectKey}`);
        console.log(`   Current status: ${task.status}`);

        // Check task state
        if (task.status !== 'planned') {
            console.log(`\n⚠️ Task is in '${task.status}' state`);
            if (task.status === 'pending') {
                console.log(`   Hint: Generate plan first: generate-plan ${taskId}`);
            } else if (task.status === 'developing') {
                console.log(`   Task is already in development`);
            } else if (task.status === 'done') {
                console.log(`   Task is already completed`);
            }
            return { success: false, error: 'Task not in planned state', task };
        }

        // Resolve project
        const resolver = new ProjectResolver();
        const project = await resolver.resolve(task.projectKey);
        if (!project || !project.path) {
            throw new Error(`Project not found or missing path: ${task.projectKey}`);
        }

        const projectPath = project.path;

        // Check plan file
        const planPath = task.planPath;
        if (!planPath || !fs.existsSync(planPath)) {
            throw new Error(`Plan file not found: ${planPath}`);
        }

        console.log(`   Plan file: ${planPath}`);
        console.log(`   Project path: ${projectPath}`);

        // Create logger
        let logger = null;
        if (logPath) {
            logger = createLogger(logPath);
        }

        // Transition to developing
        console.log(`\n🔄 Transition: planned → developing`);
        const transitionResult = await tasksStore.transitionTask(taskId, 'developing');
        if (!transitionResult.success) {
            throw new Error(transitionResult.error);
        }
        console.log(`✅ Task marked as 'developing'`);

        // Create executor
        const executor = new UnifiedExecutor({
            backend,
            logger
        });

        // Validate backend
        console.log(`\n🔍 Validating backend...`);
        const isValid = await executor.validate();
        if (!isValid) {
            throw new Error('Backend validation failed');
        }

        const backendInfo = executor.getBackendInfo();
        console.log(`✅ Backend ready: ${backendInfo.name}`);

        // Execute plan
        console.log(`\n⚡ Executing plan...`);
        const executeResult = await executor.executePlan(taskId, projectPath, {
            planPath,
            ...options
        });

        if (!executeResult.success) {
            // Mark task as failed
            console.error(`❌ Execution failed: ${executeResult.error}`);
            await tasksStore.transitionTask(taskId, 'failed', { error: executeResult.error });

            // Close logger
            if (logger) {
                await logger.close();
            }

            return {
                success: false,
                error: executeResult.error,
                task,
                executeResult
            };
        }

        // Transition to reviewing
        console.log(`\n🔄 Transition: developing → reviewing`);
        const reviewResult = await tasksStore.transitionTask(taskId, 'reviewing');
        if (!reviewResult.success) {
            console.warn(`⚠️ Failed to transition to reviewing: ${reviewResult.error}`);
        } else {
            console.log(`✅ Task marked as 'reviewing'`);
        }

        console.log(`\n✅ Task execution completed successfully`);
        console.log(`   Task ${taskId} is now in 'reviewing' state`);
        console.log(`   Please verify the implementation`);

        if (!autoReview) {
            console.log(`\n📋 Next steps:`);
            console.log(`   1. Review the implementation in ${projectPath}`);
            console.log(`   2. Test the changes`);
            console.log(`   3. Mark as done: mark-done ${taskId}`);
        } else {
            // Auto-review (optional feature)
            console.log(`\n🔄 Auto-review enabled...`);
            // TODO: Implement auto-review logic
        }

        // Close logger
        if (logger) {
            await logger.close();
        }

        // Output HANDOFF
        console.log(`\nHANDOFF:${JSON.stringify({
            ok: true,
            taskId,
            status: 'reviewing',
            task: reviewResult.success ? reviewResult.task : task,
            executeResult,
            nextSteps: [
                'Review implementation',
                'Test changes',
                `mark-done ${taskId}`
            ]
        })}`);

        return {
            success: true,
            taskId,
            status: 'reviewing',
            task: reviewResult.success ? reviewResult.task : task,
            executeResult
        };
    } catch (error) {
        console.error(`\n❌ execute-task failed: ${error.message}`);

        // Try to mark task as failed
        try {
            await tasksStore.transitionTask(taskId, 'failed', { error: error.message });
        } catch (e) {
            // Ignore marking failures
        }

        console.log(`\nHANDOFF:${JSON.stringify({
            ok: false,
            error: error.message,
            taskId
        })}`);

        return {
            success: false,
            error: error.message,
            taskId
        };
    }
}

/**
 * Mark task as done
 */
async function markTaskDone(taskId) {
    console.log(`✅ Marking task ${taskId} as done...`);

    try {
        const transitionResult = await tasksStore.transitionTask(taskId, 'done');
        if (!transitionResult.success) {
            throw new Error(transitionResult.error);
        }

        console.log(`✅ Task ${taskId} marked as done`);
        console.log(`   Status: done`);
        console.log(`   Completed at: ${transitionResult.task.completedAt}`);

        // Output HANDOFF
        console.log(`\nHANDOFF:${JSON.stringify({
            ok: true,
            taskId,
            status: 'done',
            task: transitionResult.task
        })}`);

        return {
            success: true,
            taskId,
            task: transitionResult.task
        };
    } catch (error) {
        console.error(`❌ Failed to mark task as done: ${error.message}`);

        console.log(`\nHANDOFF:${JSON.stringify({
            ok: false,
            error: error.message,
            taskId
        })}`);

        return {
            success: false,
            error: error.message,
            taskId
        };
    }
}

/**
 * Batch execute tasks
 */
async function executeTaskSkills(taskIds, options = {}) {
    const results = [];
    const failures = [];

    console.log(`⚡ Batch execution: ${taskIds.length} task(s)`);
    console.log('='.repeat(40));

    for (const taskId of taskIds) {
        try {
            const result = await executeTaskSkill(taskId, options);
            results.push({ taskId, success: result.success, result });
        } catch (error) {
            failures.push({
                taskId,
                error: error.message
            });
            results.push({ taskId, success: false, error: error.message });
        }
    }

    console.log(`\n📊 Batch execution complete:`);
    console.log(`   Total: ${taskIds.length}`);
    console.log(`   Success: ${results.filter(r => r.success).length}`);
    console.log(`   Failed: ${failures.length}`);

    if (failures.length > 0) {
        console.log(`\n❌ Failed tasks:`);
        failures.forEach(f => {
            console.log(`   - ${f.taskId}: ${f.error}`);
        });
    }

    return { results, failures };
}

// ---------- CLI Interface ----------

if (require.main === module) {
    (async () => {
        const args = process.argv.slice(2);
        const command = args[0];

        if (command === 'execute') {
            const taskId = args[1];
            const backendArg = args.find(a => a.startsWith('--backend='));
            const backend = backendArg ? backendArg.split('=')[1] : null;
            const logArg = args.find(a => a.startsWith('--log='));
            const logPath = logArg ? logArg.split('=')[1] : null;
            const autoReview = args.includes('--auto-review');

            if (!taskId) {
                console.log('Usage: node execute-task-skill.js execute <taskId> [--backend=claude|cursor] [--log=<path>] [--auto-review]');
                console.log('');
                console.log('Options:');
                console.log('  --backend     Specify backend (claude or cursor)');
                console.log('  --log         Log execution to file');
                console.log('  --auto-review  Auto-review after execution (experimental)');
                console.log('');
                console.log('Example:');
                console.log('  node execute-task-skill.js execute 123 --backend=cursor');
                process.exit(1);
            }

            try {
                await executeTaskSkill(taskId, {
                    backend,
                    logPath,
                    autoReview
                });
                process.exit(0);
            } catch (error) {
                console.error(`Error: ${error.message}`);
                process.exit(1);
            }
        } else if (command === 'mark-done') {
            const taskId = args[1];

            if (!taskId) {
                console.log('Usage: node execute-task-skill.js mark-done <taskId>');
                console.log('');
                console.log('Example:');
                console.log('  node execute-task-skill.js mark-done 123');
                process.exit(1);
            }

            try {
                await markTaskDone(taskId);
                process.exit(0);
            } catch (error) {
                console.error(`Error: ${error.message}`);
                process.exit(1);
            }
        } else if (command === 'batch') {
            const jsonFile = args[1];

            if (!jsonFile) {
                console.log('Usage: node execute-task-skill.js batch <task-ids.json>');
                console.log('');
                console.log('task-ids.json format:');
                console.log('["123", "456", "789"]');
                process.exit(1);
            }

            try {
                const taskIds = JSON.parse(fs.readFileSync(jsonFile, 'utf-8'));
                await executeTaskSkills(taskIds);
                process.exit(0);
            } catch (error) {
                console.error(`Error: ${error.message}`);
                process.exit(1);
            }
        } else {
            console.log('📋 Execute Task Skill');
            console.log('='.repeat(40));
            console.log('');
            console.log('Available commands:');
            console.log('  execute <taskId> [--backend=claude|cursor] [--log=<path>] [--auto-review]');
            console.log('      Execute a task with specified backend');
            console.log('');
            console.log('  mark-done <taskId>');
            console.log('      Mark a task as done after review');
            console.log('');
            console.log('  batch <task-ids.json>');
            console.log('      Execute multiple tasks from JSON file');
            console.log('');
            console.log('Description:');
            console.log('  Executes planned tasks with configurable backend (Claude/Cursor).');
            console.log('  Manages state transitions: planned → developing → reviewing → done.');
            console.log('  Supports backend abstraction and execution logging.');
            console.log('');
            console.log('Workflow:');
            console.log('  1. create-task → status=pending');
            console.log('  2. generate-plan → status=planned');
            console.log('  3. execute-task (this skill) → status=reviewing');
            console.log('  4. mark-done → status=done');
            console.log('');
            console.log('State Machine:');
            console.log('  pending → planned → developing → reviewing → done');
            console.log('     ↓         ↓           ↓          ↓');
            console.log('   failed   failed      failed     failed');
        }
    })();
}

module.exports = {
    executeTaskSkill,
    markTaskDone,
    executeTaskSkills
};