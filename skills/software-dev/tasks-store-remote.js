#!/usr/bin/env node

/**
 * 远程任务存储 - 通过 HTTP 调用 Go proxy 的 /api/tasks 接口
 * 当 config.json 中 settings.taskApiUrl 存在时，openclaw-plan-workflow 使用此模块替代 tasks-store
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');
const axios = require('axios');

let _client = null;

// 每次请求新建 Agent，不复用连接，避免长时间操作后 ECONNRESET
function freshAgents() {
  return {
    http: new http.Agent({ keepAlive: false }),
    https: new https.Agent({ keepAlive: false }),
  };
}

function getConfig() {
  const configPath = path.join(__dirname, 'config.json');
  if (!fs.existsSync(configPath)) return {};
  return JSON.parse(fs.readFileSync(configPath, 'utf-8'));
}

function getClient() {
  if (_client) return _client;
  // 优先使用环境变量（Proxy 启动子进程时设置），实现任务体系联动
  const config = getConfig();
  const baseUrl = process.env.TASK_API_URL || config.settings?.taskApiUrl || config.settings?.taskSystemUrl;
  const token = process.env.TASK_API_TOKEN || config.settings?.taskApiToken || '';
  if (!baseUrl) {
    throw new Error('taskApiUrl 未配置，请设置 config.settings.taskApiUrl 或环境变量 TASK_API_URL');
  }
  const url = baseUrl.replace(/\/$/, '');
  _client = { baseUrl: url, token };
  return _client;
}

async function request(method, path, body) {
  const { baseUrl, token } = getClient();
  const agents = freshAgents();
  const config = {
    method,
    url: `${baseUrl}${path}`,
    headers: { 'Content-Type': 'application/json', Connection: 'close' },
    validateStatus: () => true,
    timeout: 15000,
    httpAgent: agents.http,
    httpsAgent: agents.https,
  };
  if (token) config.headers['Authorization'] = `Bearer ${token}`;
  if (body) config.data = body;

  const res = await axios(config);
  if (res.status === 404 && method === 'GET') return null;
  if (res.status >= 400) {
    throw new Error(`API ${method} ${path}: ${res.status} ${JSON.stringify(res.data)}`);
  }
  return res.data;
}

async function loadTasks() {
  const data = await request('GET', '/api/tasks');
  const tasks = data?.tasks || [];
  return {
    nextSeq: tasks.length + 1,
    tasks: tasks.map((t) => ({
      id: t.id,
      taskId: t.taskId || null,
      title: t.title,
      description: t.description || '',
      projectKey: t.projectKey || '',
      status: t.status,
      planPath: t.planPath || null,
      priority: t.priority || 'medium',
      assignee: t.assignee || '',
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
    })),
  };
}

function generateTaskId(seq) {
  const now = new Date();
  const date = now.toISOString().slice(0, 10).replace(/-/g, '');
  const n = String(seq).padStart(3, '0');
  return `TASK-${date}-${n}`;
}

async function createTask(fields) {
  const { title, description, projectKey, priority = 'medium', assignee = '' } = fields;
  if (!title || !projectKey) {
    throw new Error('创建任务需要 title 和 projectKey');
  }
  const body = {
    title,
    description: description || title,
    projectKey,
    priority: priority === 'medium' ? 'p2' : priority === 'high' ? 'p1' : 'p3',
    assignee,
    source: 'skill', // 技能创建的任务，与手动创建区分
  };
  const task = await request('POST', '/api/tasks', body);
  return {
    id: task.id,
    taskId: task.taskId || null,
    title: task.title,
    description: task.description || task.title,
    projectKey: projectKey,
    status: 'pending',
    planPath: null,
    priority,
    assignee,
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
  };
}

async function updateTask(idOrTaskId, update) {
  const task = await getTask(idOrTaskId);
  if (!task) return null;
  const body = {};
  if (update.taskId != null) body.taskId = update.taskId;
  if (update.planPath != null) body.planPath = update.planPath;
  if (update.status != null) body.status = update.status;
  if (update.title != null) body.title = update.title;
  if (update.description != null) body.description = update.description;
  if (update.priority != null) body.priority = update.priority;
  if (update.phase != null) body.phase = update.phase;
  if (update.projectKey != null) body.projectKey = update.projectKey;
  // TMUX agent management fields
  if (update.backend != null) body.backend = update.backend;
  if (update.tmuxSession != null) body.tmuxSession = update.tmuxSession;
  if (update.tmuxWindow != null) body.tmuxWindow = update.tmuxWindow;
  if (update.tmuxPaneId != null) body.tmuxPaneId = update.tmuxPaneId;
  if (update.lastExecLogPath != null) body.lastExecLogPath = update.lastExecLogPath;
  const updated = await request('PUT', `/api/tasks/${task.id}`, body);
  return updated;
}

async function listByStatus(status) {
  const path = status ? `/api/tasks?status=${status}` : '/api/tasks';
  const data = await request('GET', path);
  return data?.tasks || [];
}

async function getTask(idOrTaskId) {
  const task = await request('GET', `/api/tasks/${encodeURIComponent(idOrTaskId)}`);
  return task;
}

async function assignTaskId(id, taskId, planPath) {
  return updateTask(id, { taskId, planPath, status: 'planned' });
}

/**
 * 状态转换：与 Proxy 任务体系联动
 * 将 skill 状态 (developing/reviewing/done/failed) 映射为 Proxy 状态 (inProgress/waitingFeedback/completed/failed)
 */
function mapStatusToProxy(skillStatus) {
  const m = {
    developing: 'inProgress',
    reviewing: 'waitingFeedback',
    done: 'completed',
    failed: 'failed',
    planned: 'planned',
    pending: 'pending',
  };
  return m[skillStatus] || skillStatus;
}

async function transitionTask(idOrTaskId, newStatus, metadata = {}) {
  const task = await getTask(idOrTaskId);
  if (!task) {
    return { success: false, error: `Task not found: ${idOrTaskId}` };
  }
  const proxyStatus = mapStatusToProxy(newStatus);
  const updated = await updateTask(idOrTaskId, { status: proxyStatus });
  return {
    success: true,
    task: updated || task,
    stateResult: { transition: { from: task.status, to: proxyStatus } },
  };
}

async function deleteTask(idOrTaskId) {
  const task = await getTask(idOrTaskId);
  if (!task) return null;
  await request('DELETE', `/api/tasks/${task.id}`);
  return task;
}

/**
 * 更新任务的 TMUX 元数据（远程）
 * @param {string} idOrTaskId - 任务 ID 或 taskId
 * @param {object} tmuxMeta - { backend, tmuxSession, tmuxWindow, tmuxPaneId, lastExecLogPath }
 * @returns {object|null} 更新后的任务
 */
async function updateTmuxMetadata(idOrTaskId, tmuxMeta) {
  return updateTask(idOrTaskId, tmuxMeta);
}

/**
 * 获取任务的 TMUX 元数据（远程）
 * @param {string} idOrTaskId - 任务 ID 或 taskId
 * @returns {object|null} TMUX 元数据
 */
async function getTmuxMetadata(idOrTaskId) {
  const task = await getTask(idOrTaskId);
  if (!task) return null;
  return {
    backend: task.backend,
    tmuxSession: task.tmuxSession,
    tmuxWindow: task.tmuxWindow,
    tmuxPaneId: task.tmuxPaneId,
    lastExecLogPath: task.lastExecLogPath
  };
}

module.exports = {
  loadTasks,
  createTask,
  updateTask,
  getTask,
  deleteTask,
  listByStatus,
  generateTaskId,
  assignTaskId,
  transitionTask,
  // TMUX metadata functions
  updateTmuxMetadata,
  getTmuxMetadata,
};
