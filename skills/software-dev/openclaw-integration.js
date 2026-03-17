#!/usr/bin/env node

/**
 * OpenClaw集成脚本
 * 为OpenClaw agent提供简单的接口来调用重构后的软件开发代理系统
 */

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const { loadConfig } = require('./config-loader');

// 简单版 Execution Log 更新工具：用于在 Code 阶段完成后更新 plan 列表
const PLAN_PHASE_MARKERS = {
  plan: '### Plan 阶段',
  code: '### Code 阶段',
  test: '### Test 阶段',
  done: '### Done 阶段'
};

function markPlanPhaseComplete(planPath, phase, message) {
  if (!planPath || !fs.existsSync(planPath)) return;
  const marker = PLAN_PHASE_MARKERS[phase];
  if (!marker) return;
  let content = fs.readFileSync(planPath, 'utf-8');
  const idx = content.indexOf(marker);
  if (idx === -1) return;
  const afterSection = content.indexOf('\n', idx) + 1;
  // 找到本阶段结束位置（下一个 ## / ### 或 ---）
  const nextSection = content.slice(afterSection).search(/\n(#{2,3}\s|---)/);
  const sectionEnd = nextSection === -1 ? content.length : afterSection + nextSection;
  // 勾选本阶段 checklist
  const section = content.slice(afterSection, sectionEnd);
  const replaced = section.replace(/^(\s*)- \[ \]/gm, '$1- [x]');
  if (replaced !== section) {
    content = content.slice(0, afterSection) + replaced + content.slice(sectionEnd);
  }
  // 追加一条完成记录
  const line = `- [x] ${new Date().toISOString()}: ${message || `${phase} 阶段完成`}`;
  content = content.slice(0, afterSection) + line + '\n' + content.slice(afterSection);
  fs.writeFileSync(planPath, content, 'utf-8');
}

class OpenClawIntegration {
  constructor() {
    this._logSection('OpenClaw 集成接口');

    this.projectRoot = __dirname;
    this.config = loadConfig();
  }

  _logSection(title) {
    console.log(`\n[openclaw] ${title}`);
    console.log('[openclaw] ' + '='.repeat(50));
  }

  _logInfo(message) {
    console.log(`[openclaw] ${message}`);
  }

  _logSuccess(message) {
    console.log(`[openclaw][OK] ${message}`);
  }

  _logWarn(message) {
    console.warn(`[openclaw][WARN] ${message}`);
  }

  _logError(message) {
    console.error(`[openclaw][ERROR] ${message}`);
  }

  _parseArg(args, flag) {
    const i = args.indexOf(flag);
    if (i === -1 || i + 1 >= args.length) return undefined;
    return args[i + 1];
  }

  /** config.projects.registry 中第一个项目 key，用于无 projectKey 任务生成计划时的默认项目 */
  _getDefaultProjectKey() {
    const registry = this.config?.projects?.registry;
    if (!registry || typeof registry !== 'object') return null;
    const key = Object.keys(registry)[0];
    return key || null;
  }

  /**
   * 从子进程输出中解析 HANDOFF 数据
   */
  _parseHandoffFromOutput(output) {
    if (!output) return null;

    // 查找 HANDOFF: 前缀
    const lines = output.split('\n');
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i].trim();
      if (line.startsWith('HANDOFF:')) {
        try {
          const jsonStr = line.substring(8); // 去掉 "HANDOFF:"
          return JSON.parse(jsonStr);
        } catch (error) {
          this._logError(`解析 HANDOFF 失败: ${error.message}`);
          return null;
        }
      }
    }
    return null;
  }

  /**
   * 显示可用命令
   */
  showHelp() {
    console.log('\n📋 可用命令:');
    console.log('='.repeat(40));
    console.log('  start-server         - 启动 Dashboard 服务');
    console.log('  stop-server          - 停止 Dashboard 服务');
    console.log('  health-check         - 检查系统健康状态');
    console.log('');
    console.log('  --- 新版 3 核心技能（推荐入口） ---');
    console.log('  create-task-json     - 创建任务 (create-task-json "标题" "描述" <projectKey>)');
    console.log('  generate-plan        - 生成计划 (generate-plan [taskId] [--agent] 默认模板，--agent 走 LLM 生成)');
    console.log('  execute-task         - 执行任务 (execute-task <taskId> [--backend claude|cursor] [--log [path]])');
    console.log('  list-tasks-json      - 列出任务 (list-tasks-json [pending|planned|developing|reviewing|done|failed])');
    console.log('');
    console.log('  --- 阶段流水线 ---');
    console.log('  phase-pipeline       - 运行阶段流水线 (phase-pipeline <taskId> [--dry-run] [--skip-commit])');
    console.log('  auto-execute         - 一键执行：无计划则先生成计划，再执行代码+测试+提交 (auto-execute <taskId> [--backend=xxx])');
    console.log('  run-phase            - 仅执行指定阶段，供定时触发 (run-phase <taskId> <plan|code|test|done> [--backend=xxx])');
    console.log('  phase-content        - 获取阶段内容 (phase-content <planPath> [phase])');
    console.log('  phase-advance        - 推进阶段 (phase-advance <taskId> [currentPhase])');
    console.log('');
    console.log('  --- 旧版 JSON 流程命令（兼容用，不推荐新用户） ---');
    console.log('  process-pending      - 旧版：处理 pending 任务生成计划，等价于 generate-plan');
    console.log('  process-planned      - 旧版：处理 planned 任务提交 / 标记完成');
    console.log('  list-tasks           - 旧版：通过 HTTP API 列出任务');
    console.log('  confirm-plan         - 旧版：确认计划（JSON 流程已不再需要）');
    console.log('  confirm-done         - 旧版：确认完成（JSON 流程已不再需要）');
    console.log('  submit-task          - 旧版：提交任务（请直接在本地 git 提交）');
    console.log('');
    console.log('  --- 兼容工作流 ---');
    console.log('  run-workflow         - 运行工作流 (run-workflow auto-dev "标题" "描述" <projectKey>)，已迁移为基于 create-task-json / generate-plan / execute-task 的封装，仅作兼容保留');
    console.log('');
    console.log('  help                 - 显示此帮助信息');
  }

  /**
   * 启动任务系统服务器
   */
  startServer() {
    this._logInfo('🚀 启动任务系统服务器...');

    const serverProcess = spawn('node', ['server-dashboard-only.js'], {
      cwd: this.projectRoot,
      stdio: 'pipe',
      detached: true
    });

    serverProcess.stdout.on('data', (data) => {
      this._logInfo(`[服务器] ${data.toString().trim()}`);
    });

    serverProcess.stderr.on('data', (data) => {
      this._logError(`服务器错误: ${data.toString().trim()}`);
    });

    serverProcess.on('close', (code) => {
      this._logInfo(`服务器进程退出，代码: ${code}`);
    });

    // 保存进程ID以便后续管理
    const pidFile = path.join(this.projectRoot, 'server.pid');
    fs.writeFileSync(pidFile, serverProcess.pid.toString());

    this._logSuccess(`服务器已启动 (PID: ${serverProcess.pid})`);
    this._logInfo('📊 Dashboard: http://localhost:3001/dashboard');
    this._logInfo('📡 API: http://localhost:3001/api/tasks');

    return serverProcess;
  }

  /**
   * 停止任务系统服务器
   */
  stopServer() {
    this._logInfo('🛑 停止任务系统服务器...');

    const pidFile = path.join(this.projectRoot, 'server.pid');
    if (fs.existsSync(pidFile)) {
      const pid = parseInt(fs.readFileSync(pidFile, 'utf-8'));

      try {
        process.kill(pid);
        this._logSuccess(`已停止服务器进程 (PID: ${pid})`);
        fs.unlinkSync(pidFile);
      } catch (error) {
        this._logWarn(`无法停止进程 ${pid}: ${error.message}`);
      }
    } else {
      this._logWarn('未找到服务器进程ID文件');
    }
  }

  /**
   * 运行完整开发流程（已改为 JSON 技能分步执行）
   */
  async runWorkflow(workflowName, ...args) {
    if (workflowName === 'auto-dev') {
      if (args.length < 3) {
        this._logError('用法: run-workflow auto-dev "标题" "描述" <projectKey>');
        return;
      }

      const title = args[0];
      const description = args[1];
      const projectKey = args[2];

      this._logSection('🚀 启动 auto-dev 全流程');
      this._logInfo(`📝 标题: ${title}`);
      this._logInfo(`📋 描述: ${description}`);
      this._logInfo(`📁 项目: ${projectKey}`);

      try {
        // 步骤1: 创建任务
        this._logInfo('📝 步骤1: 创建任务...');
        const taskResult = await this.createTaskJson(title, description, projectKey);
        if (!taskResult || taskResult.ok === false) {
          throw new Error('创建任务失败');
        }
        this._logSuccess('步骤1完成: 任务创建成功');

        // 步骤2: 生成计划
        this._logInfo('📋 步骤2: 生成计划...');
        const pendingResult = await this.processPending();
        if (!pendingResult || pendingResult.ok === false) {
          throw new Error('生成计划失败');
        }
        this._logSuccess('步骤2完成: 计划生成成功');

        // 步骤3: 执行开发
        this._logInfo('⚡ 步骤3: 执行开发...');
        const taskId = taskResult.task?.taskId || taskResult.task?.id;
        if (!taskId) {
          throw new Error('无法获取任务ID，执行中止');
        }
        const executeResult = await this.executeTask(taskId);
        if (!executeResult || executeResult.ok === false) {
          throw new Error('执行开发失败');
        }
        this._logSuccess('步骤3完成: 开发执行成功');

        this._logSuccess('auto-dev 全流程完成！');
        return { ok: true, message: 'auto-dev 全流程完成' };
      } catch (error) {
        this._logError(`auto-dev 流程失败: ${error.message}`);
        this._logWarn('流程已停止');
        return { ok: false, error: error.message };
      }
    } else {
      this._logInfo('📋 可用工作流:');
      this._logInfo('  auto-dev - 全流程自动开发');
      this._logError(`未知工作流: ${workflowName}`);
    }
  }

  /**
   * 创建新任务
   */
  async createTask(title, description, priority = 'medium') {
    this._logInfo(`📝 创建任务: ${title}`);

    const taskData = {
      title,
      description,
      priority,
      status: 'todo',
      createdAt: new Date().toISOString()
    };

    // 这里应该调用API，但为了简单起见，我们直接运行脚本
    const createScript = `
      const axios = require('axios');
      const taskData = ${JSON.stringify(taskData, null, 2)};
      
      axios.post('http://localhost:3001/api/tasks', taskData)
        .then(response => {
          console.log('✅ 任务创建成功:', response.data);
        })
        .catch(error => {
          console.error('❌ 任务创建失败:', error.message);
        });
    `;

    const scriptPath = path.join(this.projectRoot, 'temp-create-task.js');
    fs.writeFileSync(scriptPath, createScript);

    const result = spawn('node', [scriptPath], {
      cwd: this.projectRoot,
      stdio: 'inherit'
    });

    result.on('close', () => {
      fs.unlinkSync(scriptPath);
    });
  }

  /**
   * 列出所有任务
   */
  async listTasks() {
    this._logInfo('📋 列出所有任务...');

    const listScript = `
      const axios = require('axios');
      
      axios.get('http://localhost:3001/api/tasks')
        .then(response => {
          const tasks = response.data;
          console.log('📊 任务列表:');
          console.log('='.repeat(40));
          
          if (tasks.length === 0) {
            console.log('暂无任务');
          } else {
            tasks.forEach((task, index) => {
              console.log(\`\${index + 1}. \${task.title}\`);
              console.log(\`   状态: \${task.status}\`);
              console.log(\`   优先级: \${task.priority || '中'}\`);
              console.log(\`   创建时间: \${task.createdAt}\`);
              console.log('');
            });
          }
        })
        .catch(error => {
          console.error('❌ 获取任务列表失败:', error.message);
        });
    `;

    const scriptPath = path.join(this.projectRoot, 'temp-list-tasks.js');
    fs.writeFileSync(scriptPath, listScript);

    return new Promise((resolve) => {
      const result = spawn('node', [scriptPath], {
        cwd: this.projectRoot,
        stdio: 'inherit'
      });

      result.on('close', () => {
        fs.unlinkSync(scriptPath);
        resolve();
      });
    });
  }

  /**
   * 已移除：JSON 流程使用 process-pending / process-planned
   */
  confirmPlan(taskId) {
    this._logInfo('📋 JSON 流程无需此命令，请使用 process-pending / process-planned');
  }

  confirmDone(taskId) {
    this._logInfo('📋 JSON 流程无需此命令，请使用 process-planned 检测 plan 完成');
  }

  submitTask(taskId) {
    this._logInfo('📋 JSON 流程无自动提交，请在本地执行 git commit / push');
  }

  _parseLogPath(args, taskId) {
    const idx = args.indexOf('--log');
    if (idx === -1) return null;
    const next = args[idx + 1];
    const pathModule = require('path');
    if (next && !next.startsWith('-')) {
      const p = pathModule.resolve(process.cwd(), next);
      const fs = require('fs');
      if (fs.existsSync(p) && fs.statSync(p).isDirectory()) {
        const { resolveLogPath } = require('./execution-log-utils.js');
        return resolveLogPath(p, taskId);
      }
      return p;
    }
    const { getExecutionLogDir, resolveLogPath } = require('./execution-log-utils.js');
    const logsDir = getExecutionLogDir(__dirname);
    return resolveLogPath(logsDir, taskId);
  }

  /**
   * JSON 任务流：创建任务并默认联动生成 plan（含 planPath）
   * options.linkPlan !== false 时自动执行 generate-plan
   */
  async createTaskJson(title, description, projectKey, options = {}) {
    const tasksStore = require('./tasks-store-adapter');
    const { processTasksForPlan } = require('./openclaw-plan-workflow');
    try {
      const task = await tasksStore.createTask({
        title,
        description,
        projectKey,
        priority: options.priority || 'medium',
        assignee: options.assignee || ''
      });
      this._logSuccess(`任务已创建: id=${task.id} projectKey=${projectKey} status=pending`);

      const linkPlan = options.linkPlan !== false;
      if (linkPlan) {
        const results = await processTasksForPlan([task]);
        const created = results.find(r => r.ok && String(r.task.id) === String(task.id));
        if (created) {
          this._logSuccess(`已联动生成 plan: ${created.planPath} → status=planned`);
          const finalTask = await tasksStore.getTask(task.id);
          this._logInfo(`HANDOFF:${JSON.stringify({ ok: true, taskId: finalTask?.taskId || task.id, task: finalTask || task })}`);
          return { ok: true, task: finalTask || task };
        }
      }
      this._logInfo(`提示: 使用 'generate-plan' 命令生成计划文件`);
      this._logInfo(`HANDOFF:${JSON.stringify({ ok: true, taskId: task.id, task })}`);
      return { ok: true, task };
    } catch (error) {
      this._logError(`创建任务失败: ${error.message}`);
      this._logInfo(`HANDOFF:${JSON.stringify({ ok: false, error: error.message })}`);
      return { ok: false, error: error.message };
    }
  }

  /**
   * 新版：生成计划（为 pending 任务生成 plan 文件）
   * options.useAgent === true 时走 LLM/Agent（cursor 或 ccr）生成计划；否则用模板填充
   */
  async generatePlanTask(taskId = null, options = {}) {
    const tasksStore = require('./tasks-store-adapter');
    const { processTasksForPlan, processPendingSkill } = require('./openclaw-plan-workflow');
    const { createBackend } = require('./unified-executor');
    const path = require('path');
    const ProjectResolver = require('./project-resolver');

    try {
      if (taskId) {
        this._logInfo(`📋 正在获取任务 ${taskId}...`);
        const task = await tasksStore.getTask(taskId);
        if (!task) {
          throw new Error(`Task not found: ${taskId}`);
        }
        this._logInfo(`📋 任务已获取 projectKey=${task.projectKey || '(空)'} status=${task.status} useAgent=${options.useAgent}`);

        // 允许 planning：proxy 触发生成计划时已先将状态置为 planning，此处需放行
        const allowedForPlan = ['pending', 'confirmed', 'failed', 'planning'];
        if (!allowedForPlan.includes(task.status)) {
          this._logWarn(`任务 ${taskId} 当前状态为 ${task.status}，需要 pending/confirmed/failed/planning 才能生成计划`);
          return { ok: true, message: 'Task not in allowed state for plan generation', task };
        }
        if (task.status === 'failed') {
          this._logInfo(`📋 为重试失败任务 ${taskId} 生成计划...`);
        }

        if (!task.projectKey || String(task.projectKey).trim() === '') {
          const defaultKey = this._getDefaultProjectKey();
          if (!defaultKey) {
            console.error('❌ 任务缺少 projectKey 且 config.projects.registry 未配置默认项目');
            throw new Error('Task has no projectKey and no default project in config');
          }
          this._logInfo(`📋 任务无 projectKey，使用默认项目: ${defaultKey}`);
          await tasksStore.updateTask(task.id, { projectKey: defaultKey });
          task.projectKey = defaultKey;
        }

        if (options.useAgent) {
          // 走 Agent（cursor/ccr）生成计划
          this._logInfo(`📋 正在解析项目路径 projectKey=${task.projectKey}...`);
          const resolver = new ProjectResolver();
          const project = await resolver.resolve(task.projectKey);
          if (!project || !project.path) {
            throw new Error(`项目 ${task.projectKey} 未配置 path`);
          }
          const projectPath = project.path;
          const genTaskId = task.taskId || tasksStore.generateTaskId(task.id);
          const backendName = task.backend === 'cursor' ? 'cursor' : (task.backend === 'ccr' ? 'ccr' : (task.backend === 'claude' ? 'claude' : 'ccr'));

          // Cursor 生成计划：统一使用 stream-progress-plan.sh 流式生成（与 stream-progress.sh 执行计划同风格）
          if (backendName === 'cursor') {
            this._logInfo('📋 使用 stream-progress-plan.sh 流式生成计划...');
            const { execSync } = require('child_process');
            const streamPlanScript = path.join(__dirname, 'stream-progress-plan.sh');
            const planPath = path.join(projectPath, 'docs', `plan-${genTaskId}.md`);
            const runEnv = {
              ...process.env,
              TASK_API_URL: process.env.TASK_API_URL || 'http://127.0.0.1:8443',
              TASK_API_TOKEN: process.env.TASK_API_TOKEN || 'internal-execute-token',
              TASK_PLAN_TITLE: (task.title || '').toString(),
              TASK_PLAN_DESC: (task.description || task.title || '').toString(),
              TASK_PLAN_TEMPLATE_PATH: path.join(__dirname, 'templates', 'plan-template.md')
            };
            execSync(`bash "${streamPlanScript}" "${task.id}" "${genTaskId}" "${projectPath}"`, {
              stdio: 'inherit',
              encoding: 'utf-8',
              shell: true,
              env: runEnv
            });
            // 同步任务状态到 Proxy（脚本已把 status 置为 planned，此处补全 taskId/planPath/phase）；网络不稳定时重试
            const syncWithRetry = async (fn, retries = 3) => {
              for (let i = 0; i <= retries; i++) {
                try {
                  await fn();
                  return;
                } catch (e) {
                  const isNetwork = /ECONNRESET|ETIMEDOUT|ECONNREFUSED|socket hang up/i.test(e.message || '');
                  if (isNetwork && i < retries) {
                    this._logWarn(`同步任务状态失败 (${e.message})，${1 + i}s 后重试...`);
                    await new Promise((r) => setTimeout(r, (1 + i) * 1000));
                  } else {
                    throw e;
                  }
                }
              }
            };
            try {
              await syncWithRetry(() => tasksStore.assignTaskId(task.id, genTaskId, planPath));
              await syncWithRetry(() => tasksStore.updateTask(task.id, {
                phase: 'code',
                updatedAt: new Date().toISOString()
              }));
              this._logSuccess(`计划生成成功（stream-progress-plan）: ${planPath} → phase=code`);
            } catch (syncErr) {
              this._logWarn(`计划已写入 ${planPath}，但同步任务状态到 Proxy 失败: ${syncErr.message}`);
              this._logWarn('请确认 Proxy 运行正常并在应用中刷新任务列表。');
            }
            return { ok: true, result: { planPath, taskId: genTaskId, task }, task };
          }

          // Claude 生成计划：使用 stream-progress-plan-claude.sh 流式生成（与 cursor 同风格）
          if (backendName === 'claude') {
            this._logInfo('📋 使用 stream-progress-plan-claude.sh 流式生成计划...');
            const { execSync } = require('child_process');
            const streamPlanScript = path.join(__dirname, 'stream-progress-plan-claude.sh');
            const planPath = path.join(projectPath, 'docs', `plan-${genTaskId}.md`);
            const runEnv = {
              ...process.env,
              TASK_API_URL: process.env.TASK_API_URL || 'http://127.0.0.1:8443',
              TASK_API_TOKEN: process.env.TASK_API_TOKEN || 'internal-execute-token',
              TASK_PLAN_TITLE: (task.title || '').toString(),
              TASK_PLAN_DESC: (task.description || task.title || '').toString(),
              TASK_PLAN_TEMPLATE_PATH: path.join(__dirname, 'templates', 'plan-template.md')
            };
            execSync(`bash "${streamPlanScript}" "${task.id}" "${genTaskId}" "${projectPath}"`, {
              stdio: 'inherit',
              encoding: 'utf-8',
              shell: true,
              env: runEnv
            });
            const syncWithRetry = async (fn, retries = 3) => {
              for (let i = 0; i <= retries; i++) {
                try {
                  await fn();
                  return;
                } catch (e) {
                  const isNetwork = /ECONNRESET|ETIMEDOUT|ECONNREFUSED|socket hang up/i.test(e.message || '');
                  if (isNetwork && i < retries) {
                    this._logWarn(`同步任务状态失败 (${e.message})，${1 + i}s 后重试...`);
                    await new Promise((r) => setTimeout(r, (1 + i) * 1000));
                  } else {
                    throw e;
                  }
                }
              }
            };
            try {
              await syncWithRetry(() => tasksStore.assignTaskId(task.id, genTaskId, planPath));
              await syncWithRetry(() => tasksStore.updateTask(task.id, {
                phase: 'code',
                updatedAt: new Date().toISOString()
              }));
              this._logSuccess(`计划生成成功（stream-progress-plan-claude）: ${planPath} → phase=code`);
            } catch (syncErr) {
              this._logWarn(`计划已写入 ${planPath}，但同步任务状态到 Proxy 失败: ${syncErr.message}`);
              this._logWarn('请确认 Proxy 运行正常并在应用中刷新任务列表。');
            }
            return { ok: true, result: { planPath, taskId: genTaskId, task }, task };
          }

          this._logInfo(`📋 使用 ${backendName} Agent 为任务 ${taskId} 生成计划...`);
          const backend = createBackend(backendName);
          const planResult = await backend.generatePlan(genTaskId, projectPath, {
            title: task.title,
            description: task.description || task.title
          });
          if (!planResult.success) {
            throw new Error(planResult.error || 'Agent 生成计划失败');
          }
          const planPath = planResult.planPath || path.join(projectPath, 'docs', `plan-${genTaskId}.md`);
          await tasksStore.assignTaskId(task.id, genTaskId, planPath);
          await tasksStore.updateTask(task.id, {
            phase: 'code',
            updatedAt: new Date().toISOString()
          });
          this._logSuccess(`计划生成成功（Agent）: ${planPath} → phase=code，下一轮将触发代码执行`);
          return { ok: true, result: { planPath, taskId: genTaskId, task }, task };
        }

        this._logInfo(`📋 为任务 ${taskId} 生成计划（模板）...`);
        const results = await processTasksForPlan([task]);
        const result = results.find(r => String(r.task.id) === String(task.id));

        if (result && result.ok) {
          this._logSuccess(`计划生成成功: ${result.planPath}`);
          return { ok: true, result, task };
        }
        throw new Error('Plan generation failed');
      }

      this._logInfo('📋 为所有 pending 任务生成计划...');
      const results = await processPendingSkill();
      return { ok: true, results };
    } catch (error) {
      this._logError(`生成计划失败: ${error.message}`);
      return { ok: false, error: error.message };
    }
  }

  /**
   * 新版：执行任务（使用统一执行器）
   */
  async executeTask(taskId, backend = null, options = {}) {
    this._logInfo(`⚡ execute-task 已收敛为 run-phase code，taskId=${taskId} backend=${backend || '(default)'}`);
    const extraArgs = [];
    if (backend) {
      extraArgs.push(`--backend=${backend}`);
    }
    if (options.logPath) {
      extraArgs.push('--log', options.logPath);
    }
    // 直接委托给 runPhaseOnly，统一由 PhaseOrchestrator + PhaseExecutor 管理执行流程
    return this.runPhaseOnly(taskId, 'code', extraArgs);
  }

  /**
   * 标记任务为完成状态
   */
  async markTaskDone(taskId) {
    const tasksStore = require('./tasks-store-adapter');

    try {
      const task = await tasksStore.getTask(taskId);
      if (!task) {
        throw new Error(`Task not found: ${taskId}`);
      }

      this._logSuccess(`标记任务 ${taskId} 为完成状态...`);

      const result = await tasksStore.transitionTask(taskId, 'done');
      if (!result.success) {
        throw new Error(result.error);
      }

      this._logSuccess(`任务 ${taskId} 已标记为完成`);
      return { ok: true, taskId, task: result.task };
    } catch (error) {
      this._logError(`标记任务失败: ${error.message}`);
      return { ok: false, error: error.message };
    }
  }

  /**
   * JSON 任务流：处理 pending → 创建 taskId、docs/plan-*.md → planned
   */
  async processPending() {
    const { processPendingSkill } = require('./openclaw-plan-workflow');
    try {
      const results = await processPendingSkill();
      return { ok: true, results };
    } catch (error) {
      return { ok: false, error: error.message };
    }
  }

  /**
   * JSON 任务流：处理 planned → 检测 plan 完成 → done
   */
  processPlanned() {
    const { processPlannedSkill } = require('./openclaw-plan-workflow');
    return processPlannedSkill();
  }

  /**
   * 列出 JSON 存储中的任务
   */
  async listTasksJson(status) {
    const tasksStore = require('./tasks-store-adapter');
    const list = await tasksStore.listByStatus(status || undefined);
    this._logInfo(`📋 JSON 任务: ${status ? `status=${status}` : '全部'}`);
    list.forEach(t => {
      console.log(`  ${t.id} ${t.taskId || '-'} [${t.status}] ${t.title} (${t.projectKey})`);
    });
  }

  /**
   * 健康检查
   */
  async healthCheck() {
    this._logInfo('🏥 系统健康检查...');

    const healthScript = `
      const axios = require('axios');
      
      console.log('🔍 检查任务系统...');
      axios.get('http://localhost:3001/api/tasks')
        .then(() => {
          console.log('✅ 任务系统: 正常');
        })
        .catch(error => {
          console.log('❌ 任务系统: 异常 -', error.message);
        });
      
      // 检查必要文件
      const fs = require('fs');
      const path = require('path');
      
      const requiredFiles = [
        'server-dashboard-only.js',
        'openclaw-integration.js',
        'openclaw-plan-workflow.js',
        'tasks-store.js',
        'config.json'
      ];
      
      console.log('\\n🔍 检查必要文件...');
      requiredFiles.forEach(file => {
        if (fs.existsSync(path.join(__dirname, file))) {
          console.log(\`✅ \${file}: 存在\`);
        } else {
          console.log(\`❌ \${file}: 缺失\`);
        }
      });
    `;

    const scriptPath = path.join(this.projectRoot, 'temp-health-check.js');
    fs.writeFileSync(scriptPath, healthScript);

    return new Promise((resolve) => {
      const result = spawn('node', [scriptPath], {
        cwd: this.projectRoot,
        stdio: 'inherit'
      });

      result.on('close', () => {
        fs.unlinkSync(scriptPath);
        resolve();
      });
    });
  }

  /**
   * 根据命令执行相应操作
   */
  async executeCommand(command, ...args) {
    switch (command) {
      case 'start-server':
        return this.startServer();

      case 'stop-server':
        return this.stopServer();

      case 'run-workflow':
        if (args.length < 1) {
          this._logError('用法: run-workflow <workflow-name> [参数...]');
          this._logInfo('例如: run-workflow auto-dev "标题" "描述" <projectKey>');
          return;
        }
        return this.runWorkflow(args[0], ...args.slice(1));

      case 'create-task':
        if (args.length < 2) {
          this._logError('用法: create-task "标题" "描述" [优先级]');
          return;
        }
        return this.createTask(args[0], args[1], args[2] || 'medium');

      case 'create-task-json':
        if (args.length < 3) {
          this._logError('用法: create-task-json "标题" "描述" <projectKey>');
          return;
        }
        return this.createTaskJson(args[0], args[1], args[2]);

      case 'process-pending':
        this._logWarn('process-pending 为旧版 JSON 流程命令，建议改用 generate-plan');
        return this.processPending();

      case 'process-planned':
        this._logWarn('process-planned 为旧版 JSON 流程命令，推荐改用阶段流水线或 mark-done');
        return this.processPlanned();

      case 'list-tasks-json':
        return this.listTasksJson(args[0] || null);

      case 'list-tasks':
        this._logWarn('list-tasks 为旧版 HTTP API 列表命令，建议改用 list-tasks-json');
        return this.listTasks();

      case 'confirm-plan':
        if (!args[0]) {
          this._logError('用法: confirm-plan <任务ID>');
          return;
        }
        this._logWarn('confirm-plan 为旧版命令，JSON 流程下无需该步骤');
        return this.confirmPlan(args[0]);

      case 'confirm-done':
        if (!args[0]) {
          this._logError('用法: confirm-done <任务ID>');
          return;
        }
        this._logWarn('confirm-done 为旧版命令，JSON 流程下无需该步骤');
        return this.confirmDone(args[0]);

      case 'submit-task':
        if (!args[0]) {
          this._logError('用法: submit-task <任务ID>');
          return;
        }
        this._logWarn('submit-task 为旧版命令，请在本地仓库手动执行 git commit / push');
        return this.submitTask(args[0]);

      case 'health-check':
        return this.healthCheck();

      case 'generate-plan': {
        const useAgent = args.includes('--agent');
        const taskId = args[0];
        this._logInfo(`📋 generate-plan 已启动 taskId=${taskId} useAgent=${useAgent}`);
        return this.generatePlanTask(taskId, { useAgent }).then((out) => {
          if (out && out.ok === false) {
            this._logError(`生成计划失败: ${out.error || 'unknown'}`);
            process.exit(1);
          }
          return out;
        });
      }

      case 'execute-task':
        if (!args[0]) {
          this._logError('用法: execute-task <taskId> [--backend claude|cursor] [--log [path]]');
          return;
        }
        const execTaskId = args[0];
        const execBackend = this._parseArg(args, '--backend');
        const execLogPath = this._parseLogPath(args, execTaskId);
        return this.executeTask(execTaskId, execBackend, { logPath: execLogPath });

      case 'mark-done':
        if (!args[0]) {
          this._logError('用法: mark-done <taskId>');
          return;
        }
        return this.markTaskDone(args[0]);

      // === 阶段流水线命令 ===
      case 'phase-pipeline':
        if (!args[0]) {
          this._logError('用法: phase-pipeline <taskId> [--dry-run] [--skip-commit] [--backend=xxx]');
          return;
        }
        return this.runPhasePipeline(args[0], args.slice(1));

      case 'auto-execute':
        if (!args[0]) {
          this._logError('用法: auto-execute <taskId> [--backend=xxx]');
          return;
        }
        return this.runAutoExecute(args[0], args.slice(1));

      case 'run-phase':
        if (!args[0] || !args[1]) {
          this._logError('用法: run-phase <taskId> <plan|code|test|done> [--backend=xxx]');
          return;
        }
        return this.runPhaseOnly(args[0], args[1], args.slice(2));

      case 'phase-content':
        if (!args[0]) {
          this._logError('用法: phase-content <planPath> [phase]');
          return;
        }
        return this.getPhaseContent(args[0], args[1] || 'plan');

      case 'phase-advance':
        if (!args[0]) {
          this._logError('用法: phase-advance <taskId> [currentPhase]');
          return;
        }
        return this.advancePhase(args[0], args[1] || 'plan');

      case 'reset-phase':
        if (!args[0] || !args[1]) {
          this._logError('用法: reset-phase <taskId> <phase> [--status=<status>]');
          this._logError('  将任务强制重置到指定阶段，并恢复该阶段及后续阶段的 plan 文件 checkbox');
          this._logError('  phase: code | test | done');
          this._logError('  --status: 同时重置任务状态（默认 planned）');
          return;
        }
        return this.resetPhase(args[0], args[1], args.slice(2));

      case 'help':
      default:
        this.showHelp();
        break;
    }
  }

  // === 阶段流水线方法 ===

  /**
   * 运行阶段流水线
   */
  async runPhasePipeline(taskId, options = []) {
    const PhaseOrchestrator = require('./phase-orchestrator.js');
    const orchestrator = new PhaseOrchestrator({
      dryRun: options.includes('--dry-run')
    });

    const backend = options.find(o => o.startsWith('--backend='))?.split('=')[1];
    const skipCommit = options.includes('--skip-commit');

    try {
      this._logInfo(`🚀 运行阶段流水线: taskId=${taskId} backend=${backend || '(default)'} skipCommit=${skipCommit}`);
      const result = await orchestrator.runPipeline(taskId, { backend, skipCommit });
      console.log('\n' + JSON.stringify(result, null, 2));
      return result;
    } catch (error) {
      this._logError(`流水线失败: ${error.message}`);
      return { ok: false, error: error.message };
    }
  }

  /**
   * 仅执行指定阶段（触发式：定时器根据 task.phase 触发下一阶段时调用）。
   */
  async runPhaseOnly(taskId, phase, options = []) {
    const PhaseOrchestrator = require('./phase-orchestrator.js');
    const orchestrator = new PhaseOrchestrator({ dryRun: options.includes('--dry-run') });
    const backend = options.find(o => o.startsWith('--backend='))?.split('=')[1];
    try {
      this._logInfo(`🚀 run-phase 触发: taskId=${taskId} phase=${phase} backend=${backend || '(default)'} dryRun=${options.includes('--dry-run')}`);
      const result = await orchestrator.runPhaseOnly(taskId, phase, { backend });
      console.log(JSON.stringify(result, null, 2));
      return result;
    } catch (error) {
      this._logError(`run-phase ${phase} 失败: ${error.message}`);
      return { success: false, error: error.message };
    }
  }

  /**
   * 一键自动执行：若无计划则先生成计划，再执行「代码生成 → 测试验证 → 提交」。
   * 你只需创建任务后触发此命令，验收结果；不满意则新建任务迭代。
   */
  async runAutoExecute(taskId, options = []) {
    const tasksStore = require('./tasks-store-adapter');
    try {
      const task = await tasksStore.getTask(taskId);
      if (!task) throw new Error(`Task not found: ${taskId}`);

      if (!task.planPath || task.status === 'pending' || task.status === 'failed') {
        this._logInfo('📋 任务尚无计划，先生成计划...');
        const planResult = await this.generatePlanTask(taskId);
        if (!planResult.ok) throw new Error(planResult.error || '生成计划失败');
      }

      this._logInfo('🚀 开始自动执行（代码 → 测试 → 提交）...');
      return await this.runPhasePipeline(taskId, options);
    } catch (error) {
      this._logError(`自动执行失败: ${error.message}`);
      return { ok: false, error: error.message };
    }
  }

  /**
   * 获取阶段内容
   */
  async getPhaseContent(planPath, phase) {
    const PhaseOrchestrator = require('./phase-orchestrator.js');
    const orchestrator = new PhaseOrchestrator();
    const content = orchestrator.getPhasePlanContent(planPath, phase);
    console.log(JSON.stringify(content, null, 2));
    return content;
  }

  /**
   * 强制重置任务到指定阶段：
   * 1. 更新 DB 中的 task.phase 和 task.status
   * 2. 将 plan 文件中该阶段及后续阶段的 [x] 恢复为 [ ]（已执行的阶段不动）
   */
  async resetPhase(taskId, targetPhase, options = []) {
    const PHASE_ORDER = ['plan', 'code', 'test', 'done'];
    const PHASE_MARKERS = {
      plan: '### Plan 阶段',
      code: '### Code 阶段',
      test: '### Test 阶段',
      done: '### Done 阶段'
    };
    const DEFAULT_STATUS = {
      code: 'planned',
      test: 'inProgress',
      done: 'testing'
    };

    if (!PHASE_ORDER.includes(targetPhase)) {
      this._logError(`无效阶段: ${targetPhase}，支持: ${PHASE_ORDER.join(' | ')}`);
      return { success: false, error: 'invalid phase' };
    }

    const tasksStore = require('./tasks-store-adapter');
    const task = await tasksStore.getTask(taskId);
    if (!task) {
      this._logError(`Task not found: ${taskId}`);
      return { success: false, error: 'task not found' };
    }

    const statusOpt = options.find(o => o.startsWith('--status='));
    const newStatus = statusOpt ? statusOpt.split('=')[1] : (DEFAULT_STATUS[targetPhase] || 'planned');

    // 1. 更新 DB
    await tasksStore.updateTask(taskId, {
      phase: targetPhase,
      status: newStatus,
      updatedAt: new Date().toISOString()
    });
    this._logInfo(`✅ DB 已更新: task.phase=${targetPhase} task.status=${newStatus}`);

    // 2. 重置 plan 文件中该阶段及后续阶段的 checkbox
    const planPath = task.planPath;
    if (planPath && fs.existsSync(planPath)) {
      let content = fs.readFileSync(planPath, 'utf-8');
      const targetIdx = PHASE_ORDER.indexOf(targetPhase);
      const phasesToReset = PHASE_ORDER.slice(targetIdx); // 目标阶段 + 后续阶段

      for (const phase of phasesToReset) {
        const marker = PHASE_MARKERS[phase];
        if (!marker) continue;
        const idx = content.indexOf(marker);
        if (idx === -1) continue;
        const afterSection = content.indexOf('\n', idx) + 1;
        const nextSection = content.slice(afterSection).search(/\n(#{2,3}\s|---)/);
        const sectionEnd = nextSection === -1 ? content.length : afterSection + nextSection;

        // 把本阶段的 [x] 恢复为 [ ]，但保留含时间戳的"系统完成记录"行（由 appendPhaseCompleteToPlan 写入）
        const section = content.slice(afterSection, sectionEnd);
        // 只重置"模板类"条目（不含 ISO 时间戳 YYYY-MM-DDTHH: 的行）
        const reset = section.replace(/^(\s*- )\[x\]( (?!.*\d{4}-\d{2}-\d{2}T).*)/gm, '$1[ ]$2');
        if (reset !== section) {
          content = content.slice(0, afterSection) + reset + content.slice(sectionEnd);
          this._logInfo(`✅ plan 文件 ${phase} 阶段 checkbox 已重置为 [ ]`);
        }
      }

      // 同步更新 plan meta 的 phase 字段
      content = content.replace(/^(\s*phase:\s*).*$/m, `$1${targetPhase}`);
      fs.writeFileSync(planPath, content, 'utf-8');
      this._logInfo(`✅ plan meta.phase 已同步为 ${targetPhase}`);
    } else {
      this._logInfo('⚠️  无 plan 文件，仅更新了 DB');
    }

    const result = { success: true, taskId, phase: targetPhase, status: newStatus };
    console.log(JSON.stringify(result, null, 2));
    return result;
  }

  /**
   * 推进阶段
   */
  async advancePhase(taskId, currentPhase) {
    const PhaseOrchestrator = require('./phase-orchestrator.js');
    const orchestrator = new PhaseOrchestrator();
    const result = await orchestrator.advancePhase(taskId, currentPhase);
    console.log(JSON.stringify(result, null, 2));
    return result;
  }
}

// 命令行接口
if (require.main === module) {
  const integration = new OpenClawIntegration();

  const args = process.argv.slice(2);
  if (args.length === 0) {
    integration.showHelp();
  } else {
    integration.executeCommand(args[0], ...args.slice(1))
      .catch(error => {
        console.error('❌ 执行命令失败:', error.message);
        process.exit(1);
      });
  }
}

module.exports = OpenClawIntegration;