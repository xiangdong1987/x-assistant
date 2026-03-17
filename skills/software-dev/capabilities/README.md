# 三个核心子技能（创建任务 / 生成 Plan / 执行任务）

此处为可单独调用的 3 个能力，每个目录含 `SKILL.md` + `run.js`。  
**依赖安装在仓库根目录**，请先在根目录执行：

```bash
cd /path/to/software-dev-agent-skill
npm install
```

- **create-task**：创建 pending 任务（调用 `create-task-json`）
- **generate-plan**：为 pending 任务生成 plan 文件（调用 `generate-plan`）
- **execute-task**：执行已 planned 的任务（调用 `execute-task`）

`run.js` 会自动 `chdir` 到仓库根再加载 `openclaw-integration.js`，因此会使用根目录的 `node_modules`。
