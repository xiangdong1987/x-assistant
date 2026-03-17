#!/usr/bin/env node

/**
 * Claude Code Backend Implementation
 *
 * Implements the DevelopmentBackend interface for Claude Code CLI.
 * Provides specific logic for plan generation and execution using Claude CLI.
 */

const path = require('path');
const fs = require('fs');
const { DevelopmentBackend } = require('./unified-executor.js');
const { runCLI } = require('./unified-executor.js');

// ---------- Prompts ----------

const DEFAULT_PLAN_PROMPT = (taskId, title, description) => `
Task ID: ${taskId}
Title: ${title}
Description: ${description}

Please generate a comprehensive development plan for this task. The plan should include:
1. Analysis of current codebase structure
2. Implementation approach and architecture decisions
3. Detailed step-by-step implementation plan
4. Testing strategy
5. Potential risks and mitigation strategies

Please write the plan to a file at docs/plan-${taskId}.md following the project's plan template format.
`.trim();

// ---------- Claude Backend Class ----------

class ClaudeBackend extends DevelopmentBackend {
    constructor(config) {
        super(config);
        this.backendName = 'claude';
    }

    /**
     * Generate plan using Claude CLI / CCR
     *
     * 当 cliCommand === "ccr" 时，等价于：
     *   ccr 不支持 --output，通过 prompt 要求 agent 将计划写入 docs/plan-{taskId}.md
     */
    async generatePlan(taskId, projectPath, options = {}) {
        const {
            title = '',
            description = '',
            logger = null,
            skipExecute = false,
        } = options;

        console.log(`📋 Generating plan for task ${taskId}`);
        console.log(`   Backend: ${this.stepLabel}`);
        console.log(`   Project: ${projectPath}`);

        const relPlanPath = path.join('docs', `plan-${taskId}.md`);
        const absPlanPath = path.join(projectPath, relPlanPath);
        const docsDir = path.dirname(absPlanPath);

        if (!fs.existsSync(docsDir)) {
            fs.mkdirSync(docsDir, { recursive: true });
        }

        const basePrompt =
            options.prompt ||
            `生成针对任务「${title}」的详细开发计划：${description || title}`;
        const prompt =
            this.cliCommand === 'ccr'
                ? `${basePrompt}\n\n请将完整计划写入项目内的文件：${relPlanPath}（相对项目根目录），然后结束。不要执行任何代码或测试，只生成并保存计划文件。`
                : basePrompt;

        if (logger) {
            logger.logPrompt(prompt, 'Claude Plan Generation Prompt');
        }

        let args;
        let stdinForPlan = null;
        if (this.cliCommand === 'ccr') {
            // ccr：通过 stdin 传入 prompt，避免长参数与换行转义（\012）导致的问题
            args = [
                'code',
                'run',
                '--agent',
                'plan-based-code-generator',
                '--dangerously-skip-permissions',
            ];
            stdinForPlan = prompt;
        } else {
            // Fallback: plain Claude CLI (may not支持 --mode=plan 的老版本)
            args = ['--mode=plan', '-p', prompt];
            if (skipExecute) {
                args.push('--skip-execute');
            }
        }

        try {
            const result = await runCLI(this.cliCommand, args, {
                cwd: projectPath,
                timeout: this.timeoutMs,
                logger,
                label: `${this.stepLabel} Plan Generation`,
                stdin: stdinForPlan,
            });

            if (!fs.existsSync(absPlanPath)) {
                throw new Error(`Plan file not created at ${absPlanPath}`);
            }

            return {
                success: true,
                taskId,
                projectPath,
                planPath: absPlanPath,
                stdout: result.stdout,
                stderr: result.stderr,
                backend: this.stepLabel,
            };
        } catch (error) {
            return {
                success: false,
                taskId,
                projectPath,
                error: error.message,
                stdout: error.stdout || '',
                stderr: error.stderr || '',
                backend: this.stepLabel,
            };
        }
    }

    /**
     * Execute plan using Claude CLI
     */
    async executePlan(taskId, projectPath, options = {}) {
        const {
            planPath = null,
            prompt = null,
            logger = null
        } = options;

        console.log(`⚡ Executing plan for task ${taskId}`);
        console.log(`   Backend: ${this.stepLabel}`);
        console.log(`   Project: ${projectPath}`);

        if (!planPath && !prompt) {
            return {
                success: false,
                taskId,
                projectPath,
                error: 'Either planPath or prompt must be provided',
                backend: this.stepLabel
            };
        }

        // CCR 路径：等价于 `ccr code run --agent plan-based-code-generator  < planPath`
        console.log(`CCR Plan Path: ${planPath}`);
        if (this.cliCommand === 'ccr' && planPath) {
            if (!fs.existsSync(planPath)) {
                return {
                    success: false,
                    taskId,
                    projectPath,
                    error: `Plan file not found: ${planPath}`,
                    backend: this.stepLabel
                };
            }
            const planContent = fs.readFileSync(planPath, 'utf-8');
            if (logger) {
                logger.logPrompt(planContent, 'CCR Plan Content (from file)');
            }
            const args = ['code', 'run', '--agent', 'plan-based-code-generator'];
            try {
                const result = await runCLI(this.cliCommand, args, {
                    cwd: projectPath,
                    timeout: this.executionTimeoutMs,
                    logger,
                    label: `${this.stepLabel} Plan Execution (CCR)`,
                    stdin: planContent
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
                    stdout: error.stdout || '',
                    stderr: error.stderr || '',
                    backend: this.stepLabel
                };
            }
        }

        // 传统 Claude CLI：仍然使用 -p "<prompt>" 方式
        const executePrompt = prompt || (() => {
            const planContent = fs.readFileSync(planPath, 'utf-8');
            return [
                '## ⚠️ 执行范围约束（必须遵守）',
                '- 仅实现计划中明确列出的内容，不要添加计划之外的「优化」「改进」「额外功能」',
                '- 不要自行扩展需求或增加未在计划中的步骤',
                '- 若计划有歧义，严格按最小实现完成，不要过度设计',
                '',
                '---',
                '',
                planContent
            ].join('\n');
        })();

        if (logger) {
            logger.logPrompt(executePrompt, 'Claude Execution Prompt');
        }

        const args = ['-p', executePrompt];

        try {
            const result = await runCLI(this.cliCommand, args, {
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
                stdout: error.stdout || '',
                stderr: error.stderr || '',
                backend: this.stepLabel
            };
        }
    }

    /**
     * Get backend information
     */
    async getBackendInfo() {
        let version = 'unknown';

        try {
            if (this.cliCommand === 'ccr') {
                const result = await runCLI(this.cliCommand, ['code', '--version'], {
                    timeout: 10000,
                    label: `${this.stepLabel} Version Check`
                });
                version = result.stdout.trim();
            } else {
                const result = await runCLI(this.cliCommand, ['--version'], {
                    timeout: 10000,
                    label: `${this.stepLabel} Version Check`
                });
                version = result.stdout.trim();
            }
        } catch (error) {
            version = `Error: ${error.message}`;
        }

        return {
            name: 'Claude Code',
            backendName: 'claude',
            cliCommand: this.cliCommand,
            stepLabel: this.stepLabel,
            version,
            config: this.config,
            features: [
                'Plan generation with --mode=plan',
                'Plan execution with direct prompt',
                'Native codebase understanding',
                'File editing capabilities'
            ]
        };
    }

    /**
     * Validate Claude CLI installation and setup
     */
    async validateInstallation() {
        try {
            if (this.cliCommand === 'ccr') {    
            // Check if claude command is available
                await runCLI(this.cliCommand, ['code', '--version'], {
                    timeout: 10000,
                    label: `${this.stepLabel} Version Check`
                });
            } else {
                await runCLI(this.cliCommand, ['--version'], {
                    timeout: 10000,
                    label: `${this.stepLabel} Version Check`
                });
            }

            if (this.cliCommand === 'ccr') {
                await runCLI(this.cliCommand, ['code', '--help'], {
                    timeout: 10000,
                    label: `${this.stepLabel} Help Check`
                });
            } else {
                await runCLI(this.cliCommand, ['--help'], {
                    timeout: 10000,
                    label: `${this.stepLabel} Help Check`
                });
            }

            console.log(`✅ ${this.stepLabel} is properly installed and working`);
            return true;
        } catch (error) {
            console.error(`❌ ${this.stepLabel} validation failed: ${error.message}`);
            console.error(`   Please ensure Claude Code CLI is installed and configured`);
            console.error(`   Visit: https://claude.ai/claude-code`);
            return false;
        }
    }
}

// ---------- Exports ----------

module.exports = ClaudeBackend;

// ---------- CLI Interface ----------

if (require.main === module) {
    (async () => {
        const args = process.argv.slice(2);
        const command = args[0];

        const { getBackendConfig } = require('./unified-executor.js');
        const backendConfig = getBackendConfig('claude');
        const backend = new ClaudeBackend(backendConfig);

        if (command === 'test') {
            console.log('🧪 Testing Claude CLI backend...');
            const isValid = await backend.validateInstallation();

            if (isValid) {
                process.exit(0);
            } else {
                process.exit(1);
            }
        } else if (command === 'info') {
            const info = await backend.getBackendInfo();
            console.log('📊 Claude CLI Backend Information:');
            console.log(JSON.stringify(info, null, 2));
        } else if (command === 'generate-plan') {
            const taskId = args[1];
            const projectPath = args[2];
            const title = args[3] || '';
            const description = args[4] || '';

            if (!taskId || !projectPath) {
                console.log('Usage: node claude-backend.js generate-plan <taskId> <projectPath> [title] [description]');
                process.exit(1);
            }

            const result = await backend.generatePlan(taskId, projectPath, { title, description });

            if (result.success) {
                console.log('✅ Plan generated successfully');
                console.log(`   Plan path: ${result.planPath}`);
                process.exit(0);
            } else {
                console.error(`❌ Plan generation failed: ${result.error}`);
                process.exit(1);
            }
        } else if (command === 'execute-plan') {
            const taskId = args[1];
            const projectPath = args[2];
            const planPath = args[3];

            if (!taskId || !projectPath || !planPath) {
                console.log('Usage: node claude-backend.js execute-plan <taskId> <projectPath> <planPath>');
                process.exit(1);
            }

            const result = await backend.executePlan(taskId, projectPath, { planPath });

            if (result.success) {
                console.log('✅ Plan executed successfully');
                process.exit(0);
            } else {
                console.error(`❌ Plan execution failed: ${result.error}`);
                process.exit(1);
            }
        } else {
            console.log('📋 Claude CLI Backend CLI');
            console.log('='.repeat(40));
            console.log('Available commands:');
            console.log('  test                        - Test Claude CLI installation');
            console.log('  info                        - Show backend information');
            console.log('  generate-plan <taskId> <projectPath> [title] [description]');
            console.log('                              - Generate plan for a task');
            console.log('  execute-plan <taskId> <projectPath> <planPath>');
            console.log('                              - Execute plan for a task');
        }
    })().catch(error => {
        console.error(`❌ CLI error: ${error.message}`);
        process.exit(1);
    });
}