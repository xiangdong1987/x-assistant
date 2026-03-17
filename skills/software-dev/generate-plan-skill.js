#!/usr/bin/env node

/**
 * Generate Plan Skill (Skill 2 of 3)
 *
 * Purpose: Generate plan files for pending tasks
 * Input: None (processes all pending) or specific taskId
 * Output: Plan files in docs/plan-{taskId}.md
 * State: pending → planned
 * Command: generate-plan [taskId]
 *
 * Creates: Plan files with task metadata and empty execution log
 */

const fs = require('fs');
const path = require('path');
const tasksStore = require('./tasks-store-adapter');
const ProjectResolver = require('./project-resolver');

const PLAN_TEMPLATE_PATH = path.join(__dirname, 'templates', 'plan-template.md');

/**
 * Load plan template
 */
function loadTemplate() {
    if (!fs.existsSync(PLAN_TEMPLATE_PATH)) {
        throw new Error(`Plan template not found: ${PLAN_TEMPLATE_PATH}`);
    }
    return fs.readFileSync(PLAN_TEMPLATE_PATH, 'utf-8');
}

/**
 * Render plan template with task data
 */
function renderPlanTemplate(vars) {
    let tpl = loadTemplate();
    const now = new Date().toISOString();
    const defaults = {
        taskId: vars.taskId || '',
        taskTitle: vars.title || '',
        projectName: vars.projectName || '',
        projectPath: vars.projectPath || '',
        projectKey: vars.projectKey || '',
        techStack: Array.isArray(vars.techStack) ? vars.techStack.join(', ') : (vars.techStack || ''),
        techStackJson: JSON.stringify(vars.techStack || []),
        priority: vars.priority || 'medium',
        status: 'planning',
        assignee: vars.assignee || '',
        owner: vars.owner || 'xiang',
        description: vars.description || '',
        expectedOutput: vars.expectedOutput || '按计划实现并通过验收',
        generatedAt: now,
        estimatedHours: vars.estimatedHours || '',
        createdAt: now,
        updatedAt: now
    };
    const merged = { ...defaults, ...vars };
    for (const [key, value] of Object.entries(merged)) {
        const placeholder = `{{${key}}}`;
        tpl = tpl.split(placeholder).join(value != null ? String(value) : '');
    }
    return tpl;
}

/**
 * Write plan to docs directory
 */
function writePlanToDocs(projectPath, taskId, task) {
    const projectRoot = path.resolve(projectPath);
    const docsDir = path.join(projectRoot, 'docs');
    if (!fs.existsSync(docsDir)) {
        fs.mkdirSync(docsDir, { recursive: true });
    }
    const planFileName = `plan-${taskId}.md`;
    const planPath = path.join(docsDir, planFileName);
    const project = task._project || {};
    const content = renderPlanTemplate({
        taskId,
        title: task.title,
        description: task.description,
        projectKey: task.projectKey,
        projectName: project.name || task.projectKey,
        projectPath: projectPath,
        techStack: project.techStack || [],
        priority: task.priority,
        assignee: task.assignee,
        owner: project.owner || task.assignee || 'xiang'
    });
    fs.writeFileSync(planPath, content, 'utf-8');

    // Validate plan file
    const isValid = validatePlanFile(planPath);
    if (!isValid) {
        console.error(`❌ Plan file validation failed: ${planPath}`);
        throw new Error(`Plan file validation failed: file is empty or missing required frontmatter`);
    }

    return planPath;
}

/**
 * Validate plan file
 */
function validatePlanFile(planPath) {
    if (!fs.existsSync(planPath)) {
        console.error(`❌ Plan file not found: ${planPath}`);
        return false;
    }

    const stats = fs.statSync(planPath);
    if (stats.size === 0) {
        console.error(`❌ Plan file is empty: ${planPath}`);
        return false;
    }

    const content = fs.readFileSync(planPath, 'utf-8');
    if (!content.trim()) {
        console.error(`❌ Plan file content is empty: ${planPath}`);
        return false;
    }

    // Check for required frontmatter fields
    const meta = parsePlanMeta(planPath);
    if (!meta) {
        console.error(`❌ Plan file missing frontmatter: ${planPath}`);
        return false;
    }

    const requiredFields = ['taskId', 'title', 'status'];
    for (const field of requiredFields) {
        if (!meta[field]) {
            console.error(`❌ Plan file missing required field "${field}": ${planPath}`);
            return false;
        }
    }

    console.log(`✅ Plan file validation passed: ${planPath}`);
    return true;
}

/**
 * Parse plan metadata from end of file
 */
function parsePlanMeta(planPath) {
    if (!fs.existsSync(planPath)) return null;
    const content = fs.readFileSync(planPath, 'utf-8');
    const metaStart = content.lastIndexOf('\n---\n');
    if (metaStart === -1) return null;
    const block = content.slice(metaStart + 5).trim();
    const lines = block.split('\n');
    const meta = {};
    for (const line of lines) {
        const m = line.match(/^\s*(\w+):\s*(.*)$/);
        if (m) meta[m[1].trim()] = m[2].trim();
    }
    return meta;
}

/**
 * Generate plan skill - processes all pending tasks or specific taskId
 */
async function generatePlanSkill(taskId = null) {
    const resolver = new ProjectResolver();

    try {
        // Get tasks to process
        let tasks;
        if (taskId) {
            const task = await tasksStore.getTask(taskId);
            if (!task) {
                throw new Error(`Task not found: ${taskId}`);
            }

            // 支持 pending 和 failed：failed 任务可重试生成计划
            if (task.status !== 'pending' && task.status !== 'failed') {
                console.log(`⚠️ Task ${taskId} is in '${task.status}' state, need 'pending' or 'failed' for plan generation`);
                return { success: true, message: 'Task not in pending/failed state', task };
            }
            if (task.status === 'failed') {
                console.log(`📋 Retrying plan generation for failed task ${taskId}...`);
            }

            tasks = [task];
        } else {
            const pending = await tasksStore.listByStatus('pending');
            const failed = await tasksStore.listByStatus('failed');
            tasks = [...pending, ...failed];
        }

        if (tasks.length === 0) {
            console.log('📋 No pending or failed tasks to process');
            console.log(`\nHANDOFF:${JSON.stringify({ ok: true, message: 'No pending tasks', results: [] })}`);
            return { success: true, results: [] };
        }

        console.log(`📋 Processing ${tasks.length} pending task(s)...`);

        const results = [];
        let successCount = 0;
        let failCount = 0;

        for (const task of tasks) {
            let projectPath;
            try {
                const project = await resolver.resolve(task.projectKey);
                projectPath = project.path;
                task._project = project;

                if (!projectPath) {
                    console.warn(`⚠️ Skipping task ${task.id}: Project ${task.projectKey} not configured with path`);
                    failCount++;
                    continue;
                }
            } catch (e) {
                console.warn(`⚠️ Skipping task ${task.id}: Cannot resolve project ${task.projectKey} - ${e.message}`);
                failCount++;
                continue;
            }

            const taskId = await tasksStore.generateTaskId(task.id);
            try {
                const planPath = writePlanToDocs(projectPath, taskId, task);
                await tasksStore.assignTaskId(task.id, taskId, planPath);
                console.log(`✅ ${taskId} Plan created (${path.resolve(projectPath)}) → ${planPath} → status=planned`);
                results.push({ taskId, planPath, task, ok: true });
                successCount++;
            } catch (error) {
                console.error(`❌ Failed to generate plan for task ${task.id}: ${error.message}`);

                // Mark task as failed
                await tasksStore.updateTask(task.id, {
                    status: 'failed',
                    error: error.message,
                    updatedAt: new Date().toISOString()
                });

                results.push({ taskId: task.id, task, ok: false, error: error.message });
                failCount++;
            }
        }

        const summary = {
            total: tasks.length,
            success: successCount,
            failed: failCount,
            results
        };

        console.log(`\n📊 Processing complete:`);
        console.log(`   Total: ${tasks.length}`);
        console.log(`   Success: ${successCount}`);
        console.log(`   Failed: ${failCount}`);

        console.log(`\nHANDOFF:${JSON.stringify({ ok: true, summary })}`);
        return { success: true, summary, results };
    } catch (error) {
        console.error(`❌ generate-plan failed: ${error.message}`);
        console.log(`\nHANDOFF:${JSON.stringify({ ok: false, error: error.message })}`);
        throw error;
    }
}

// ---------- CLI Interface ----------

if (require.main === module) {
    (async () => {
        const args = process.argv.slice(2);
        const taskId = args[0] || null;

        console.log('📋 Generate Plan Skill');
        console.log('='.repeat(40));

        try {
            await generatePlanSkill(taskId);
            process.exit(0);
        } catch (error) {
            console.error(`Error: ${error.message}`);
            process.exit(1);
        }
    })();
}

module.exports = {
    generatePlanSkill,
    writePlanToDocs,
    parsePlanMeta,
    validatePlanFile,
    renderPlanTemplate
};