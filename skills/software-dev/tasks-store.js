#!/usr/bin/env node

/**
 * JSON 任务存储（无 Lark、无服务端依赖）
 * 任务状态: pending → planned → developing → reviewing → done
 *     ↓         ↓           ↓          ↓
 *   failed   failed      failed     failed
 */

const fs = require('fs');
const path = require('path');

// Import state machine for state management
const { TaskStates, updateTaskStatus, validateTaskStatus } = require('./state-machine.js');

const DATA_DIR = path.join(__dirname, 'data');
const TASKS_FILE = path.join(DATA_DIR, 'tasks.json');

function ensureDataDir() {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
}

function loadTasks() {
  ensureDataDir();
  if (!fs.existsSync(TASKS_FILE)) {
    return { nextSeq: 1, tasks: [] };
  }
  try {
    const raw = fs.readFileSync(TASKS_FILE, 'utf-8');
    return JSON.parse(raw);
  } catch (e) {
    return { nextSeq: 1, tasks: [] };
  }
}

function saveTasks(data) {
  ensureDataDir();
  fs.writeFileSync(TASKS_FILE, JSON.stringify(data, null, 2), 'utf-8');
}

/**
 * 生成展示用任务ID：TASK-YYYYMMDD-NNN（seq 可用任务 id）
 */
function generateTaskId(seq) {
  const now = new Date();
  const date = now.toISOString().slice(0, 10).replace(/-/g, '');
  const n = String(seq).padStart(3, '0');
  return `TASK-${date}-${n}`;
}

/**
 * 创建任务（状态 pending，必须包含 projectKey）
 * @param {object} fields - { title, description, projectKey [, priority, assignee ] }
 * @returns {object} task
 */
function createTask(fields) {
  const { title, description, projectKey, priority = 'medium', assignee = '' } = fields;
  if (!title || !projectKey) {
    throw new Error('创建任务需要 title 和 projectKey');
  }
  const data = loadTasks();
  const id = String(data.nextSeq++);
  const now = new Date().toISOString();
  const task = {
    id,
    taskId: null,
    title,
    description: description || title,
    projectKey,
    status: TaskStates.PENDING,
    planPath: null,
    priority,
    assignee,
    createdAt: now,
    updatedAt: now,
    // TMUX agent management fields
    backend: null,
    tmuxSession: null,
    tmuxWindow: null,
    tmuxPaneId: null,
    lastExecLogPath: null,
    // State machine fields
    plannedAt: null,
    developingStartTime: null,
    developingEndTime: null,
    reviewingStartTime: null,
    reviewingEndTime: null,
    completedAt: null,
    failedAt: null,
    error: null,
    transitions: []
  };
  data.tasks.push(task);
  saveTasks(data);
  return task;
}

/**
 * 更新任务
 */
function updateTask(idOrTaskId, update) {
  const data = loadTasks();
  const task = data.tasks.find(
    t => String(t.id) === String(idOrTaskId) || t.taskId === idOrTaskId
  );
  if (!task) return null;

  // If updating status, use state machine validation
  if (update.status) {
    const stateResult = updateTaskStatus(task, update.status, update.metadata || {});
    if (!stateResult.success) {
      throw new Error(stateResult.error);
    }
    Object.assign(task, stateResult.task);
    // Preserve other fields from update (e.g. taskId, planPath from assignTaskId)
    const { status, metadata, ...rest } = update;
    Object.assign(task, rest);
  } else {
    Object.assign(task, update, { updatedAt: new Date().toISOString() });
  }
  task.updatedAt = new Date().toISOString();
  saveTasks(data);
  return task;
}

/**
 * 状态转换函数：转换任务状态并记录历史
 */
function transitionTask(idOrTaskId, newStatus, metadata = {}) {
  const data = loadTasks();
  const task = data.tasks.find(
    t => String(t.id) === String(idOrTaskId) || t.taskId === idOrTaskId
  );
  if (!task) {
    return {
      success: false,
      error: `Task not found: ${idOrTaskId}`
    };
  }

  const stateResult = updateTaskStatus(task, newStatus, metadata);

  if (!stateResult.success) {
    return {
      success: false,
      error: stateResult.error,
      currentStatus: stateResult.currentStatus
    };
  }

  // Apply the updated task
  Object.assign(task, stateResult.task);
  saveTasks(data);

  return {
    success: true,
    task,
    stateResult
  };
}

/**
 * 标记任务失败
 */
function markTaskFailed(idOrTaskId, errorMessage = 'Task failed') {
  return transitionTask(idOrTaskId, TaskStates.FAILED, { error: errorMessage });
}

/**
 * 标记任务开始开发
 */
function startDevelopment(idOrTaskId) {
  return transitionTask(idOrTaskId, TaskStates.DEVELOPING);
}

/**
 * 标记任务进入审核状态
 */
function startReviewing(idOrTaskId) {
  return transitionTask(idOrTaskId, TaskStates.REVIEWING);
}

/**
 * 标记任务完成
 */
function markTaskDone(idOrTaskId) {
  return transitionTask(idOrTaskId, TaskStates.DONE);
}

/**
 * 按状态列出任务
 */
function listByStatus(status) {
  const data = loadTasks();
  if (!status) return data.tasks;
  return data.tasks.filter(t => t.status === status);
}

/**
 * 获取单个任务
 */
function getTask(idOrTaskId) {
  const data = loadTasks();
  return data.tasks.find(
    t => String(t.id) === String(idOrTaskId) || t.taskId === idOrTaskId
  ) || null;
}

/**
 * 为待处理任务分配 taskId（内部用，由 process-pending 调用）
 */
function assignTaskId(id, taskId, planPath) {
  return updateTask(id, {
    taskId,
    planPath,
    status: TaskStates.PLANNED
  });
}

/**
 * 删除任务
 */
function deleteTask(idOrTaskId) {
  const data = loadTasks();
  const idx = data.tasks.findIndex(
    t => String(t.id) === String(idOrTaskId) || t.taskId === idOrTaskId
  );
  if (idx === -1) return null;
  const removed = data.tasks.splice(idx, 1)[0];
  saveTasks(data);
  return removed;
}

/**
 * 获取所有任务
 */
function getAllTasks() {
  const data = loadTasks();
  return data.tasks;
}

/**
 * 批量获取任务（支持多个 ID）
 */
function getTasksByIds(ids) {
  const data = loadTasks();
  return data.tasks.filter(task =>
    ids.some(id => String(task.id) === String(id) || task.taskId === id)
  );
}

/**
 * 更新任务的 TMUX 元数据
 * @param {string} idOrTaskId - 任务 ID 或 taskId
 * @param {object} tmuxMeta - { backend, tmuxSession, tmuxWindow, tmuxPaneId, lastExecLogPath }
 * @returns {object|null} 更新后的任务
 */
function updateTmuxMetadata(idOrTaskId, tmuxMeta) {
  const data = loadTasks();
  const task = data.tasks.find(
    t => String(t.id) === String(idOrTaskId) || t.taskId === idOrTaskId
  );
  if (!task) return null;

  if (tmuxMeta.backend !== undefined) task.backend = tmuxMeta.backend;
  if (tmuxMeta.tmuxSession !== undefined) task.tmuxSession = tmuxMeta.tmuxSession;
  if (tmuxMeta.tmuxWindow !== undefined) task.tmuxWindow = tmuxMeta.tmuxWindow;
  if (tmuxMeta.tmuxPaneId !== undefined) task.tmuxPaneId = tmuxMeta.tmuxPaneId;
  if (tmuxMeta.lastExecLogPath !== undefined) task.lastExecLogPath = tmuxMeta.lastExecLogPath;

  task.updatedAt = new Date().toISOString();
  saveTasks(data);
  return task;
}

/**
 * 获取任务的 TMUX 元数据
 * @param {string} idOrTaskId - 任务 ID 或 taskId
 * @returns {object|null} TMUX 元数据
 */
function getTmuxMetadata(idOrTaskId) {
  const data = loadTasks();
  const task = data.tasks.find(
    t => String(t.id) === String(idOrTaskId) || t.taskId === idOrTaskId
  );
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
  TASKS_FILE,
  loadTasks,
  saveTasks,
  createTask,
  updateTask,
  getTask,
  getAllTasks,
  getTasksByIds,
  deleteTask,
  listByStatus,
  generateTaskId,
  assignTaskId,
  // TMUX metadata functions
  updateTmuxMetadata,
  getTmuxMetadata,
  // State management functions
  transitionTask,
  markTaskFailed,
  startDevelopment,
  startReviewing,
  markTaskDone,
  // State machine exports
  TaskStates
};
