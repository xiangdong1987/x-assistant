#!/usr/bin/env node

/**
 * Cursor CLI Backend Implementation
 *
 * Implements DevelopmentBackend interface for Cursor CLI.
 * Provides specific logic for plan generation and execution using Cursor CLI.
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

Please write plan to a file at docs/plan-${taskId}.md following project's plan template format.
`.trim();

// ---------- Cursor Backend Class ----------

class CursorBackend extends DevelopmentBackend {
    constructor(config) {
        super(config);
        this.backendName = 'cursor';
    }

    /**
     * Generate plan using Cursor CLI
     */
    async generatePlan(taskId, projectPath, options = {}) {
        const {
            title = '',
            description = '',
            logger = null,
            skipExecute = false
        } = options;

        console.log(`📋 Generating plan for task ${taskId}`);
        console.log(`   Backend: ${this.stepLabel}`);
        console.log(`   Project: ${projectPath}`);

        // Build prompt
        const prompt = options.prompt || DEFAULT_PLAN_PROMPT(taskId, title, description);

        if (logger) {
            logger.logPrompt(prompt, 'Cursor Plan Generation Prompt');
        }

        const args = [this.planCommand, '-p', prompt];
        if (skipExecute) {
            args.push('--skip-execute');
        }

        try {
            const result = await runCLI(this.cliCommand, args, {
                cwd: projectPath,
                timeout: this.timeoutMs,
                logger,
                label: `${this.stepLabel} Plan Generation`
            });

            // Verify plan file was created
            const planPath = path.join(projectPath, 'docs', `plan-${taskId}.md`);
            if (!fs.existsSync(planPath)) {
                throw new Error(`Plan file not created at ${planPath}`);
            }

            return {
                success: true,
                taskId,
                projectPath,
                planPath,
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
     * Execute plan using Cursor CLI
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

        let executePrompt;

        if (prompt) {
            executePrompt = prompt;
        } else if (planPath) {
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
            executePrompt = [
                '## ⚠️ 执行范围约束（必须遵守）',
                '- 仅实现计划中明确列出的内容，不要添加计划之外的「优化」「改进」「额外功能」',
                '- 不要自行扩展需求或增加未在计划中的步骤',
                '- 若计划有歧义，严格按最小实现完成，不要过度设计',
                '',
                '---',
                '',
                planContent
            ].join('\n');
        } else {
            return {
                success: false,
                taskId,
                projectPath,
                error: 'Either planPath or prompt must be provided',
                backend: this.stepLabel
            };
        }

        if (logger) {
            logger.logPrompt(executePrompt, 'Cursor Execution Prompt');
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
            const result = await runCLI(this.cliCommand, ['--version'], {
                timeout: 10000,
                label: `${this.stepLabel} Version Check`
            });
            version = result.stdout.trim();
        } catch (error) {
            version = `Error: ${error.message}`;
        }

        return {
            name: 'Cursor CLI',
            backendName: 'cursor',
            cliCommand: this.cliCommand,
            stepLabel: this.stepLabel,
            version,
            config: this.config,
            features: [
                'Plan generation with --mode=plan',
                'Plan execution with direct prompt',
                'Native codebase understanding',
                'File editing capabilities',
                'Integration with Cursor IDE'
            ]
        };
    }

    /**
     * Validate Cursor CLI installation and setup
     */
    async validateInstallation() {
        try {
            // Check if agent command is available
            await runCLI(this.cliCommand, ['--version'], {
                timeout: 10000,
                label: `${this.stepLabel} Version Check`
            });

            // Check if we can access agent --help
            await runCLI(this.cliCommand, ['--help'], {
                timeout: 10000,
                label: `${this.stepLabel} Help Check`
            });

            console.log(`✅ ${this.stepLabel} is properly installed and working`);
            return true;
        } catch (error) {
            console.error(`❌ ${this.stepLabel} validation failed: ${error.message}`);
            console.error(`   Please ensure Cursor CLI is installed and configured`);
            console.error(`   Visit: https://cursor.com/docs/cli/overview`);
            return false;
        }
    }
}

// ---------- Exports ----------

module.exports = CursorBackend;

// ---------- CLI Interface ----------

if (require.main === module) {
    (async () => {
        const args = process.argv.slice(2);
        const command = args[0];

        const { getBackendConfig } = require('./unified-executor.js');
        const backendConfig = getBackendConfig('cursor');
        const backend = new CursorBackend(backendConfig);

        if (command === 'test') {
            console.log('🧪 Testing Cursor CLI backend...');
            const isValid = await backend.validateInstallation();

            if (isValid) {
                process.exit(0);
            } else {
                process.exit(1);
            }
        } else if (command === 'info') {
            const info = await backend.getBackendInfo();
            console.log('📊 Cursor CLI Backend Information:');
            console.log(JSON.stringify(info, null, 2));
        } else if (command === 'generate-plan') {
            const taskId = args[1];
            const projectPath = args[2];
            const title = args[3] || '';
            const description = args[4] || '';

            if (!taskId || !projectPath) {
                console.log('Usage: node cursor-backend.js generate-plan <taskId> <projectPath> [title] [description]');
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
                console.log('Usage: node cursor-backend.js execute-plan <taskId> <projectPath> <planPath>');
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
            console.log('📋 Cursor CLI Backend CLI');
            console.log('='.repeat(40));
            console.log('Available commands:');
            console.log('  test                        - Test Cursor CLI installation');
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