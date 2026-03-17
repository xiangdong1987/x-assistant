#!/usr/bin/env node
const path = require('path');
const root = path.resolve(__dirname, '..', '..');
process.chdir(root);
const Integration = require(path.join(root, 'openclaw-integration.js'));
const integration = new Integration();

// Parse arguments
const args = process.argv.slice(2);
const taskId = args[0]; // Optional: specific task ID

integration.executeCommand('generate-plan', taskId).catch(e => {
  console.error(e.message || e);
  process.exit(1);
});
