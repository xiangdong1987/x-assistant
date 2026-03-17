#!/usr/bin/env node
const path = require('path');
const root = path.resolve(__dirname, '..', '..');
process.chdir(root);
const Integration = require(path.join(root, 'openclaw-integration.js'));
const integration = new Integration();

// Parse arguments
const args = process.argv.slice(2);
const taskId = args[0];
const backendIndex = args.indexOf('--backend');
const backend = backendIndex !== -1 ? args[backendIndex + 1] : null;

if (!taskId) {
    console.error('用法: node run.js <taskId> [--backend claude|cursor]');
    console.error('');
    console.error('参数:');
    console.error('  <taskId>       任务 ID (数字 ID 或 TASK-YYYYMMDD-NNN)');
    console.error('  --backend       指定后端 (claude 或 cursor, 默认为 claude)');
    process.exit(1);
}

// Build args array for executeCommand: delegate to run-phase code
const executeArgs = [taskId, 'code'];
if (backend) {
    executeArgs.push('--backend', backend);
}

integration.executeCommand('run-phase', ...executeArgs).catch(e => {
    console.error(e.message || e);
    process.exit(1);
});
