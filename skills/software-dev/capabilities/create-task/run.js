#!/usr/bin/env node
const path = require('path');
const root = path.resolve(__dirname, '..', '..');
process.chdir(root);
const Integration = require(path.join(root, 'openclaw-integration.js'));
const integration = new Integration();
const [title, desc, projectKey] = process.argv.slice(2);
if (!title || !projectKey) {
  console.error('用法: node run.js "标题" "描述" <projectKey>');
  process.exit(1);
}
integration.executeCommand('create-task-json', title, desc || title, projectKey).catch(e => {
  console.error(e.message || e);
  process.exit(1);
});
