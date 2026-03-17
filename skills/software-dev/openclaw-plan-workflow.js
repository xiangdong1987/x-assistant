#!/usr/bin/env node

/**
 * OpenClaw 以 Plan 为核心的工作流技能（JSON 存储，无 Lark）
 *
 * 技能1: 创建任务（status=pending，含 projectKey）
 * 技能2: 监控 pending → 创建 taskId、在项目 docs/ 下生成 plan.md → status=planned
 * 技能3: 监控 planned → 检测 plan 中 meta.status 为 done/implemented/verified → status=done
 */

const fs = require('fs');
const path = require('path');

const tasksStore = require('./tasks-store-adapter');
const ProjectResolver = require('./project-resolver');

const PLAN_TEMPLATE_PATH = path.join(__dirname, 'templates', 'plan-template.md');

function loadTemplate() {
  if (!fs.existsSync(PLAN_TEMPLATE_PATH)) {
    throw new Error(`计划模板不存在: ${PLAN_TEMPLATE_PATH}`);
  }
  return fs.readFileSync(PLAN_TEMPLATE_PATH, 'utf-8');
}

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
 * 在项目 docs 目录下写入 plan-{taskId}.md（projectPath 必须为项目根目录的绝对路径）
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

  // 校验 plan 文件
  const isValid = validatePlanFile(planPath);
  if (!isValid) {
    console.error(`❌ Plan 文件校验失败: ${planPath}`);
    throw new Error(`Plan 文件校验失败: 文件为空或缺少必要 frontmatter`);
  }

  return planPath;
}

/**
 * 从 plan 文件末尾解析 meta 块（YAML 风格）
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
 * 校验 plan 文件是否有效
 * 1. 文件非空
 * 2. 包含必要的 frontmatter (taskId, title, status)
 */
function validatePlanFile(planPath) {
  if (!fs.existsSync(planPath)) {
    console.error(`❌ Plan 文件不存在: ${planPath}`);
    return false;
  }

  const stats = fs.statSync(planPath);
  if (stats.size === 0) {
    console.error(`❌ Plan 文件为空: ${planPath}`);
    return false;
  }

  const content = fs.readFileSync(planPath, 'utf-8');
  if (!content.trim()) {
    console.error(`❌ Plan 文件内容为空: ${planPath}`);
    return false;
  }

  // 检查是否包含必要的 frontmatter
  const meta = parsePlanMeta(planPath);
  if (!meta) {
    console.error(`❌ Plan 文件缺少 frontmatter: ${planPath}`);
    return false;
  }

  // 检查必要的字段
  const requiredFields = ['taskId', 'title', 'status'];
  for (const field of requiredFields) {
    if (!meta[field]) {
      console.error(`❌ Plan 文件缺少必要字段 "${field}": ${planPath}`);
      return false;
    }
  }

  console.log(`✅ Plan 文件校验通过: ${planPath}`);
  return true;
}

/**
 * 更新 plan 文件末尾 meta 中的 status，实现任务状态 → plan 联动
 */
function updatePlanMetaStatus(planPath, newStatus) {
  if (!planPath || !fs.existsSync(planPath)) return false;
  let content = fs.readFileSync(planPath, 'utf-8');
  const metaStart = content.lastIndexOf('\n---\n');
  if (metaStart === -1) return false;
  const beforeMeta = content.slice(0, metaStart + 5);
  const metaBlock = content.slice(metaStart + 5);
  const statusLineRegex = /^(\s*status:\s*).*$/m;
  let newMetaBlock;
  if (statusLineRegex.test(metaBlock)) {
    newMetaBlock = metaBlock.replace(statusLineRegex, `$1${newStatus}`);
  } else {
    newMetaBlock = metaBlock.trimEnd() + (metaBlock.endsWith('\n') ? '' : '\n') + `  status: ${newStatus}\n`;
  }
  fs.writeFileSync(planPath, beforeMeta + newMetaBlock, 'utf-8');
  return true;
}

/**
 * 技能1：创建任务（pending，必须包含 projectKey）
 * 联动：创建后自动为该任务（及所有 pending）生成 plan，即自动执行 process-pending
 */
async function createTaskSkill(title, description, projectKey, options = {}) {
  try {
    const task = await tasksStore.createTask({
      title,
      description: description || title,
      projectKey,
      priority: options.priority || 'medium',
      assignee: options.assignee || ''
    });
    console.log(`✅ 任务已创建: id=${task.id} projectKey=${projectKey} status=pending`);

    const linkPlan = options.linkPlan !== false;
    if (linkPlan) {
      const results = await processPendingSkill();
      const created = results.find(r => String(r.task.id) === String(task.id));
      if (created) {
        console.log(`✅ 已联动生成 plan: ${created.planPath} → status=planned`);
      }
    }

    const finalTask = (await tasksStore.getTask(task.id)) || task;
    // 输出标准化 HANDOFF
    console.log(`\nHANDOFF:${JSON.stringify({ ok: true, taskId: finalTask.id, task: finalTask })}`);
    return finalTask;
  } catch (error) {
    console.error(`❌ 创建任务失败: ${error.message}`);
    // 输出标准化 HANDOFF
    console.log(`\nHANDOFF:${JSON.stringify({ ok: false, error: error.message })}`);
    throw error;
  }
}

/**
 * 处理指定任务列表，生成 plan 文件
 * 支持 pending 和 failed 任务（failed 可重试）
 */
async function processTasksForPlan(tasks) {
  if (!tasks || tasks.length === 0) return [];
  const resolver = new ProjectResolver();
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
        console.warn(`⚠️ 跳过任务 ${task.id}: 项目 ${task.projectKey} 未配置 path`);
        failCount++;
        continue;
      }
    } catch (e) {
      console.warn(`⚠️ 跳过任务 ${task.id}: 无法解析项目 ${task.projectKey} - ${e.message}`);
      failCount++;
      continue;
    }
    const genTaskId = tasksStore.generateTaskId(task.id);
    try {
      const planPath = writePlanToDocs(projectPath, genTaskId, task);
      await tasksStore.assignTaskId(task.id, genTaskId, planPath);

      // Initialize the phase to 'plan' when the plan is created
      await tasksStore.updateTask(task.id, {
        phase: 'plan',
        updatedAt: new Date().toISOString()
      });

      console.log(`✅ ${genTaskId} 计划已创建（项目目录: ${path.resolve(projectPath)}）→ ${planPath} → status=planned`);
      results.push({ taskId: genTaskId, planPath, task, ok: true });
      successCount++;
    } catch (error) {
      console.error(`❌ 为任务 ${task.id} 生成 plan 失败: ${error.message}`);
      await tasksStore.updateTask(task.id, {
        status: 'failed',
        error: error.message,
        updatedAt: new Date().toISOString()
      });
      results.push({ taskId: task.id, task, ok: false, error: error.message });
      failCount++;
    }
  }

  return results;
}

/**
 * 技能2：处理所有 pending 和 failed 任务 → 生成 taskId、在项目 docs/ 下创建 plan-{taskId}.md，状态改为 planned
 */
async function processPendingSkill() {
  try {
    const pending = await tasksStore.listByStatus('pending');
    const failed = await tasksStore.listByStatus('failed');
    const tasks = [...pending, ...failed];
    if (tasks.length === 0) {
      console.log('📋 无 pending 或 failed 任务');
      console.log(`\nHANDOFF:${JSON.stringify({ ok: true, message: '无 pending 或 failed 任务', results: [] })}`);
      return [];
    }
    if (failed.length > 0) {
      console.log(`📋 含 ${failed.length} 个 failed 任务将重试`);
    }

    const results = await processTasksForPlan(tasks);
    const successCount = results.filter(r => r.ok).length;
    const failCount = results.filter(r => !r.ok).length;

    const summary = {
      total: tasks.length,
      success: successCount,
      failed: failCount,
      results: results
    };

    console.log(`\n📊 处理完成: 总计 ${tasks.length} 个任务，成功 ${successCount} 个，失败 ${failCount} 个`);
    console.log(`\nHANDOFF:${JSON.stringify({ ok: true, summary })}`);
    return results;
  } catch (error) {
    console.error(`❌ process-pending 失败: ${error.message}`);
    console.log(`\nHANDOFF:${JSON.stringify({ ok: false, error: error.message })}`);
    throw error;
  }
}

/** plan 中视为“完成”的 meta.status 值 */
const DONE_STATUSES = ['done', 'implemented', 'verified', 'completed'];

/**
 * 技能3：监控 planned 任务，若 plan 中 meta.status 为完成态则更新任务为 done
 */
async function processPlannedSkill() {
  const planned = await tasksStore.listByStatus('planned');
  if (planned.length === 0) {
    console.log('📋 无 planned 任务');
    return [];
  }
  const results = [];
  for (const task of planned) {
    const planPath = task.planPath;
    if (!planPath || !fs.existsSync(planPath)) {
      console.warn(`⚠️ 任务 ${task.taskId || task.id}: plan 文件不存在 ${planPath}`);
      continue;
    }
    const meta = parsePlanMeta(planPath);
    if (!meta || !meta.status) continue;
    const status = (meta.status || '').toLowerCase().trim();
    if (!DONE_STATUSES.includes(status)) continue;
    await tasksStore.updateTask(task.id, { status: 'done' });
    console.log(`✅ ${task.taskId} 已标记完成（plan meta.status=${meta.status}）`);
    results.push({ task, meta });
  }
  return results;
}

// CLI
if (require.main === module) {
  (async () => {
    const args = process.argv.slice(2);
    const cmd = args[0];

    try {
      if (cmd === 'create-task') {
        const title = args[1];
        const description = args[2];
        const projectKey = args[3];
        if (!title || !projectKey) {
          console.log('用法: node openclaw-plan-workflow.js create-task "标题" "描述" <projectKey>');
          process.exit(1);
        }
        await createTaskSkill(title, description || title, projectKey);
      } else if (cmd === 'process-pending') {
        await processPendingSkill();
      } else if (cmd === 'process-planned') {
        await processPlannedSkill();
      } else if (cmd === 'list') {
        const status = args[1] || null;
        const list = await tasksStore.listByStatus(status);
        console.log('任务列表:', status ? `status=${status}` : '全部');
        console.log(JSON.stringify(list, null, 2));
      } else {
        console.log('用法:');
        console.log('  create-task "标题" "描述" <projectKey>  创建 pending 任务');
        console.log('  process-pending                         处理 pending → planned（写 docs/plan-*.md）');
        console.log('  process-planned                          处理 planned → done（读 plan meta）');
        console.log('  list [pending|planned|done]              列出任务');
      }
    } catch (e) {
      console.error(e.message || e);
      process.exit(1);
    }
  })();
}

module.exports = {
  createTaskSkill,
  processTasksForPlan,
  processPendingSkill,
  processPlannedSkill,
  writePlanToDocs,
  parsePlanMeta,
  updatePlanMetaStatus,
  renderPlanTemplate
};
