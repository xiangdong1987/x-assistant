#!/usr/bin/env node

/**
 * Create Task Skill (Skill 1 of 3)
 *
 * Purpose: Create development tasks with status=pending
 * Input: title, description, projectKey
 * Output: Task with status=pending
 * State: pending (no plan file yet)
 * Command: create-task-json "Title" "Description" <projectKey>
 *
 * Note: Does NOT auto-generate plans - decoupled from planning step
 */

const tasksStore = require('./tasks-store-adapter');

/**
 * Create task skill implementation
 * @param {string} title - Task title
 * @param {string} description - Task description
 * @param {string} projectKey - Project key (must exist in config)
 * @param {object} options - Additional options (priority, assignee)
 * @returns {Promise<object>} Created task object
 */
async function createTaskSkill(title, description, projectKey, options = {}) {
    if (!title) {
        throw new Error('Task title is required');
    }
    if (!projectKey) {
        throw new Error('Project key is required');
    }

    console.log(`📝 Creating task: ${title}`);
    console.log(`   Project: ${projectKey}`);
    console.log(`   Description: ${description || title}`);

    try {
        const task = await tasksStore.createTask({
            title,
            description: description || title,
            projectKey,
            priority: options.priority || 'medium',
            assignee: options.assignee || ''
        });

        console.log(`✅ Task created successfully`);
        console.log(`   Task ID: ${task.id}`);
        console.log(`   Status: ${task.status}`);
        console.log(`   Created at: ${task.createdAt}`);
        console.log(`\n📋 Next steps:`);
        console.log(`   1. Generate plan: node openclaw-integration.js generate-plan ${task.id}`);
        console.log(`   2. Execute task: node openclaw-integration.js execute-task ${task.id}`);

        // Output HANDOFF for automated processing
        console.log(`\nHANDOFF:${JSON.stringify({
            ok: true,
            taskId: task.id,
            task,
            nextSteps: [
                `generate-plan ${task.id}`,
                `execute-task ${task.id}`
            ]
        })}`);

        return task;
    } catch (error) {
        console.error(`❌ Failed to create task: ${error.message}`);

        // Output error HANDOFF
        console.log(`\nHANDOFF:${JSON.stringify({
            ok: false,
            error: error.message
        })}`);

        throw error;
    }
}

/**
 * Batch create tasks
 */
async function createTaskSkills(taskDefinitions) {
    const results = [];
    const failures = [];

    for (const def of taskDefinitions) {
        try {
            const task = await createTaskSkill(
                def.title,
                def.description,
                def.projectKey,
                def.options || {}
            );
            results.push({ success: true, task });
        } catch (error) {
            failures.push({
                title: def.title,
                error: error.message
            });
            results.push({ success: false, error: error.message });
        }
    }

    console.log(`\n📊 Batch creation complete:`);
    console.log(`   Total: ${taskDefinitions.length}`);
    console.log(`   Success: ${results.filter(r => r.success).length}`);
    console.log(`   Failed: ${failures.length}`);

    if (failures.length > 0) {
        console.log(`\n❌ Failed tasks:`);
        failures.forEach(f => {
            console.log(`   - ${f.title}: ${f.error}`);
        });
    }

    return { results, failures };
}

// ---------- CLI Interface ----------

if (require.main === module) {
    (async () => {
        const args = process.argv.slice(2);
        const command = args[0];

        if (command === 'create') {
            const title = args[1];
            const description = args[2];
            const projectKey = args[3];

            if (!title || !projectKey) {
                console.log('Usage: node create-task-skill.js create "Title" "Description" <projectKey>');
                console.log('');
                console.log('Example:');
                console.log('  node create-task-skill.js create "Add user login" "Implement OAuth2 login" my-project');
                process.exit(1);
            }

            try {
                await createTaskSkill(title, description, projectKey);
                process.exit(0);
            } catch (error) {
                console.error(`Error: ${error.message}`);
                process.exit(1);
            }
        } else if (command === 'batch') {
            const jsonFile = args[1];

            if (!jsonFile) {
                console.log('Usage: node create-task-skill.js batch <tasks.json>');
                console.log('  (建议将 JSON 放在 data/task-definitions/ 下，该目录已 .gitignore)');
                console.log('');
                console.log('tasks.json format:');
                console.log('[');
                console.log('  { "title": "Task 1", "description": "Desc 1", "projectKey": "proj1" },');
                console.log('  { "title": "Task 2", "description": "Desc 2", "projectKey": "proj2" }');
                console.log(']');
                process.exit(1);
            }

            try {
                const fs = require('fs');
                const raw = JSON.parse(fs.readFileSync(jsonFile, 'utf-8'));
                const taskDefs = Array.isArray(raw) ? raw : [raw];
                await createTaskSkills(taskDefs);
                process.exit(0);
            } catch (error) {
                console.error(`Error: ${error.message}`);
                process.exit(1);
            }
        } else {
            console.log('📋 Create Task Skill');
            console.log('='.repeat(40));
            console.log('');
            console.log('Available commands:');
            console.log('  create "Title" "Description" <projectKey>');
            console.log('      Create a single task');
            console.log('');
            console.log('  batch <tasks.json>');
            console.log('      Create multiple tasks from JSON file');
            console.log('');
            console.log('Description:');
            console.log('  Creates development tasks with status=pending.');
            console.log('  Tasks must specify a projectKey from config.json projects.');
            console.log('  Does NOT auto-generate plans - use generate-plan skill.');
            console.log('');
            console.log('Workflow:');
            console.log('  1. create-task (this skill) → status=pending');
            console.log('  2. generate-plan → status=planned');
            console.log('  3. execute-task → status=developing → reviewing → done');
        }
    })();
}

module.exports = {
    createTaskSkill,
    createTaskSkills
};