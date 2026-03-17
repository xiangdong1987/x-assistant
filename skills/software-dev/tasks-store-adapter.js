#!/usr/bin/env node

/**
 * 统一的任务存储接口 - 自动选择本地或远程，对外一律提供 async API
 */

const { getTasksStore } = require('./tasks-store-resolver');

const store = getTasksStore();

// Promise.resolve 同时兼容 sync 返回值与 Promise
const adapter = {
  loadTasks: () => Promise.resolve(store.loadTasks()),
  createTask: (...args) => Promise.resolve(store.createTask(...args)),
  updateTask: (...args) => Promise.resolve(store.updateTask(...args)),
  getTask: (...args) => Promise.resolve(store.getTask(...args)),
  deleteTask: (...args) => Promise.resolve(store.deleteTask(...args)),
  listByStatus: (...args) => Promise.resolve(store.listByStatus(...args)),
  generateTaskId: store.generateTaskId,
  assignTaskId: (...args) => Promise.resolve(store.assignTaskId(...args)),
  // TMUX metadata functions
  updateTmuxMetadata: (...args) => Promise.resolve(store.updateTmuxMetadata(...args)),
  getTmuxMetadata: (...args) => Promise.resolve(store.getTmuxMetadata(...args)),
  transitionTask: (...args) =>
    Promise.resolve(
      store.transitionTask
        ? store.transitionTask(...args)
        : Promise.reject(new Error('transitionTask not supported by store'))
    ),
};

module.exports = adapter;
