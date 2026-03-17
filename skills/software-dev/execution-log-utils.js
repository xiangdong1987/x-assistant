#!/usr/bin/env node

/**
 * 执行日志工具：可配置的日志目录、绝对路径、任务关联
 * 供 unified-executor、run.js、proxy 使用
 *
 * 配置（config.json）：
 *   executionLogDir 或 settings.executionLogDir
 *   - 不设：默认软件安装目录/logs（绝对路径）
 *   - 设为相对路径：相对 skills/software-dev 解析
 *   - 设为绝对路径：直接使用
 */

const fs = require('fs');
const path = require('path');
const { loadConfig } = require('./config-loader');

/**
 * 获取执行日志根目录（绝对路径）
 * 优先级：config.executionLogDir > config.settings.executionLogDir > 软件安装目录/logs
 * @param {string} configDir - config.json 所在目录（如 __dirname）
 * @returns {string} 绝对路径
 */
function getExecutionLogDir(configDir) {
    let config = {};
    try {
        config = loadConfig();
    } catch (err) {
        console.error('[execution-log-utils] Failed to load config:', err.message);
    }
    const dir = config.executionLogDir || config.settings?.executionLogDir;
    if (dir && dir.trim()) {
        return path.resolve(configDir, dir);
    }
    // 默认：软件安装目录（xassistant 根目录）/logs
    const workspaceRoot = path.resolve(configDir, '..', '..');
    return path.join(workspaceRoot, 'logs');
}

/**
 * 生成日志文件路径
 * @param {string} logDir - 日志目录（绝对路径）
 * @param {string} [taskId] - 任务 ID
 * @param {object} [options] - { stable: boolean } 如果 stable 为 true，则不包含时间戳，便于追加到同一个文件
 * @returns {string} 绝对路径
 */
function resolveLogPath(logDir, taskId, options = {}) {
    if (options.stable && taskId) {
        return path.join(logDir, `exec-${taskId}.log`);
    }
    const d = new Date();
    const ts = d.toISOString().slice(0, 10).replace(/-/g, '') + '-' + d.toISOString().slice(11, 19).replace(/:/g, '');
    const base = taskId ? `exec-${taskId}-${ts}.log` : `exec-${ts}.log`;
    return path.join(logDir, base);
}

module.exports = { getExecutionLogDir, resolveLogPath };
