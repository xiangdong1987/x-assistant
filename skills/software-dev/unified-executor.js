#!/usr/bin/env node

/**
 * Unified Development Executor with Backend Abstraction
 *
 * Provides a unified interface for development workflows with configurable backends.
 * Supports both Claude Code and Cursor CLI backends through a common interface.
 *
 * Backend Interface:
 * - generatePlan(taskId, projectPath, options): Promise<PlanResult>
 * - executePlan(taskId, projectPath, options): Promise<ExecutionResult>
 * - getCLICommand(): string
 * - getStepLabel(): string
 * - validateInstallation(): Promise<boolean>
 */

const fs = require('fs');
const path = require('path');
const { spawn, execSync } = require('child_process');
const { loadConfig } = require('./config-loader');

// ---------- Configuration ----------

/**
 * Get backend configuration
 */
function getBackendConfig(backendName) {
    const config = loadConfig();
    const backend = backendName || config.settings?.defaultBackend || 'claude';

    const backendConfigs = {
        claude: {
            cliCommand: config.settings?.claudeCliCommand || 'claude',
            stepLabel: 'Claude CLI',
            planCommand: '--mode=plan',
            timeoutMs: config.settings?.planTimeoutMs || 180000,
            executionTimeoutMs: config.settings?.executionTimeoutMs || 600000
        },
        ccr: {
            cliCommand: 'ccr',
            stepLabel: 'CCR',
            planCommand: '--mode=plan',
            timeoutMs: config.settings?.planTimeoutMs || 180000,
            executionTimeoutMs: config.settings?.executionTimeoutMs || 600000
        },
        cursor: {
            cliCommand: config.settings?.cursorCliCommand || 'agent',
            stepLabel: 'Cursor CLI',
            planCommand: '--mode=plan',
            timeoutMs: config.settings?.cursorPlanTimeoutMs || 180000,
            executionTimeoutMs: config.settings?.cursorCliTimeoutMs || 600000
        }
    };

    return backendConfigs[backend] || backendConfigs.claude;
}

// ---------- Logger ----------

/**
 * Create logger for execution tracking
 */
function createLogger(logPath) {
    if (!logPath) return null;

    const logDir = path.dirname(logPath);
    if (!fs.existsSync(logDir)) {
        fs.mkdirSync(logDir, { recursive: true });
    }

    const stream = fs.createWriteStream(logPath, { flags: 'a' });
    const ts = () => new Date().toISOString();

    function writeToFile(level, msg) {
        const line = `${ts()} [${level}] ${msg}\n`;
        stream.write(line);
    }

    return {
        log(msg) {
            process.stdout.write(msg + '\n');
            writeToFile('LOG', msg);
        },
        warn(msg) {
            process.stderr.write(msg + '\n');
            writeToFile('WARN', msg);
        },
        error(msg) {
            process.stderr.write(msg + '\n');
            writeToFile('ERROR', msg);
        },
        markCliStart(stepLabel, backendLabel) {
            const line = `\n${ts()} --- ${backendLabel} ${stepLabel} ---\n`;
            stream.write(line);
        },
        logPrompt(prompt, label = 'Prompt') {
            const maxLen = 8000;
            const preview = prompt.length > maxLen
                ? prompt.slice(0, maxLen) + `\n\n... [truncated, full length ${prompt.length} chars]`
                : prompt;
            stream.write(`\n${ts()} --- ${label} ---\n${preview}\n${ts()} --- ${label} end ---\n\n`);
        },
        logFullCommand(fullCommandLine) {
            stream.write(`\n${ts()} --- Full CLI Command (for replay) ---\n${fullCommandLine}\n${ts()} --- Full CLI Command end ---\n\n`);
        },
        getLogWriter() {
            let stderrStarted = false;
            return {
                writeStdout(chunk) { stream.write(chunk); },
                writeStderr(chunk) {
                    if (!stderrStarted) {
                        stream.write(`\n${ts()} --- [STDERR] ---\n`);
                        stderrStarted = true;
                    }
                    stream.write(chunk);
                }
            };
        },
        close() {
            return new Promise((resolve) => {
                stream.once('finish', resolve);
                stream.end();
            });
        }
    };
}

/**
 * Normalize any logger-like object to the full logger interface expected by
 * UnifiedExecutor/backends.
 *
 * This keeps plain `console` usable, while still preserving richer loggers
 * created by createLogger().
 */
function normalizeLogger(logger) {
    if (!logger) return null;

    const baseLog = typeof logger.log === 'function'
        ? logger.log.bind(logger)
        : console.log.bind(console);
    const baseWarn = typeof logger.warn === 'function'
        ? logger.warn.bind(logger)
        : console.warn.bind(console);
    const baseError = typeof logger.error === 'function'
        ? logger.error.bind(logger)
        : console.error.bind(console);

    return {
        ...logger,
        log: baseLog,
        warn: baseWarn,
        error: baseError,
        markCliStart: typeof logger.markCliStart === 'function'
            ? logger.markCliStart.bind(logger)
            : () => {},
        logPrompt: typeof logger.logPrompt === 'function'
            ? logger.logPrompt.bind(logger)
            : (prompt, label = 'Prompt') => {
                const text = String(prompt || '');
                const maxLen = 2000;
                const preview = text.length > maxLen
                    ? text.slice(0, maxLen) + `\n\n... [truncated, full length ${text.length} chars]`
                    : text;
                baseLog(`--- ${label} ---\n${preview}\n--- ${label} end ---`);
            },
        logFullCommand: typeof logger.logFullCommand === 'function'
            ? logger.logFullCommand.bind(logger)
            : (fullCommandLine) => baseLog(`Full CLI Command: ${fullCommandLine}`),
        getLogWriter: typeof logger.getLogWriter === 'function'
            ? logger.getLogWriter.bind(logger)
            : () => ({
                writeStdout(chunk) { process.stdout.write(chunk); },
                writeStderr(chunk) { process.stderr.write(chunk); }
            }),
        close: typeof logger.close === 'function'
            ? logger.close.bind(logger)
            : async () => {}
    };
}

// ---------- CLI Execution ----------

/**
 * Execute CLI command with timeout and logging
 * Supports commands with subcommands like "ccr code"
 */
function resolveCommandPath(command) {
    const [base] = String(command).split(/\s+/);
    try {
        const which = process.platform === 'win32' ? 'where' : 'which';
        return execSync(`${which} ${base}`, { encoding: 'utf8' }).trim().split(/\r?\n/)[0];
    } catch {
        return base;
    }
}

function buildFullCommandLine(command, args) {
    const cmdParts = String(command).split(/\s+/);
    const base = cmdParts[0];
    const prefixArgs = cmdParts.slice(1);
    const allArgs = [...prefixArgs, ...args];
    const fullPath = resolveCommandPath(base);
    const escapedArgs = allArgs.map(a => {
        const s = String(a);
        if (s.includes('\n') || s.includes(' ') || s.includes('"') || s.includes("'")) {
            // 展示时用简短预览，避免日志中出现 \012 等转义且难以阅读
            const preview = s.includes('\n')
                ? s.split('\n')[0].slice(0, 60) + (s.length > 60 ? '...' : '') + ' [prompt ' + s.length + ' chars]'
                : s.slice(0, 80) + (s.length > 80 ? '...' : '');
            return '"' + preview.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
        }
        return s;
    });
    return `${fullPath} ${escapedArgs.join(' ')}`;
}

async function runCLI(command, args, options = {}) {
    const {
        cwd = process.cwd(),
        timeout = 600000,
        logger = null,
        label = 'CLI Execution',
        stdin = null
    } = options;

    return new Promise((resolve, reject) => {
        const fullCommandLine = buildFullCommandLine(command, args);
        console.log(`🚀 ${label}: ${fullCommandLine}`);
        if (logger) {
            logger.markCliStart(label, command);
            logger.logFullCommand(fullCommandLine);
        }

        const cmdParts = String(command).split(/\s+/);
        const base = cmdParts[0];
        const prefixArgs = cmdParts.slice(1);
        const allArgs = [...prefixArgs, ...args];

        const env = { ...process.env };
        const cmdDir = path.dirname(resolveCommandPath(base));
        if (process.platform === 'win32') {
            env.Path = `${cmdDir};${env.Path || ''}`;
        } else {
            env.PATH = `${cmdDir}:${env.PATH || ''}`;
        }

        const child = spawn(base, allArgs, {
            cwd,
            stdio: ['pipe', 'pipe', 'pipe'],
            env
        });

        // Write stdin if provided (for pipelines like: echo "prompt" | ccr code run ...)
        if (stdin && child.stdin) {
            child.stdin.write(String(stdin));
            child.stdin.end();
        }

        let stdout = '';
        let stderr = '';
        const logWriter = logger ? logger.getLogWriter() : null;

        child.stdout.on('data', (data) => {
            const chunk = data.toString();
            stdout += chunk;
            if (logWriter) {
                logWriter.writeStdout(chunk);
            } else {
                process.stdout.write(chunk);
            }
        });

        child.stderr.on('data', (data) => {
            const chunk = data.toString();
            stderr += chunk;
            if (logWriter) {
                logWriter.writeStderr(chunk);
            } else {
                process.stderr.write(chunk);
            }
        });

        const timeoutId = setTimeout(() => {
            child.kill('SIGTERM');
            reject(new Error(`Command timeout after ${timeout}ms`));
        }, timeout);

        child.on('close', (code) => {
            clearTimeout(timeoutId);

            if (code === 0) {
                resolve({ code, stdout, stderr });
            } else {
                const error = new Error(`Command failed with code ${code}: ${stderr}`);
                error.code = code;
                error.stdout = stdout;
                error.stderr = stderr;
                reject(error);
            }
        });

        child.on('error', (error) => {
            clearTimeout(timeoutId);
            reject(error);
        });
    });
}

// ---------- Backend Interface ----------

/**
 * Base backend class with common functionality
 */
class DevelopmentBackend {
    constructor(config) {
        this.config = config;
        this.cliCommand = config.cliCommand;
        this.stepLabel = config.stepLabel;
        this.planCommand = config.planCommand;
        this.timeoutMs = config.timeoutMs;
        this.executionTimeoutMs = config.executionTimeoutMs;
    }

    async validateInstallation() {
        try {
            if (this.cliCommand === 'ccr') {    
                const result = await runCLI(this.cliCommand, ['code', '--version'], {
                    timeout: 10000,
                    label: `${this.stepLabel} version check`
                });
                return result.stdout.trim();
            } else {
                const result = await runCLI(this.cliCommand, ['--version'], {
                    timeout: 10000,
                    label: `${this.stepLabel} version check`
                });
                return result.stdout.trim();
            }
        } catch (error) {
            console.error(`❌ ${this.stepLabel} not found or not working: ${error.message}`);
            console.error(`   Please install ${this.stepLabel} and ensure it's in PATH`);
            return false;
        }
    }

    getCLICommand() {
        return this.cliCommand;
    }

    getStepLabel() {
        return this.stepLabel;
    }

    async generatePlan(taskId, projectPath, options = {}) {
        throw new Error('generatePlan must be implemented by subclass');
    }

    async executePlan(taskId, projectPath, options = {}) {
        throw new Error('executePlan must be implemented by subclass');
    }

    /**
     * Common plan generation logic
     */
    async _generatePlanCommon(taskId, projectPath, prompt, options = {}) {
        const { logger = null, skipExecute = false } = options;

        console.log(`📋 Generating plan for task ${taskId} in ${projectPath}`);
        console.log(`   Using: ${this.stepLabel}`);

        if (logger) {
            logger.logPrompt(prompt, 'Plan Generation Prompt');
        }

        const planArgs = [];
        if (this.cliCommand === 'ccr') {
            planArgs.push('code');
        }
        planArgs.push(this.planCommand, '-p', prompt);
        if (skipExecute) {
            planArgs.push('--skip-execute');
        }

        try {
            const result = await runCLI(this.cliCommand, planArgs, {
                cwd: projectPath,
                timeout: this.timeoutMs,
                logger,
                label: `${this.stepLabel} Plan Generation`
            });

            return {
                success: true,
                taskId,
                projectPath,
                stdout: result.stdout,
                stderr: result.stderr,
                backend: this.stepLabel
            };
        } catch (error) {
            return {
                success: false,
                taskId,
                projectPath,
                error: error.message,
                stdout: error.stdout,
                stderr: error.stderr,
                backend: this.stepLabel
            };
        }
    }

    /**
     * Common plan execution logic
     */
    async _executePlanCommon(taskId, projectPath, planFilePath, options = {}) {
        const { logger = null } = options;

        console.log(`⚡ Executing plan for task ${taskId} in ${projectPath}`);
        console.log(`   Plan file: ${planFilePath}`);
        console.log(`   Using: ${this.stepLabel}`);

        const planContent = fs.readFileSync(planFilePath, 'utf-8');
        if (logger) {
            logger.logPrompt(planContent, 'Plan Execution Prompt');
        }

        const executeArgs = [];
        if (this.cliCommand === 'ccr') {
            executeArgs.push('code');
        }
        executeArgs.push('-p', planContent);

        try {
            const result = await runCLI(this.cliCommand, executeArgs, {
                cwd: projectPath,
                timeout: this.executionTimeoutMs,
                logger,
                label: `${this.stepLabel} Plan Execution`
            });

            return {
                success: true,
                taskId,
                projectPath,
                stdout: result.stdout,
                stderr: result.stderr,
                backend: this.stepLabel
            };
        } catch (error) {
            return {
                success: false,
                taskId,
                projectPath,
                error: error.message,
                stdout: error.stdout,
                stderr: error.stderr,
                backend: this.stepLabel
            };
        }
    }
}

// ---------- Backend Factory ----------

/**
 * Create backend instance based on name
 */
function createBackend(backendName = null) {
    const config = loadConfig();
    const backend = backendName || config.settings?.defaultBackend || 'claude';
    const backendConfig = getBackendConfig(backend);

    let BackendClass;
    try {
        if (backend === 'cursor') {
            BackendClass = require('./cursor-backend.js');
        } else {
            // claude / ccr 均使用 claude-backend（ccr 通过 config.cliCommand 区分）
            BackendClass = require('./claude-backend.js');
        }
    } catch (error) {
        console.warn(`⚠️ Backend module not found for ${backend}, using base class`);
        BackendClass = DevelopmentBackend;
    }

    return new BackendClass(backendConfig);
}

// ---------- Unified Executor ----------

/**
 * Unified executor for development workflows
 */
class UnifiedExecutor {
    constructor(options = {}) {
        this.backend = createBackend(options.backend);
        this.logger = normalizeLogger(options.logger);
        this.config = loadConfig();
    }

    /**
     * Validate backend installation
     */
    async validate() {
        return await this.backend.validateInstallation();
    }

    /**
     * Generate plan for a task
     */
    async generatePlan(taskId, projectPath, options = {}) {
        const mergedOptions = { ...options, logger: this.logger };
        return await this.backend.generatePlan(taskId, projectPath, mergedOptions);
    }

    /**
     * Execute plan for a task
     */
    async executePlan(taskId, projectPath, options = {}) {
        const mergedOptions = { ...options, logger: this.logger };
        return await this.backend.executePlan(taskId, projectPath, mergedOptions);
    }

    /**
     * Full workflow: generate and execute plan
     */
    async fullWorkflow(taskId, projectPath, options = {}) {
        console.log(`🚀 Starting full workflow for task ${taskId}`);
        console.log(`   Backend: ${this.backend.getStepLabel()}`);
        console.log(`   Project: ${projectPath}`);

        // Generate plan
        const planResult = await this.generatePlan(taskId, projectPath, options);
        if (!planResult.success) {
            console.error(`❌ Plan generation failed: ${planResult.error}`);
            return planResult;
        }

        console.log(`✅ Plan generated successfully`);

        // Execute plan
        const executeResult = await this.executePlan(taskId, projectPath, options);
        if (!executeResult.success) {
            console.error(`❌ Plan execution failed: ${executeResult.error}`);
            return executeResult;
        }

        console.log(`✅ Plan executed successfully`);

        return {
            success: true,
            taskId,
            projectPath,
            backend: this.backend.getStepLabel(),
            planResult,
            executeResult
        };
    }

    /**
     * Get current backend information
     */
    getBackendInfo() {
        return {
            name: this.backend.getStepLabel(),
            cliCommand: this.backend.getCLICommand(),
            config: this.backend.config
        };
    }
}

// ---------- Phase Executor (per-backend, phase-oriented) ----------

/**
 * Phase-oriented executor that reuses UnifiedExecutor under the hood.
 * Exposes a simple executePhase(task, phase, options) interface to orchestration code.
 */
class PhaseExecutor {
    constructor(options = {}) {
        this.backendName = options.backendName || null;
        this.logger = normalizeLogger(options.logger);
    }

    /**
     * Execute a single phase (code/test/done) for the given task.
     * Required options:
     * - projectPath: absolute path to project root
     * - planPath: path to plan markdown file
     */
    async executePhase(task, phase, options = {}) {
        const supportedPhases = ['code', 'test', 'done'];
        if (!supportedPhases.includes(phase)) {
            throw new Error(`PhaseExecutor does not support phase: ${phase}`);
        }

        const projectPath = options.projectPath;
        const planPath = options.planPath || task.planPath;

        if (!projectPath) {
            throw new Error('PhaseExecutor.executePhase requires projectPath');
        }
        if (!planPath) {
            throw new Error('PhaseExecutor.executePhase requires planPath');
        }

        const backendName = this.backendName || task.backend || null;
        const executor = new UnifiedExecutor({
            backend: backendName,
            logger: this.logger
        });

        const isValid = await executor.validate();
        if (!isValid) {
            return { success: false, error: 'Backend validation failed' };
        }

        const taskId = task.taskId || task.id;

        try {
            const executeResult = await executor.executePlan(taskId, projectPath, {
                planPath,
                phase,
                ...options
            });

            if (!executeResult.success) {
                return {
                    success: false,
                    error: executeResult.error,
                    executeResult
                };
            }

            return {
                success: true,
                executeResult
            };
        } catch (error) {
            return {
                success: false,
                error: error.message,
                executeResult: null
            };
        }
    }
}

// ---------- Tmux Phase Executor (fire-and-forget via tmux) ----------

/**
 * TmuxPhaseExecutor wraps phase execution inside a dedicated tmux pane.
 *
 * It sends `openclaw-integration run-phase` with AGENT_TMUX_WRAPPED=1 to a new
 * tmux window/pane, so the inner process uses PhaseExecutor (direct CLI) and
 * never re-enters TmuxPhaseExecutor — avoiding recursion.
 *
 * executePhase() returns { success: true, async: true } immediately.
 * The actual work (backend CLI call, plan checklist updates, advancePhase) all
 * happen inside the tmux pane's own Node.js process.
 */
class TmuxPhaseExecutor {
    constructor(options = {}) {
        this.backendName = options.backendName || null;
        this.logger = normalizeLogger(options.logger);
    }

    _log(msg) {
        if (this.logger && this.logger.log) this.logger.log(msg);
        else console.log(msg);
    }

    async executePhase(task, phase, options = {}) {
        const {
            ensureTmuxSession,
            createTaskWindow,
            spawnInTmuxPane,
            buildAgentCommand
        } = require('./agent-start-skill');

        const taskId = task.taskId || task.id;
        const sessionName = task.projectKey;
        if (!sessionName) {
            throw new Error('TmuxPhaseExecutor requires task.projectKey for tmux session name');
        }

        const backendName = this.backendName || task.backend || null;
        const projectPath = options.projectPath || task.projectPath || null;
        const planPath = options.planPath || task.planPath || null;

        // Use the original agent-start streaming shell path so tmux panes show
        // live agent output instead of wrapping another run-phase process.
        const fullCmd = buildAgentCommand(backendName, taskId, {
            projectPath,
            planPath,
            phase
        });

        this._log(`[TmuxPhaseExecutor] phase=${phase} session=${sessionName} backend=${backendName || 'default'}`);
        ensureTmuxSession(sessionName);
        const windowName = `${taskId}-${phase}`;
        const paneId = createTaskWindow(sessionName, windowName);
        spawnInTmuxPane(paneId, fullCmd);

        // Persist tmux metadata to the task record for observability
        try {
            const tasksStore = require('./tasks-store-adapter');
            await tasksStore.updateTmuxMetadata(taskId, {
                tmuxSession: sessionName,
                tmuxWindow: windowName,
                tmuxPaneId: paneId,
                phase
            });
        } catch (e) {
            this._log(`[TmuxPhaseExecutor] Warning: could not update tmux metadata: ${e.message}`);
        }

        return { success: true, async: true, paneId };
    }
}

/**
 * Factory to create PhaseExecutor instances for a given backend.
 *
 * When config.settings.useTmuxForBackend is true AND the current process is NOT
 * already running inside a tmux-wrapped execution (AGENT_TMUX_WRAPPED=1), a
 * TmuxPhaseExecutor is returned so the phase runs in a dedicated tmux pane.
 */
function createPhaseExecutor(backendName = null, logger = null) {
    const config = loadConfig();
    const useTmux = config.settings?.useTmuxForBackend && !process.env.AGENT_TMUX_WRAPPED;
    if (useTmux) {
        return new TmuxPhaseExecutor({ backendName, logger });
    }
    return new PhaseExecutor({ backendName, logger });
}

// ---------- Exports ----------

module.exports = {
    UnifiedExecutor,
    DevelopmentBackend,
    createBackend,
    createLogger,
    normalizeLogger,
    runCLI,
    loadConfig,
    getBackendConfig,
    PhaseExecutor,
    TmuxPhaseExecutor,
    createPhaseExecutor
};

// ---------- CLI Interface ----------

if (require.main === module) {
    (async () => {
        const args = process.argv.slice(2);
        const command = args[0];

        if (command === 'test-backend') {
            const backendName = args[1] || 'claude';
            console.log(`🧪 Testing ${backendName} backend...`);

            const backend = createBackend(backendName);
            const isValid = await backend.validateInstallation();

            if (isValid) {
                console.log(`✅ ${backend.getStepLabel()} is properly installed`);
                process.exit(0);
            } else {
                console.error(`❌ ${backend.getStepLabel()} installation check failed`);
                process.exit(1);
            }
        } else if (command === 'info') {
            const backendName = args[1] || null;
            const backend = createBackend(backendName);
            const info = backend.getBackendInfo ? await backend.getBackendInfo() : backend.getStepLabel();

            console.log('📊 Backend Information:');
            console.log(JSON.stringify(info, null, 2));
        } else {
            console.log('📋 Unified Executor CLI');
            console.log('='.repeat(40));
            console.log('Available commands:');
            console.log('  test-backend [claude|cursor]  - Test backend installation');
            console.log('  info [claude|cursor]          - Show backend information');
            console.log('');
            console.log('Usage as module:');
            console.log('  const { UnifiedExecutor } = require("./unified-executor");');
            console.log('  const executor = new UnifiedExecutor({ backend: "cursor" });');
            console.log('  await executor.fullWorkflow(taskId, projectPath);');
        }
    })().catch(error => {
        console.error(`❌ CLI error: ${error.message}`);
        process.exit(1);
    });
}