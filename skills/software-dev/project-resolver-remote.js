#!/usr/bin/env node

/**
 * 远程项目解析器 - 通过 HTTP 调用 Go proxy 的 /api/projects 接口
 * 当 config.json 中 settings.taskApiUrl 存在时使用
 */

const fs = require('fs');
const path = require('path');
const axios = require('axios');

let _client = null;

function getConfig() {
    const configPath = path.join(__dirname, 'config.json');
    if (!fs.existsSync(configPath)) return {};
    return JSON.parse(fs.readFileSync(configPath, 'utf-8'));
}

function getClient() {
    if (_client) return _client;
    const config = getConfig();
    const baseUrl = process.env.TASK_API_URL || config.settings?.taskApiUrl;
    const token = process.env.TASK_API_TOKEN || config.settings?.taskApiToken || '';
    if (!baseUrl) {
        throw new Error('taskApiUrl 未配置，请在 config.json 的 settings 中设置 taskApiUrl');
    }
    const url = baseUrl.replace(/\/$/, '');
    _client = { baseUrl: url, token };
    return _client;
}

async function request(method, reqPath, body) {
    const { baseUrl, token } = getClient();
    const config = {
        method,
        url: `${baseUrl}${reqPath}`,
        headers: { 'Content-Type': 'application/json' },
        validateStatus: () => true,
    };
    if (token) config.headers['Authorization'] = `Bearer ${token}`;
    if (body) config.data = body;

    const res = await axios(config);
    if (res.status === 404 && method === 'GET') return null;
    if (res.status >= 400) {
        throw new Error(`API ${method} ${reqPath}: ${res.status} ${JSON.stringify(res.data)}`);
    }
    return res.data;
}

class ProjectResolverRemote {
    /**
     * 解析项目键 → 从 Proxy 获取项目信息
     */
    async resolve(projectKey) {
        if (!projectKey) {
            throw new Error('项目键不能为空');
        }
        const project = await request('GET', `/api/projects/${encodeURIComponent(projectKey)}`);
        if (!project || !project.key) {
            throw new Error(`项目未注册: ${projectKey}`);
        }
        return {
            key: project.key,
            name: project.name || projectKey,
            path: project.path || '',
            type: project.type || 'unknown',
            techStack: project.techStack || [],
            owner: project.owner || 'unknown',
            status: project.status || 'unknown',
            description: project.description || '',
        };
    }

    /**
     * 获取所有项目
     */
    async listAll() {
        const data = await request('GET', '/api/projects');
        const projects = data?.projects || [];
        return projects.map(p => ({
            key: p.key,
            name: p.name || p.key,
            path: p.path || '',
            type: p.type || 'unknown',
            techStack: p.techStack || [],
            owner: p.owner || 'unknown',
            status: p.status || 'unknown',
            description: p.description || '',
        }));
    }
}

// CLI
if (require.main === module) {
    const resolver = new ProjectResolverRemote();
    const args = process.argv.slice(2);
    const cmd = args[0];

    (async () => {
        try {
            if (cmd === 'list') {
                const projects = await resolver.listAll();
                console.log('📋 项目列表 (from Proxy):');
                projects.forEach((p, i) => {
                    console.log(`  ${i + 1}. ${p.name} (${p.key}) → ${p.path}`);
                });
            } else if (cmd === 'info') {
                const key = args[1];
                if (!key) { console.error('用法: node project-resolver-remote.js info <key>'); process.exit(1); }
                const p = await resolver.resolve(key);
                console.log(JSON.stringify(p, null, 2));
            } else {
                console.log('用法: node project-resolver-remote.js [list|info <key>]');
            }
        } catch (e) {
            console.error(`❌ ${e.message}`);
            process.exit(1);
        }
    })();
}

module.exports = ProjectResolverRemote;
