#!/usr/bin/env node

/**
 * Agent Start Skill
 *
 * Purpose: Start agents in tmux sessions for task execution
 * Input: (projectKey, taskId, backend)
 * Backend: tuxme, cursor, claude
 * State: Creates tmux session/window/pane and starts agent
 * Command: start <projectKey> <taskId> <backend>
 *
 * Handles: TMUX session management, agent spawning, metadata tracking
 */

const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const tasksStore = require('./tasks-store-adapter');

// 支持的标准阶段，需与 phase-orchestrator / openclaw-integration 保持一致
const SUPPORTED_PHASES = ['plan', 'code', 'test', 'done'];

/**
 * TODO(阶段/agent 扩展入口):
 * - 如需为不同阶段配置默认 backend/agent（而不是写在 task/plan 里），可以在此对象中增加映射：
 *   - 例如：DEFAULT_PHASE_CONFIG.code = { backend: 'cursor' }
 *   - 新增阶段时同步扩展 SUPPORTED_PHASES + DEFAULT_PHASE_CONFIG
 * - 运行时优先级仍由 resolvePhaseBackendConfig 控制，DEFAULT_PHASE_CONFIG 只是兜底。
 */
const DEFAULT_PHASE_CONFIG = {
  // plan: { backend: 'ccr' },
  // code: { backend: 'cursor' },
  // test: { backend: 'cursor' },
  // done: { backend: 'ccr' },
};

/**
 * Execute command and return output
 */
function execCommand(command, options = {}) {
  try {
    return execSync(command, {
      encoding: 'utf-8',
      stdio: 'pipe',
      ...options
    }).trim();
  } catch (error) {
    if (options.ignoreError) return null;
    throw new Error(`Command failed: ${command}\n${error.message}`);
  }
}

/**
 * Ensure tmux session exists, create if not
 */
function ensureTmuxSession(sessionName) {
  const sessions = execCommand('tmux list-sessions -F "#{session_name}" 2>/dev/null || true');
  const exists = sessions.split('\n').includes(sessionName);

  if (!exists) {
    console.log(`📦 Creating tmux session: ${sessionName}`);
    execCommand(`tmux new-session -d -s "${sessionName}"`);
    console.log(`✅ Session created: ${sessionName}`);
  } else {
    console.log(`📍 Session already exists: ${sessionName}`);
  }

  return sessionName;
}

/**
 * Create a new uniquely-named tmux window for this task.
 * Returns the pane id (e.g. %1) for reliable targeting; session:window can fail if tmux resolves names differently.
 */
function createTaskWindow(sessionName, taskId) {
  const windowName = taskId;
  console.log(`📦 Creating tmux window: ${windowName}`);
  const paneId = execCommand(`tmux new-window -t "${sessionName}" -n "${windowName}" -d -P -F '#{pane_id}'`);
  if (!paneId || !paneId.trim()) {
    throw new Error(`tmux new-window did not return pane id for ${sessionName}:${windowName}`);
  }
  console.log(`✅ Window created: ${sessionName}:${windowName} (pane ${paneId.trim()})`);
  return paneId.trim();
}

/**
 * Create a new pane in an existing window (single-window mode)
 * Returns the pane id (e.g. %5) for targeting
 */
function createTaskPane(sessionName, windowTarget) {
  const target = `${sessionName}:${windowTarget}`;
  console.log(`📦 Creating pane in window: ${target}`);
  const paneId = execCommand(`tmux split-window -t "${target}" -d -P -F '#{pane_id}'`);
  console.log(`✅ Pane created: ${paneId}`);
  return paneId;
}

/**
 * Spawn command in a tmux pane. Target can be pane id (e.g. %1) or session:window.
 * When autoClose is true, the shell exits after the command finishes (pane closes).
 * Default autoClose=false for debugging; set env AGENT_START_AUTO_CLOSE=1 to close pane when done.
 */
function spawnInTmuxPane(target, command, options = {}) {
  const defaultAutoClose = process.env.AGENT_START_AUTO_CLOSE === '1';
  const { autoClose = defaultAutoClose } = options;
  const targetArg = target.startsWith('%') ? target : `"${target}"`;
  // The command is sent as-is. Callers are responsible for adding log piping inside the command.
  execCommand(`tmux send-keys -t ${targetArg} 'echo "[${target}] Starting..."' C-m`);
  const escaped = shEscapeSingle(command);
  if (autoClose) {
    execCommand(`tmux send-keys -t ${targetArg} '${escaped}; exit' C-m`);
  } else {
    execCommand(`tmux send-keys -t ${targetArg} '${escaped}' C-m`);
  }
  console.log(`🚀 Command sent to: ${target} (autoClose: ${autoClose}, set AGENT_START_AUTO_CLOSE=1 to close when done)`);
  return true;
}

/** Escape for single-quoted shell literal (value in '...') */
function shEscapeSingle(s) {
  if (s == null) return '';
  return String(s).replace(/'/g, "'\\''");
}

/** Env prefix so tmux pane has TASK_API_* when running status-aware scripts (stream-progress.sh / run-with-status.sh) */
function taskApiEnvPrefix() {
  const url = process.env.TASK_API_URL || 'http://127.0.0.1:8443';
  const token = process.env.TASK_API_TOKEN || 'internal-execute-token';
  return `TASK_API_URL='${shEscapeSingle(url)}' TASK_API_TOKEN='${shEscapeSingle(token)}' `;
}

/** TASK_PHASE env for run-with-status.sh / stream-progress.sh (code|test|done) */
function phaseEnvString(phase) {
  if (phase && ['code', 'test', 'done'].includes(phase)) {
    return `TASK_PHASE='${shEscapeSingle(phase)}' `;
  }
  return '';
}

/**
 * 从 task 与 plan meta 中解析当前阶段应使用的 backend/agent 配置。
 *
 * 优先级（高 → 低）：
 * 1. options.backend （CLI 传入的显式 backend 覆盖）
 * 2. task.metadata.phaseBackends[phase]
 * 3. task.backend
 * 4. planMeta.phaseBackends[phase]
 * 5. planMeta.backend
 *
 * 预留 agentConfig，支持后续为不同阶段配置 model / promptPreset 等参数。
 */
function resolvePhaseBackendConfig(task, options = {}, planMeta = null) {
  const fallbackPhase = task.phase && SUPPORTED_PHASES.includes(task.phase) ? task.phase : 'code';
  const phase = options.phase && SUPPORTED_PHASES.includes(options.phase)
    ? options.phase
    : fallbackPhase;

  const cliBackend = options.backend || null;
  const metadata = task.metadata || {};
  const phaseBackends = metadata.phaseBackends || {};
  const metaPhaseBackends = (planMeta && planMeta.phaseBackends) || {};
  const planBackend = planMeta && planMeta.backend;

  const defaultPhaseConfig = DEFAULT_PHASE_CONFIG[phase] || {};

  const backend =
    cliBackend ||
    phaseBackends[phase] ||
    task.backend ||
    metaPhaseBackends[phase] ||
    planBackend ||
    defaultPhaseConfig.backend ||
    null;

  const phaseConfigs = metadata.phaseConfigs || {};
  const agentConfig =
    phaseConfigs[phase] ||
    metadata.agentConfig ||
    defaultPhaseConfig.agentConfig ||
    {};

  return {
    phase,
    backend,
    agentConfig
  };
}

/**
 * 尝试解析 plan 文件中的 meta 信息（通过 phase-orchestrator 以避免重复实现解析逻辑）
 */
function loadPlanMeta(planPath) {
  if (!planPath || !fs.existsSync(planPath)) return null;
  try {
    const PhaseOrchestrator = require('./phase-orchestrator');
    const orchestrator = new PhaseOrchestrator({ dryRun: true, logger: console });
    const parsed = orchestrator.parsePlanFile(planPath);
    return parsed && parsed.meta ? parsed.meta : null;
  } catch (e) {
    console.log(`   ⚠️  Failed to load plan meta from ${planPath}: ${e.message}`);
    return null;
  }
}

/** Wrap command with run-with-status.sh for status updates (planning→planned, coding→testing, etc.) */
function wrapRunWithStatus(taskId, phase, innerCommand) {
  const runWithStatusPath = path.join(__dirname, 'run-with-status.sh');
  const env = phase === 'plan' ? `TASK_PHASE='plan' ` : phaseEnvString(phase);
  return taskApiEnvPrefix() + env + `bash "${runWithStatusPath}" "${taskId}" -- sh -c ${JSON.stringify(innerCommand)}`;
}

/** CCR phase prompt suffix for plan-based-code-generator */
function ccrPhasePrompt(phase, planPath) {
  const fileRef = planPath ? ` The plan file is located at: ${planPath}.` : '';
  if (phase === 'test') {
    return ` "We are now in the Test phase. Execute the test plan, run tests, and fix any related bugs.${fileRef} Please make sure to check off the corresponding tasks for this phase in the markdown plan file. Do not add new features. Proceed automatically."`;
  }
  if (phase === 'done') {
    return ` "We are now in the Done phase. Review the changes, finalize the code, and auto commit the work.${fileRef} Please write a summary of your analysis and the final results directly into the markdown plan file. Please make sure to check off the corresponding tasks for this phase in the markdown plan file. Proceed automatically."`;
  }
  return ` "Please make sure to check off the corresponding tasks you accomplish in the markdown plan file as you progress.${fileRef} Proceed automatically."`;
}

/**
 * Build agent command based on backend and phase.
 * - plan: generate plan (openclaw-integration generate-plan; cursor wrapped with run-with-status)
 * - code/test/done: execute plan via Cursor / CCR / Claude, with run-with-status or stream-progress for status updates
 */
function buildAgentCommand(backend, taskId, options = {}) {
  const { projectPath, planPath: optPlanPath } = options;
  const phase = options.phase;

  // ---------- phase=plan：生成计划 ----------
  if (phase === 'plan') {
    // cursor & claude: openclaw-integration generate-plan + run-with-status（统一入口，各 backend 内部分发）
    const taskApiUrl = process.env.TASK_API_URL || 'http://127.0.0.1:8443';
    const token = process.env.TASK_API_TOKEN || 'internal-execute-token';
    const integrationPath = path.join(__dirname, 'openclaw-integration.js');
    const baseCmd = `env TASK_VIA_AGENT_START=1 TASK_API_URL="${taskApiUrl}" TASK_API_TOKEN="${token}" node "${integrationPath}" generate-plan "${taskId}" --agent`;
    if (backend === 'cursor' || backend === 'claude') {
      return wrapRunWithStatus(taskId, 'plan', baseCmd);
    }
    return baseCmd;
  }

  // ---------- CCR (claude code)：run-with-status + ccr code ----------
  if (backend === 'ccr') {
    const resolvedPlanPath = optPlanPath || (projectPath ? `${projectPath}/docs/plan-${taskId}.md` : `docs/plan-${taskId}.md`);
    const ccrCmd = `ccr code run --agent --dangerously-skip-permissions plan-based-code-generator${ccrPhasePrompt(phase, resolvedPlanPath)}`;
    const shellCmd = resolvedPlanPath ? `${ccrCmd} < "${resolvedPlanPath}"` : 'ccr code';
    const inner = projectPath ? `cd "${projectPath}" && ${shellCmd}` : shellCmd;
    return wrapRunWithStatus(taskId, phase, inner);
  }

  // ---------- Cursor：stream-progress.sh（需已有 plan 文件） ----------
  if (backend === 'cursor') {
    const resolvedPlanPath = optPlanPath || (projectPath ? `${projectPath}/docs/plan-${taskId}.md` : `docs/plan-${taskId}.md`);
    const streamScript = path.join(__dirname, 'stream-progress.sh');
    return taskApiEnvPrefix() + phaseEnvString(phase) + `bash "${streamScript}" '${resolvedPlanPath}' '${projectPath || '.'}'`;
  }

  // ---------- Claude：stream-progress-claude.sh（与 cursor 同风格） ----------
  if (backend === 'claude') {
    const resolvedPlanPath = optPlanPath || (projectPath ? `${projectPath}/docs/plan-${taskId}.md` : `docs/plan-${taskId}.md`);
    const streamScript = path.join(__dirname, 'stream-progress-claude.sh');
    return taskApiEnvPrefix() + phaseEnvString(phase) + `bash "${streamScript}" '${resolvedPlanPath}' '${projectPath || '.'}'`;
  }

  // ---------- tuxme / 其他 backend ----------
  const baseCommand = backend === 'tuxme'
    ? `tuxme run --task ${taskId} --backend tuxme`
    : `tuxme run --task ${taskId} --backend ${backend}`;
  return projectPath ? `cd "${projectPath}" && ${baseCommand}` : baseCommand;
}

/**
 * 新版统一命令构造：
 * 通过 openclaw-integration 的 run-phase 命令，以 PhaseOrchestrator + UnifiedExecutor 为唯一后端路由入口。
 *
 * - 所有 plan/code/test/done 阶段统一走：
 *   node openclaw-integration.js run-phase <taskId> <phase> [--backend=xxx]
 *
 * 日志路径由 tmux pane 外层控制；此处只关心业务参数。
 */
function buildAgentCommandV2(params) {
  const {
    taskId,
    projectPath,
    phase,
    backend
    // agentConfig 目前预留，不直接参与命令行参数拼接
  } = params;

  const integrationPath = path.join(__dirname, 'openclaw-integration.js');
  const backendArg = backend ? ` --backend=${backend}` : '';

  let baseCmd;

  if (phase === 'plan') {
    // plan 阶段：如果还没有 plan 文件，则应当生成 plan，而不是直接 run-phase。
    // generate-plan 会根据 task.backend 决定使用 cursor/claude/ccr 等，并写入 planPath + 设置 phase=code。
    baseCmd = `node "${integrationPath}" generate-plan "${taskId}" --agent`;
  } else {
    // code/test/done 阶段：统一通过 run-phase 触发 PhaseOrchestrator + UnifiedExecutor。
    // openclaw-integration 会自己读取 planPath / backend / phase 等上下文。
    baseCmd = `node "${integrationPath}" run-phase "${taskId}" "${phase}"${backendArg}`;
  }

  const inner = projectPath ? `cd "${projectPath}" && ${baseCmd}` : baseCmd;

  // 通过 TASK_API_* + TASK_PHASE 让 pane 内命令能与任务系统通信
  const phaseEnv = phase === 'plan' ? '' : phaseEnvString(phase);
  return taskApiEnvPrefix() + phaseEnv + inner;
}


/**
 * Get log directory path
 */
function getLogDir() {
  const logDir = path.join(__dirname, '..', '..', 'logs');
  if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir, { recursive: true });
  }
  return logDir;
}

/**
 * Generate log file path for task
 */
function generateLogPath(taskId) {
  const logDir = getLogDir();
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  return path.join(logDir, `exec-${taskId}-${timestamp}.log`);
}

/**
 * Main function to start agent in tmux
 */
async function startAgent(projectKey, taskId, backend, options = {}) {
  console.log('🚀 Agent Start Skill');
  console.log('='.repeat(40));
  console.log(`   Project: ${projectKey}`);
  console.log(`   Task ID: ${taskId}`);
  console.log(`   Backend: ${backend}`);

  try {
    // Validate inputs
    if (!projectKey || !taskId || !backend) {
      throw new Error('Missing required parameters: projectKey, taskId, backend');
    }

    // Verify task exists
    const task = await tasksStore.getTask(taskId);
    if (!task) {
      throw new Error(`Task not found: ${taskId}`);
    }

    console.log(`   Title: ${task.title}`);
    console.log(`   Current status: ${task.status}`);

    // singleWindow: 同一 window 下多 pane；否则每 task 一个 window
    const singleWindow = options.singleWindow === true;
    const windowTarget = options.window || (singleWindow ? '0' : 'dev');

    // Ensure tmux session exists
    const sessionName = projectKey;
    ensureTmuxSession(sessionName);

    const paneId = singleWindow
      ? createTaskPane(sessionName, windowTarget)
      : createTaskWindow(sessionName, taskId);

    console.log(`\n📍 ${singleWindow ? 'Pane' : 'Window'} allocated: ${paneId}`);

    // Generate log path
    const logPath = generateLogPath(taskId);

    // Resolve project path: explicit option > task.projectPath > ProjectResolver(projectKey)
    let projectPath = options.projectPath
      || task.projectPath
      || task.metadata?.projectPath
      || null;

    if (!projectPath && (task.projectKey || projectKey)) {
      try {
        const ProjectResolver = require('./project-resolver');
        const resolver = new ProjectResolver();
        const resolved = await resolver.resolve(task.projectKey || projectKey);
        if (resolved && resolved.path) {
          projectPath = resolved.path;
        }
      } catch (e) {
        console.log(`   ⚠️  Could not resolve project path from key: ${e.message}`);
      }
    }

    if (projectPath) {
      console.log(`   Project path: ${projectPath}`);
    }

    // Resolve plan path: CLI option > task.planPath > docs/plan-{taskId}.md (phase=plan 时不需要 plan 文件)
    let planPath = options.planPath || task.planPath || task.metadata?.planPath || null;
    const needsPlan = (backend === 'ccr' || backend === 'claude-code' || backend === 'cursor' || backend === 'claude') && options.phase !== 'plan';
    if (!planPath && projectPath && needsPlan) {
      const candidatePlan = path.join(projectPath, 'docs', `plan-${taskId}.md`);
      if (fs.existsSync(candidatePlan)) {
        planPath = candidatePlan;
      } else {
        console.log(`   ⚠️  No plan file found at ${candidatePlan}, will open agent interactively`);
      }
    }
    if (planPath) {
      console.log(`   Plan file: ${planPath}`);
    }

    // 解析 plan meta（如 backend / phaseBackends），并据此解析当前阶段 backend / agent 配置
    const planMeta = loadPlanMeta(planPath);
    const { phase, backend: resolvedBackend, agentConfig } = resolvePhaseBackendConfig(task, {
      phase: options.phase,
      backend
    }, planMeta);

    console.log(`   Resolved phase: ${phase}`);
    console.log(`   Resolved backend: ${resolvedBackend || '(default)'}`);

    // 对于 plan/code/test/done 阶段，统一通过 openclaw-integration run-phase 入口执行；
    // 其他非标准 backend（如 tuxme）仍然走旧的 buildAgentCommand 以保持兼容。
    const useUnifiedEntrance = SUPPORTED_PHASES.includes(phase);

    const command = useUnifiedEntrance
      ? buildAgentCommandV2({
          taskId,
          projectPath,
          phase,
          backend: resolvedBackend,
          agentConfig,
        })
      : buildAgentCommand(backend, taskId, {
          logPath,
          projectPath,
          planPath,
          phase: options.phase,
          prompt: options.prompt,
        });

    // Send command to pane
    spawnInTmuxPane(paneId, command);

    // Update task with tmux metadata (paneId is either %N from createTaskWindow or createTaskPane)
    const tmuxMeta = {
      backend,
      tmuxSession: sessionName,
      tmuxWindow: singleWindow ? windowTarget : taskId,
      tmuxPaneId: paneId,
      lastExecLogPath: logPath
    };

    await tasksStore.updateTmuxMetadata(taskId, tmuxMeta);
    console.log(`\n✅ TMUX metadata saved to task`);

    // Note: Do NOT transition task status here - let the execute-task inside the pane handle it
    // The execute-task-skill will transition from planned -> developing when it starts

    // Output HANDOFF
    const handoff = {
      ok: true,
      skill: 'agent.start',
      version: '1.0',
      data: {
        projectKey,
        taskId,
        title: task.title,
        backend,
        tmux: {
          session: sessionName,
          window: singleWindow ? windowTarget : taskId,
          paneId: paneId
        },
        logPath
      },
      error: null
    };

    console.log(`\nHANDOFF:${JSON.stringify(handoff, null, 2)}`);

    return {
      success: true,
      ...handoff
    };

  } catch (error) {
    console.error(`\n❌ Agent start failed: ${error.message}`);

    const handoff = {
      ok: false,
      skill: 'agent.start',
      version: '1.0',
      data: {
        projectKey,
        taskId,
        backend
      },
      error: error.message
    };

    console.log(`\nHANDOFF:${JSON.stringify(handoff, null, 2)}`);

    return {
      success: false,
      ...handoff
    };
  }
}

// ---------- CLI Interface ----------

if (require.main === module) {
  (async () => {
    const args = process.argv.slice(2);
    const command = args[0];

    if (command === 'start') {
      const projectKey = args[1];
      const taskId = args[2];
      const backend = args[3];

      const windowArg = args.find(a => a.startsWith('--window='));
      const window = windowArg ? windowArg.split('=')[1] : 'dev';

      const planArg = args.find(a => a.startsWith('--plan='));
      const plan = planArg ? planArg.split('=')[1] : null;

      const phaseArg = args.find(a => a.startsWith('--phase='));
      const phase = phaseArg ? phaseArg.split('=')[1] : null;

      const singleWindow = args.includes('--single-window');

      if (!projectKey || !taskId || !backend) {
        console.log('Usage: node agent-start-skill.js start <projectKey> <taskId> <backend> [options]');
        console.log('');
        console.log('Arguments:');
        console.log('  projectKey   Project key (e.g., xassistant)');
        console.log('  taskId       Task ID (e.g., TASK-20260304-123)');
        console.log('  backend      Backend type (tuxme, cursor, claude)');
        console.log('');
        console.log('Options:');
        console.log('  --window=<name>   Window name or index (default: dev, or 0 when --single-window)');
        console.log('  --single-window    One window per project, each task in a new pane');
        console.log('  --plan=<path>      Path to plan file');
        console.log('  --phase=<phase>   Phase (e.g. test, done)');
        console.log('');
        console.log('Examples:');
        console.log('  node agent-start-skill.js start xassistant TASK-20260304-123 tuxme');
        console.log('  node agent-start-skill.js start xassistant TASK-20260304-123 cursor --single-window');
        process.exit(1);
      }

      try {
        await startAgent(projectKey, taskId, backend, { window, planPath: plan, phase, singleWindow });
        process.exit(0);
      } catch (error) {
        console.error(`Error: ${error.message}`);
        process.exit(1);
      }
    } else {
      console.log('📋 Agent Start Skill');
      console.log('='.repeat(40));
      console.log('');
      console.log('Available commands:');
      console.log('  start <projectKey> <taskId> <backend> [options]');
      console.log('      Start an agent in tmux for the specified task');
      console.log('');
      console.log('Options:');
      console.log('  --single-window    One window per project; each task runs in a new pane');
      console.log('  --window=<name>    Window name or index (default: dev, or 0 with --single-window)');
      console.log('  --plan=<path>      Path to the plan file to execute');
      console.log('  --phase=<phase>    Phase: test, done, etc.');
      console.log('');
      console.log('Description:');
      console.log('  Creates a tmux session per project if not exists.');
      console.log('  Without --single-window: one new window per task (window name = taskId).');
      console.log('  With --single-window: one window per project, each task in a new pane.');
      console.log('  Updates task metadata with tmux session/window/pane info.');
    }
  })();
}

module.exports = {
  startAgent,
  ensureTmuxSession,
  createTaskWindow,
  createTaskPane,
  spawnInTmuxPane,
  buildAgentCommand,
  buildAgentCommandV2,
  taskApiEnvPrefix,
  phaseEnvString,
  shEscapeSingle,
  resolvePhaseBackendConfig,
  loadPlanMeta
};