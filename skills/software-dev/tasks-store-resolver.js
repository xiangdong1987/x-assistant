#!/usr/bin/env node

/**
 * 根据 config 选择使用本地 tasks-store 或远程 tasks-store-remote
 * 当 settings.taskApiUrl 存在时使用远程（Go proxy）
 */

const fs = require('fs');
const path = require('path');

function useRemote() {
  // 流程验证脚本可强制使用本地存储，便于无 Proxy 时自验证
  if (process.env.VERIFY_USE_LOCAL_STORE === '1') return false;
  // Proxy 启动子进程时会设置 TASK_API_URL，优先使用环境变量以支持任务体系联动
  if (process.env.TASK_API_URL) return true;
  const configPath = path.join(__dirname, 'config.json');
  if (!fs.existsSync(configPath)) return false;
  const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
  // taskApiUrl = Go proxy; taskSystemUrl = legacy Node server. Prefer taskApiUrl.
  return !!(config.settings?.taskApiUrl);
}

function getTasksStore() {
  if (useRemote()) {
    return require('./tasks-store-remote');
  }
  return require('./tasks-store');
}

module.exports = { useRemote, getTasksStore };
