#!/usr/bin/env node

/**
 * Phase Orchestrator - 阶段流水线协调器
 *
 * 实现 Plan → Code → Test → Done 的阶段化流水线
 * 支持渐进式披露：每个阶段只传入当前阶段所需的 plan 片段
 * 自动提交：Done 阶段完成后自动 git commit
 */

const fs = require('fs');
const path = require('path');
const { spawn, execSync } = require('child_process');
const { createPhaseExecutor } = require('./unified-executor');

/**
 * 将测试阶段结果追加写入 plan 文件的 Execution Log Test 阶段
 */
function appendTestResultToPlan(planPath, testResult) {
  let content = fs.readFileSync(planPath, 'utf-8');
  const marker = '### Test 阶段';
  const idx = content.indexOf(marker);
  if (idx === -1) return;
  const afterSection = content.indexOf('\n', idx) + 1;
  const line = testResult.success
    ? `- [x] ${new Date().toISOString()}: ${testResult.message || 'Tests passed'}`
    : `- [ ] ${new Date().toISOString()}: ${testResult.error || testResult.message || 'Tests failed'}`;
  content = content.slice(0, afterSection) + line + '\n' + content.slice(afterSection);
  fs.writeFileSync(planPath, content, 'utf-8');
}

/** 阶段名与 Execution Log 中的标题对应 */
const PHASE_MARKERS = {
  plan: '### Plan 阶段',
  code: '### Code 阶段',
  test: '### Test 阶段',
  done: '### Done 阶段'
};

/**
 * 将某阶段区块内所有未勾选项 - [ ] 改为 - [x]，便于终态判断（todo 全部完成）
 */
function checkOffPhaseSectionChecklists(content, sectionStart, sectionEnd) {
  const section = content.slice(sectionStart, sectionEnd);
  const replaced = section.replace(/^(\s*)- \[ \]/gm, '$1- [x]');
  if (replaced === section) return content;
  return content.slice(0, sectionStart) + replaced + content.slice(sectionEnd);
}

/**
 * 阶段完成时更新 plan 进度：1）勾选该阶段内所有 checklist；2）追加一条完成记录
 */
function appendPhaseCompleteToPlan(planPath, phase, message) {
  if (!planPath || !fs.existsSync(planPath)) return;
  const marker = PHASE_MARKERS[phase];
  if (!marker) return;
  let content = fs.readFileSync(planPath, 'utf-8');
  const idx = content.indexOf(marker);
  if (idx === -1) return;
  const afterSection = content.indexOf('\n', idx) + 1;
  // 找到本阶段结束位置（下一个 ## / ### 或 ---）
  const nextSection = content.slice(afterSection).search(/\n(#{2,3}\s|---)/);
  const sectionEnd = nextSection === -1 ? content.length : afterSection + nextSection;
  content = checkOffPhaseSectionChecklists(content, afterSection, sectionEnd);
  const line = `- [x] ${new Date().toISOString()}: ${message || phase + ' 阶段完成'}`;
  content = content.slice(0, afterSection) + line + '\n' + content.slice(afterSection);
  fs.writeFileSync(planPath, content, 'utf-8');
}

// 阶段定义
const PHASES = {
  plan: {
    name: 'Plan',
    next: 'code',
    description: '生成/确认计划',
  },
  code: {
    name: 'Code',
    next: 'test',
    description: '代码实现',
  },
  test: {
    name: 'Test',
    next: 'done',
    description: '测试验证',
  },
  done: {
    name: 'Done',
    next: null,
    description: '完成/提交',
  }
};

class PhaseOrchestrator {
  constructor(options = {}) {
    this.tasksStore = require('./tasks-store-adapter');
    this.logger = options.logger || console;
    this.dryRun = options.dryRun || false;
  }

  /**
   * 解析 plan 文件，提取阶段内容
   */
  parsePlanFile(planPath) {
    if (!planPath || !fs.existsSync(planPath)) {
      return null;
    }

    const content = fs.readFileSync(planPath, 'utf-8');
    const result = {
      raw: content,
      overview: '',
      phases: {},
      meta: {}
    };

    // 解析 meta 部分
    const metaMatch = content.match(/\n---\nmeta:\n([\s\S]*?)\n---/);
    if (metaMatch) {
      const metaLines = metaMatch[1].split('\n');
      metaLines.forEach(line => {
        const [key, ...valueParts] = line.split(':');
        if (key && valueParts.length > 0) {
          result.meta[key.trim()] = valueParts.join(':').trim();
        }
      });
    }

    // 解析 Overview 部分
    const overviewMatch = content.match(/## Overview\n([\s\S]*?)(?=## Execution Log|$)/);
    if (overviewMatch) {
      result.overview = overviewMatch[1].trim();
    }

    // 解析 Execution Log 各阶段
    const phases = ['Plan', 'Code', 'Test', 'Done'];
    phases.forEach(phase => {
      const phaseRegex = new RegExp(`### ${phase} 阶段\\n([\\s\\S]*?)(?=### |## |$)`, 'i');
      const phaseMatch = content.match(phaseRegex);
      if (phaseMatch) {
        result.phases[phase.toLowerCase()] = {
          content: phaseMatch[1].trim(),
          checklist: this.parseChecklist(phaseMatch[1])
        };
      }
    });

    return result;
  }

  /**
   * 解析 checklist 项
   */
  parseChecklist(content) {
    const items = [];
    const lines = content.split('\n');
    lines.forEach(line => {
      const match = line.match(/- \[([ xX])\] (.+)/);
      if (match) {
        items.push({
          checked: match[1].toLowerCase() === 'x',
          text: match[2].trim()
        });
      }
    });
    return items;
  }

  /**
   * 获取当前阶段所需的 plan 片段（渐进式披露）
   */
  getPhasePlanContent(planPath, phase) {
    const parsed = this.parsePlanFile(planPath);
    if (!parsed) return null;

    // 基础信息始终包含
    const base = {
      taskId: parsed.meta.taskId,
      title: parsed.meta.title,
      projectKey: parsed.meta.projectKey,
      projectPath: parsed.meta.projectPath,
      overview: parsed.overview,
      currentPhase: phase
    };

    // 根据阶段返回不同的内容
    switch (phase) {
      case 'plan':
        return {
          ...base,
          phaseContent: '生成详细的开发计划，包括技术方案、任务拆分、风险评估',
          input: {
            description: parsed.overview
          },
          output: {
            expected: '完整的开发计划文档'
          }
        };

      case 'code':
        return {
          ...base,
          phaseContent: parsed.phases.code?.content || '',
          checklist: parsed.phases.code?.checklist || [],
          input: {
            plan: parsed.phases.plan?.content || '',
            constraints: '仅实现计划中的代码部分，不要运行测试或提交'
          },
          output: {
            expected: '代码实现完成'
          }
        };

      case 'test':
        return {
          ...base,
          phaseContent: parsed.phases.test?.content || '',
          checklist: parsed.phases.test?.checklist || [],
          input: {
            scope: '运行所有测试，确保代码质量'
          },
          output: {
            expected: '所有测试通过'
          }
        };

      case 'done':
        return {
          ...base,
          phaseContent: parsed.phases.done?.content || '',
          checklist: parsed.phases.done?.checklist || [],
          input: {
            scope: '代码审查、最终确认、提交'
          },
          output: {
            expected: '代码已提交'
          }
        };

      default:
        return base;
    }
  }

  /**
   * 推进任务到下一阶段
   */
  async advancePhase(taskId, currentPhase) {
    const phase = PHASES[currentPhase];
    if (!phase) {
      throw new Error(`Unknown phase: ${currentPhase}`);
    }

    if (!phase.next) {
      this.logger.log(`Task ${taskId} is already at final phase (done)`);
      return { phase: 'done', advanced: false };
    }

    const nextPhase = phase.next;
    this.logger.log(`Advancing task ${taskId} from ${currentPhase} to ${nextPhase}`);

    // 更新任务 phase
    await this.tasksStore.updateTask(taskId, {
      phase: nextPhase,
      updatedAt: new Date().toISOString()
    });

    return { phase: nextPhase, advanced: true };
  }

  /**
   * 执行阶段流水线
   * @param {string} taskId 任务 ID
   * @param {object} options 选项
   */
  async runPipeline(taskId, options = {}) {
    const task = await this.tasksStore.getTask(taskId);
    if (!task) {
      throw new Error(`Task not found: ${taskId}`);
    }

    this.logger.log(`\n🚀 Starting phase pipeline for task ${taskId}`);
    this.logger.log(`📋 Title: ${task.title}`);
    this.logger.log(`📋 Current phase: ${task.phase || 'plan'}`);

    const planPath = task.planPath;
    const projectKey = task.projectKey;

    if (!planPath) {
      throw new Error(`Task ${taskId} has no plan file`);
    }

    // 确定起始阶段
    let currentPhase = task.phase || 'plan';

    // 执行各阶段
    const results = {
      taskId,
      phases: {},
      success: true
    };

    while (currentPhase) {
      this.logger.log(`\n📋 Executing phase: ${currentPhase}`);

      const phaseContent = this.getPhasePlanContent(planPath, currentPhase);
      results.phases[currentPhase] = {
        started: new Date().toISOString(),
        input: phaseContent
      };

      try {
        const phaseResult = await this.executePhase(taskId, currentPhase, phaseContent, options);
        results.phases[currentPhase].result = phaseResult;
        results.phases[currentPhase].completed = new Date().toISOString();

        if (!phaseResult.success) {
          results.success = false;
          results.error = `Phase ${currentPhase} failed: ${phaseResult.error}`;
          break;
        }

        // 推进到下一阶段
        const advanceResult = await this.advancePhase(taskId, currentPhase);
        currentPhase = advanceResult.advanced ? advanceResult.phase : null;

      } catch (error) {
        results.phases[currentPhase].error = error.message;
        results.phases[currentPhase].completed = new Date().toISOString();
        results.success = false;
        results.error = error.message;
        break;
      }
    }

    // 如果所有阶段完成，执行自动提交
    if (results.success && !currentPhase) {
      results.commit = await this.autoCommit(task, options);
    }

    return results;
  }

  /**
   * 执行单个阶段
   */
  async executePhase(taskId, phase, phaseContent, options = {}) {
    this.logger.log(`📋 Phase: ${PHASES[phase]?.description || phase}`);

    switch (phase) {
      case 'plan':
        return this.executePlanPhase(taskId, phaseContent, options);

      case 'code':
        return this.executeAgentPhase(taskId, phase, phaseContent, options);

      case 'test':
        return this.executeAgentPhase(taskId, phase, phaseContent, options);

      case 'done':
        const res = await this.executeAgentPhase(taskId, phase, phaseContent, options);
        if (res.success) {
          await this.tasksStore.transitionTask(taskId, 'completed');
        }
        return res;

      default:
        return { success: false, error: `Unknown phase: ${phase}` };
    }
  }

  /**
   * Universal Agent Phase logic (Tmux driven)
   */
  async executeAgentPhase(taskId, phase, phaseContent, options) {
    this.logger.log(`📋 Executing phase via backend for phase: ${phase}...`);

    if (this.dryRun) {
      return { success: true, message: `Dry run - skipping ${phase} execution` };
    }

    const task = await this.tasksStore.getTask(taskId);
    if (!task) throw new Error('Task not found');

    // 解析项目路径（与 autoCommit 中保持一致）
    const ProjectResolver = require('./project-resolver');
    const resolver = new ProjectResolver();
    const project = await resolver.resolve(task.projectKey);
    if (!project || !project.path) {
      throw new Error(`Project not found or missing path: ${task.projectKey}`);
    }

    const backendName = options.backend || task.backend || null;
    const phaseExecutor = createPhaseExecutor(backendName, this.logger);

    const execResult = await phaseExecutor.executePhase(task, phase, {
      projectPath: project.path,
      planPath: task.planPath
    });

    if (!execResult.success) {
      return { success: false, error: execResult.error };
    }

    // Async executor (e.g. TmuxPhaseExecutor): the inner tmux process handles plan annotation and phase advance
    if (execResult.async) {
      return { success: true, async: true };
    }

    if (task.planPath && fs.existsSync(task.planPath)) {
      appendPhaseCompleteToPlan(task.planPath, phase, `Phase ${phase} completed by backend ${backendName || task.backend || 'default'}`);
    }

    return { success: true, message: `Phase ${phase} completed by backend ${backendName || task.backend || 'default'}` };
  }

  /**
   * Plan 阶段：生成/确认计划
   */
  async executePlanPhase(taskId, phaseContent, options) {
    this.logger.log('📋 Generating/confirming plan...');

    // Plan 文件已存在时跳过生成
    if (phaseContent && phaseContent.taskId && phaseContent.overview) {
      this.logger.log('📋 ✅ Plan already exists, skipping generation');
      const task = await this.tasksStore.getTask(taskId);
      if (task?.planPath && fs.existsSync(task.planPath)) {
        appendPhaseCompleteToPlan(task.planPath, 'plan', 'Plan already exists');
      }
      return { success: true, message: 'Plan already exists' };
    }

    // 如果需要生成 plan，调用 generate-plan capability
    if (!this.dryRun) {
      const { processTasksForPlan } = require('./openclaw-plan-workflow');
      const task = await this.tasksStore.getTask(taskId);
      const results = await processTasksForPlan([task]);
      const result = results.find(r => String(r.task?.id) === String(task.id) || r.taskId === taskId);

      if (result && result.ok) {
        if (result.planPath && fs.existsSync(result.planPath)) {
          appendPhaseCompleteToPlan(result.planPath, 'plan', 'Plan 生成完成');
        }

        // 自动触发真正的 plan 生成 agent
        const { execSync } = require('child_process');
        try {
          // 这个命令会调用 claude-backend.js generate-plan (如同界面上的 `生成计划` 功能)
          const cmd = `node "${path.join(__dirname, 'openclaw-integration.js')}" generate-plan "${taskId}"`;
          this.logger.log(`📋 Running: ${cmd}`);
          execSync(cmd, { encoding: 'utf-8', stdio: 'pipe' });
        } catch (e) {
          this.logger.log(`📋 ⚠️ Plan agent 触发失败: ${e.message}`);
        }

        // 把状态推演到 inProgress (因为已经 plan 结束了)
        await this.tasksStore.updateTask(taskId, {
          status: 'inProgress',
          phase: 'code',
          updatedAt: new Date().toISOString()
        });

        return { success: true, planPath: result.planPath };
      }
    }

    return { success: true, message: 'Plan phase completed' };
  }

  /**
   * 仅执行指定阶段（触发式：定时器根据 plan/任务状态触发下一阶段时调用）
   * 执行完后更新 plan 进度、推进 task.phase，若为 done 阶段则再执行 autoCommit。
   */
  async runPhaseOnly(taskId, phase, options = {}) {
    const task = await this.tasksStore.getTask(taskId);
    if (!task) throw new Error(`Task not found: ${taskId}`);
    if (!task.planPath || !fs.existsSync(task.planPath)) throw new Error(`Task ${taskId} has no plan file`);

    const currentPhase = task.phase || 'plan';
    this.logger.log(`📋 runPhaseOnly: taskId=${taskId} requestedPhase=${phase} currentPhase=${currentPhase} status=${task.status}`);

    if (currentPhase !== phase) {
      this.logger.log(`📋 runPhaseOnly: skip execution because task.phase(${currentPhase}) != requestedPhase(${phase}). task.id=${taskId} task.status=${task.status}`);
      return { success: true, skipped: true, message: `Task phase is ${currentPhase}, not ${phase}` };
    }

    const planPath = task.planPath;
    this.logger.log(`📋 runPhaseOnly: planPath=${planPath}`);
    const phaseContent = this.getPhasePlanContent(planPath, phase);

    this.logger.log('📋 runPhaseOnly: executing phase via executePhase...');
    const phaseResult = await this.executePhase(taskId, phase, phaseContent, options);
    if (!phaseResult.success) {
      this.logger.log(`📋 runPhaseOnly: phase execution failed: ${phaseResult.error || 'unknown error'}`);
      return { success: false, error: phaseResult.error, phase };
    }

    // Async executor (TmuxPhaseExecutor): the tmux pane process will call advancePhase itself.
    // Return immediately so the caller (run-phase CLI) can exit without blocking.
    if (phaseResult.async) {
      this.logger.log(`📋 runPhaseOnly: async execution started (tmux pane), skipping phase advance in this process`);
      return { success: true, async: true, phase };
    }

    this.logger.log('📋 runPhaseOnly: phase execution succeeded, advancing phase...');
    const advanceResult = await this.advancePhase(taskId, phase);
    const nextPhase = advanceResult.phase;
    this.logger.log(`📋 runPhaseOnly: advanced to nextPhase=${nextPhase === null ? 'null' : nextPhase}`);

    if (phase === 'done' && nextPhase === null) {
      this.logger.log('📋 runPhaseOnly: done phase completed, triggering autoCommit...');
      const commitResult = await this.autoCommit(task, options);
      return { success: true, phase, nextPhase: null, commit: commitResult };
    }
    return { success: true, phase, nextPhase };
  }

  /**
   * 自动提交代码
   */
  async autoCommit(task, options = {}) {
    if (options.skipCommit) {
      return { skipped: true, message: 'Auto-commit skipped by option' };
    }

    const ProjectResolver = require('./project-resolver');
    const resolver = new ProjectResolver();
    const project = await resolver.resolve(task.projectKey);

    this.logger.log('\n📝 Auto-committing changes...');

    try {
      // 检查是否有变更
      const status = execSync('git status --porcelain', {
        cwd: project.path,
        encoding: 'utf-8'
      }).trim();

      if (!status) {
        return { success: true, message: 'No changes to commit' };
      }

      // 生成 commit message
      const commitMessage = this.generateCommitMessage(task);

      // git add
      if (!this.dryRun) {
        execSync('git add .', { cwd: project.path });
        this.logger.log('📋 Staged all changes');
      }

      // git commit
      if (!this.dryRun) {
        execSync(`git commit -m "${commitMessage}"`, { cwd: project.path });
        this.logger.log(`📋 Committed: ${commitMessage}`);
      }

      return {
        success: true,
        message: commitMessage,
        files: status.split('\n').length
      };

    } catch (error) {
      this.logger.log(`📋 ⚠️ Auto-commit failed: ${error.message}`);
      return { success: false, error: error.message };
    }
  }

  /**
   * 生成 commit message
   */
  generateCommitMessage(task) {
    const taskId = task.taskId || task.id;
    const title = task.title.replace(/"/g, '\\"').substring(0, 50);
    return `feat(task): ${title} [${taskId}]`;
  }

  /**
   * CLI 接口
   */
  static async runCLI() {
    const args = process.argv.slice(2);
    const command = args[0];

    const orchestrator = new PhaseOrchestrator({
      dryRun: args.includes('--dry-run')
    });

    switch (command) {
      case 'run': {
        const taskId = args[1];
        if (!taskId) {
          console.error('Usage: node phase-orchestrator.js run <taskId> [--dry-run]');
          process.exit(1);
        }

        const backend = args.find(a => a.startsWith('--backend='))?.split('=')[1];
        const skipCommit = args.includes('--skip-commit');

        try {
          const result = await orchestrator.runPipeline(taskId, { backend, skipCommit });
          console.log('\n' + JSON.stringify(result, null, 2));
          process.exit(result.success ? 0 : 1);
        } catch (error) {
          console.error(`\n❌ Pipeline failed: ${error.message}`);
          process.exit(1);
        }
        break;
      }

      case 'phase-content': {
        const planPath = args[1];
        const phase = args[2] || 'plan';
        if (!planPath) {
          console.error('Usage: node phase-orchestrator.js phase-content <planPath> [phase]');
          process.exit(1);
        }
        const content = orchestrator.getPhasePlanContent(planPath, phase);
        console.log(JSON.stringify(content, null, 2));
        break;
      }

      case 'advance': {
        const taskId = args[1];
        const currentPhase = args[2] || 'plan';
        if (!taskId) {
          console.error('Usage: node phase-orchestrator.js advance <taskId> [currentPhase]');
          process.exit(1);
        }
        const result = await orchestrator.advancePhase(taskId, currentPhase);
        console.log(JSON.stringify(result, null, 2));
        break;
      }

      case 'run-phase': {
        const taskId = args[1];
        const phase = args[2];
        if (!taskId || !phase) {
          console.error('Usage: node phase-orchestrator.js run-phase <taskId> <plan|code|test|done> [--backend=xxx]');
          process.exit(1);
        }
        const backend = args.find(a => a.startsWith('--backend='))?.split('=')[1];
        try {
          const result = await orchestrator.runPhaseOnly(taskId, phase, { backend });
          console.log(JSON.stringify(result, null, 2));
          process.exit(result.success ? 0 : 1);
        } catch (error) {
          console.error(`run-phase failed: ${error.message}`);
          process.exit(1);
        }
        break;
      }

      default:
        console.log(`
Phase Orchestrator - 阶段流水线协调器

用法:
  node phase-orchestrator.js run <taskId> [--dry-run] [--backend=xxx] [--skip-commit]
    运行完整的 Plan → Code → Test → Done 流水线

  node phase-orchestrator.js phase-content <planPath> [phase]
    获取指定阶段的 plan 内容（渐进式披露）

  node phase-orchestrator.js advance <taskId> [currentPhase]
    手动推进任务到下一阶段

  node phase-orchestrator.js run-phase <taskId> <plan|code|test|done> [--backend=xxx]
    仅执行指定阶段（供定时触发用），完成后更新 plan 进度并推进 phase

选项:
  --dry-run      模拟运行，不执行实际操作
  --backend=xxx  指定执行后端 (claude/cursor/tuxme)
  --skip-commit  跳过自动提交
        `);
    }
  }
}

// CLI 入口
if (require.main === module) {
  PhaseOrchestrator.runCLI().catch(e => {
    console.error(e.message);
    process.exit(1);
  });
}

module.exports = PhaseOrchestrator;
