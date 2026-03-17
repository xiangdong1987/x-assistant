# XAssistant

[English](README.md) | 中文

AI Agent 统一入口应用，集任务管理、多阶段自动化执行和实时反馈系统于一体的 Flutter 应用。

## 项目概述

XAssistant 是一个智能化的任务管理助手，支持通过自然语言创建任务、自动生成执行计划，并通过 Claude Code、Claude Code Remote (ccr) 或 Cursor IDE 自动执行任务。任务按 plan → code → test → done 四个阶段流水线自动推进。应用采用前后端分离架构，支持跨平台运行（iOS、Android、macOS、Windows、Linux）。

## 核心功能

### 1. 任务管理
- **任务生命周期**: `pending` → `confirmed` → `planning` → `planned` → `coding` → `testing` → `submitting` → `done`（或 `failed`）
- **优先级管理**: P0/P1/P2/P3 四级优先级
- **任务来源**: 手动创建、OpenClaw 网关、Cursor IDE
- **执行器支持**: Claude Code (`claude`)、Claude Code Remote (`ccr`)、Cursor

### 2. 多阶段自动化流水线
每个任务按以下四个阶段自动推进：
- **plan**：AI Agent 生成执行计划
- **code**：实现代码变更
- **test**：运行测试
- **done**：审查、提交并最终确认

`phaseWatcher` 持续监控任务状态，自动触发对应阶段。阶段执行可内嵌运行，也可在 **tmux pane** 中异步运行（可配置）。

### 3. Dashboard 首页
- 今日任务展示、任务统计卡片（待确认/执行中/待反馈/已完成）、快速访问常用项目

### 4. 项目管理
- 项目配置（路径、技术栈、所有者、状态）、项目技能关联、最近项目快速访问

### 5. 技能系统
- **项目技能**：每个项目可配置专属技能
- **技能执行**：通过 WebSocket 实时通信执行命令
- **内置技能**：`create-task`、`execute-task`、`generate-plan`、`agent-start`、`agent-stop`、`agent-status`、`tmux-focus`
- **扩展技能**：`schedule`（日程管理）、`shutdown`（关机自动化）、`db-query`（数据库查询）、`italia-company-lookup`（公司信息查询）

### 6. 实时通信
- WebSocket 长连接（心跳保活、自动重连）、OpenClaw Gateway 任务推送、连接状态实时显示

## 技术架构

### 前端技术栈
| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.16+ |
| 状态管理 | Riverpod 2.x |
| 路由 | GoRouter 13.x |
| 本地存储 | Hive, SharedPreferences |
| 网络通信 | WebSocket, Dio |
| UI 组件 | Material Design 3, Google Fonts |
| 语音功能 | speech_to_text, flutter_tts |

### 后端技术栈 (proxy)
| 类别 | 技术 |
|------|------|
| 语言 | Go 1.21+ |
| MCP 集成 | Cursor IDE 协议 |
| API | RESTful + WebSocket |
| 认证 | JWT |
| 自动化 | phaseWatcher（阶段流水线监控） |

### 技能运行时
| 类别 | 技术 |
|------|------|
| 脚本 | Node.js 18+ |
| 异步执行 | tmux pane |
| 后端 CLI | ccr / cursor / claude |

## 目录结构

```
xassistant/
├── lib/                        # Flutter 前端代码
├── proxy/                      # Go 后端代理
├── skills/                     # 技能脚本
│   ├── software-dev/           # 核心开发自动化（plan/code/test/done 流水线）
│   ├── schedule/               # 日程管理技能
│   ├── shutdown/               # 关机自动化技能
│   └── db-query/               # 数据库查询技能
└── docs/                       # 项目文档与任务计划
```

## 快速开始

### 环境要求
- Flutter SDK >= 3.16.0，Dart SDK >= 3.2.0
- Go 1.21+（后端代理），Node.js >= 18.0
- `jq`、`cursor` / `claude` / `ccr` CLI、`tmux`（异步阶段执行需要）

### 安装与启动

```bash
# 前端
flutter pub get && flutter run

# 后端 (proxy 目录)
cd proxy && go mod download
go run main.go --skills-path="../skills"
```

详见 [README.md](README.md) 中的完整命令与配置。

### macOS 安装与部署（使用 Release 包）

如果你只想在 macOS 上**使用** XAssistant，而不是本地开发，推荐通过 GitHub Release 提供的打包版本进行安装（内置 Go 版 `proxy`），而不是手动 `flutter run`。

**步骤：**

1. **从 GitHub Releases 下载应用包**
   - 打开本项目的 GitHub Releases 页面。
   - 找到目标版本（通常对应 `release/x.y.z` 分支）。
   - 下载资产 `XAssistant-macos.zip`。

2. **安装到应用目录**
   - 解压 `XAssistant-macos.zip`，得到 `XAssistant.app`。
   - 将 `XAssistant.app` 拖到 `/Applications` 或你习惯的应用目录。
   - 首次启动如果被 Gatekeeper 拦截，可以通过：
     - 右键 `XAssistant.app` 选择「打开」一次，或
     - 在终端执行（可选）：
       ```bash
       xattr -d com.apple.quarantine /Applications/XAssistant.app
       ```

3. **启动内置 proxy（后端）**
   - Release 构建时，Go 版 `proxy` 已经被打入：
     ```text
     XAssistant.app/Contents/MacOS/proxy
     ```
   - 推荐方式是通过 **macOS 客户端内的「代理配置 / Proxy Config」界面**进行配置和启动，而不是手动敲很长的命令行：
     - 在应用中打开：`设置 → Proxy Config`（该界面同时支持 **中文 / English**）。
     - 在表单中配置：
       - **Workdir（工作目录）**：例如 `/Volumes/external/code/ai/projects/siyou/xassistant`（包含 `proxy/config`、`skills` 等）
       - **Skills Path（技能路径）**：例如 `../skills`
       - **Port / OpenClaw / Token** 等其他参数
     - 点击「**Start Proxy / 启动代理**」按钮后，应用会在后台以合适的参数启动内置 `proxy`。
   - 如需手动调试，也可以直接在终端中运行：
     ```bash
     /Applications/XAssistant.app/Contents/MacOS/proxy \
       --port 8443 \
       --workdir "/Volumes/external/code/ai/projects/siyou/xassistant" \
       --skills-path "../skills" \
       --allow-local-no-auth
     ```
   - 建议将 `--workdir` 指向当前仓库根目录，这样无需单独复制配置文件。

4. **在应用中配置前端连接后端**
   - 启动 `XAssistant.app`。
   - 打开设置，将：
     - **HTTP Base URL** 设置为 `http://127.0.0.1:8443`
     - **WebSocket URL** 设置为 `ws://127.0.0.1:8443/ws`
   - 保存后，任务列表、计划执行等就会通过本机运行的 `proxy` 与 skills 交互。

5. **升级到新版本**
   - 每次有新版本发布时：
     - 从 GitHub Releases 下载新的 `XAssistant-macos.zip`。
     - 替换 `/Applications/XAssistant.app` 即可（内置 `proxy` 也会一起升级）。
   - 后端配置（如 `projects.json`、`skill_paths.json` 等）仍由 `--workdir` 指向的目录管理，一般不随应用更新而改变。

## 任务状态流转

```
pending → confirmed → planning → planned → coding → testing → submitting → done
                                                                          ↘ failed
```

后端每 5 秒从计划文件 meta 同步任务状态，并通过 WebSocket 广播变更。

## 配置说明

- **连接**：在应用「设置」中配置 HTTP/WebSocket 地址与 Token。
- **Proxy 项目**：复制 `proxy/config/projects.example.json` 为 `projects.json` 并修改路径。
- **技能路径**：可设置环境变量 `XASSISTANT_SKILL_PATHS`，或复制 `skill_paths.example.json` 为 `skill_paths.json`，支持相对路径与 `$HOME`。
- **技能配置**：在 `skills/software-dev/config.json` 中设置 `projectBasePath` 和 `settings.executor`（`cursor`、`ccr` 或 `claude`）。

## 文档

- [阶段流转与状态机](docs/phase-flow.md)
- [任务状态说明](docs/task-status-states.md)
- [tmux agent 使用指南](docs/tmux-agent-usage.md)
- [多 Agent 工作流](docs/design-workflow-multi-agent.md)
- [OpenClaw 集成](docs/openclaw-unified-ui-skills.md)

## 赞助 / 打赏

若本项目对你有帮助，欢迎赞助支持：

- **[Buy Me a Coffee](https://buymeacoffee.com/xiangdong14)** — 一次性或月度赞助
- **支付宝**：扫码赞赏

  <img src="docs/alipay.png" width="180" alt="支付宝收款码" />

感谢你的支持。

## License

MIT
