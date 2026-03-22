# Claude Voice Proxy

Go 后端服务，为 XAssistant Flutter App 提供 WebSocket 桥接、OpenClaw 集成和实时语音交互（VAD + STT + TTS）。

---

## 快速启动

### 基础模式

```bash
go run main.go
```

### 启用 OpenClaw + 语音

```bash
OPENCLAW_TOKEN=<your-token> bash start.sh
```

> `OPENCLAW_TOKEN` 为必填项。本地开发时可使用任意非空字符串（如 `dev`），
> 因为 `--allow-local-no-auth` 已跳过本地请求的 JWT 验证。

或手动指定参数：

```bash
CGO_ENABLED=1 go run main.go \
  --openclaw \
  --openclaw-token="<your-token>" \
  --allow-local-no-auth \
  --skills-path="../skills" \
  -voice \
  -voice-models-dir ./models \
  -voice-stt-dir ./models/stt-sense-voice
```

> `CGO_ENABLED=1` 是语音功能必须的，Sherpa-ONNX 依赖 CGO。

---

## 语音功能

### 工作流程

```
麦克风 PCM16 → VAD（静音检测）→ STT（语音转文字）→ 追加到 App 输入框
```

- **VAD**：Silero VAD 实时检测说话起止，自动切断句子
- **STT**：支持多引擎并行，整段识别后返回最终文字
- **App 集成**：识别结果追加到输入框，支持语音指令控制

### 语音指令（App 内）

说出以下指令词，App 会自动执行对应操作（支持 SenseVoice 标点，如"发送。"也可识别）：

| 指令词 | 操作 |
|--------|------|
| `发送` / `提交` / `发出去` / `发吧` / `发出` | 5 秒倒计时后自动发送，可点 ✕ 取消 |
| `清除` / `清空` / `删除` / `重来` / `算了` | 立即清空输入框 |
| `send` / `submit` / `send it` | 同"发送" |
| `clear` / `clear input` | 同"清除" |

> 指令词需出现在当次说话的**末尾**。例如说"帮我查一下天气发送"，会提取"帮我查一下天气"并发送。

### 快捷键

| 快捷键 | 操作 |
|--------|------|
| `Ctrl+M` | 开启 / 关闭语音输入 |

---

### 下载模型（仅需运行一次）

```bash
bash models/download.sh
```

下载完成后默认目录结构：

```
models/
├── vad/
│   └── silero_vad.onnx              # Silero VAD (~2MB)
├── stt/                             # Zipformer 双语 zh-en（流式，低延迟）
│   ├── encoder.int8.onnx
│   ├── decoder.int8.onnx
│   ├── joiner.int8.onnx
│   └── tokens.txt
├── stt-paraformer-zh/               # Paraformer zh（批量，中文准确率高）
│   ├── model.int8.onnx
│   ├── tokens.txt
│   └── type.txt                     # 内容: paraformer
├── stt-sense-voice/                 # SenseVoice（推荐，中英日韩粤，自带标点）
│   ├── model.int8.onnx
│   ├── tokens.txt
│   ├── type.txt                     # 内容: sense-voice
│   └── language.txt                 # 内容: zh（固定中文，避免误识别为日文）
└── tts/
    ├── model.onnx                   # Kokoro 多语言 TTS
    ├── voices.bin
    ├── tokens.txt
    ├── lexicon.txt
    └── espeak-ng-data/
```

---

## STT 模型切换

### 支持的模型类型

| 类型 | 识别方式 | 推荐场景 | 大小 |
|------|----------|----------|------|
| `sense-voice` | 批量 | **中文首选**，自带标点，支持中英日韩粤 | ~228MB |
| `paraformer` | 批量 | 中文，无标点 | ~220MB |
| `zipformer` | 流式（实时局部文字） | 英文为主，低延迟 | ~90MB |
| `whisper` | 批量 | 多语言 | 视规格而定 |

### 模型类型自动检测

启动时按以下顺序检测目录内模型类型：

1. **`type.txt`**（优先）：文件内容为 `sense-voice` / `paraformer` / `zipformer` / `whisper`
2. **文件启发式**：
   - `encoder.int8.onnx` + `decoder.int8.onnx` + `joiner.int8.onnx` → `zipformer`
   - `model.int8.onnx` 或 `model.onnx` → `paraformer`
   - `encoder.onnx` + `decoder.onnx` → `whisper`

### 切换模型

```bash
# 使用 SenseVoice（推荐，中文效果最好）
OPENCLAW_TOKEN=dev bash start.sh
# start.sh 默认已指向 stt-sense-voice

# 手动指定
CGO_ENABLED=1 go run main.go -voice -voice-stt-dir ./models/stt-sense-voice

# 多模型并联（并行识别，取字数最多的结果）
CGO_ENABLED=1 go run main.go -voice \
  -voice-stt-dir ./models/stt-sense-voice \
  -voice-stt-dir ./models/stt-zipformer-en
```

### SenseVoice 中文模型下载

```bash
mkdir -p models/stt-sense-voice
BASE="https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main"
curl -L -o models/stt-sense-voice/model.int8.onnx "$BASE/model.int8.onnx"
curl -L -o models/stt-sense-voice/tokens.txt      "$BASE/tokens.txt"
echo "sense-voice" > models/stt-sense-voice/type.txt
echo "zh"          > models/stt-sense-voice/language.txt
```

### Paraformer 中文模型下载

```bash
mkdir -p models/stt-paraformer-zh
BASE="https://huggingface.co/csukuangfj/sherpa-onnx-paraformer-zh-2024-03-09/resolve/main"
curl -L -o models/stt-paraformer-zh/model.int8.onnx "$BASE/model.int8.onnx"
curl -L -o models/stt-paraformer-zh/tokens.txt      "$BASE/tokens.txt"
echo "paraformer" > models/stt-paraformer-zh/type.txt
```

---

## 语音相关 Flag

| Flag | 默认值 | 说明 |
|------|--------|------|
| `-voice` | false | 启用语音流水线 |
| `-voice-models-dir` | `./models` | 模型根目录（VAD/TTS 路径基准） |
| `-voice-stt-dir` | `<models-dir>/stt` | STT 模型目录（**可重复**以加载多个模型） |
| `-voice-vad-threshold` | `0.4` | VAD 检测灵敏度（0.0-1.0，越低越灵敏） |
| `-voice-vad-silence-ms` | `700` | 静音多少毫秒后结束一句话 |
| `-voice-stt-threads` | `4` | 每个 STT 引擎的推理线程数 |
| `-voice-tts-threads` | `2` | TTS 推理线程数 |
| `-voice-tts-speaker` | `0` | 默认 TTS 说话人 ID（0-52） |

### 环境变量

| 变量 | 对应 Flag |
|------|-----------|
| `VOICE_MODELS_DIR` | `-voice-models-dir` |
| `VOICE_ENABLED` | `-voice` |

---

## 语音 API

| 端点 | 说明 |
|------|------|
| `GET /api/voice/status` | 语音管线状态与能力（JSON） |
| `WS  /voice/ws?token=<jwt>` | 语音 WebSocket（PCM16 双向） |
| `GET /voice-test` | 浏览器测试页面 |

---

## 完整 Flag 列表

| Flag | 默认值 | 说明 |
|------|--------|------|
| `-port` | `8443` | 监听端口 |
| `-host` | `0.0.0.0` | 监听地址 |
| `-pin` | — | 配对 PIN（6 位数字） |
| `-workdir` | — | Claude Code 工作目录 |
| `-skills-path` | — | Skills 目录路径 |
| `-log` | — | 日志文件路径 |
| `-openclaw` | false | 启用 OpenClaw 集成 |
| `-openclaw-token` | — | OpenClaw 认证 Token |
| `-openclaw-url` | — | OpenClaw Gateway URL |
| `-allow-local-no-auth` | false | 本地请求跳过 JWT 验证 |
