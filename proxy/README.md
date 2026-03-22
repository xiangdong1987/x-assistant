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
bash start.sh
```

或手动指定参数：

```bash
CGO_ENABLED=1 go run main.go \
  --openclaw \
  --openclaw-token="<your-token>" \
  --allow-local-no-auth \
  --skills-path="../skills" \
  -voice \
  -voice-models-dir ./models
```

> `CGO_ENABLED=1` 是语音功能必须的，Sherpa-ONNX 依赖 CGO。

---

## 语音功能

### 下载模型（约 400MB，仅需运行一次）

```bash
bash models/download.sh
```

下载完成后默认目录结构：

```
models/
├── vad/
│   └── silero_vad.onnx          # Silero VAD (~2MB)
├── stt/                         # 默认 STT 目录（Zipformer 双语 zh-en）
│   ├── encoder.int8.onnx
│   ├── decoder.int8.onnx
│   ├── joiner.int8.onnx
│   └── tokens.txt
└── tts/
    ├── model.onnx               # Kokoro 多语言 TTS
    ├── voices.bin
    ├── tokens.txt
    ├── lexicon.txt
    └── espeak-ng-data/
```

---

## STT 模型切换

### 支持的模型类型

| 类型 | 识别方式 | 代表模型 | 特点 |
|------|----------|----------|------|
| `zipformer` | 流式（实时局部文字） | Zipformer 双语 | 低延迟，英文较强 |
| `paraformer` | 批量（整段识别） | Paraformer-zh | 中文准确率高 |
| `whisper` | 批量（整段识别） | Whisper tiny/small/large | 多语言，准确率高 |

### 模型类型自动检测

程序启动时自动检测 STT 目录中的模型类型，检测顺序：

1. **`type.txt`**（优先）：目录内放一个文件，内容为 `zipformer` / `paraformer` / `whisper`
2. **文件启发式**：
   - 有 `encoder.int8.onnx` + `decoder.int8.onnx` + `joiner.int8.onnx` → `zipformer`
   - 有 `model.int8.onnx` 或 `model.onnx` → `paraformer`
   - 有 `encoder.onnx` + `decoder.onnx` → `whisper`

### 切换单个模型

```bash
# 使用中文 Paraformer
CGO_ENABLED=1 go run main.go -voice -voice-stt-dir ./models/stt-paraformer-zh

# 使用 Whisper
CGO_ENABLED=1 go run main.go -voice -voice-stt-dir ./models/stt-whisper
```

### 同时加载多个模型（并行识别，取最长结果）

`-voice-stt-dir` 可重复指定，所有模型并行跑，自动选最长的识别结果：

```bash
CGO_ENABLED=1 go run main.go -voice \
  -voice-stt-dir ./models/stt-zipformer-en \
  -voice-stt-dir ./models/stt-paraformer-zh
```

> 多模型场景适合中英混合输入：英文走 Zipformer，中文走 Paraformer，取字数最多的结果。

### Paraformer 中文模型下载示例

```bash
mkdir -p models/stt-paraformer-zh
cd models/stt-paraformer-zh
# 从 sherpa-onnx releases 下载 Paraformer zh 模型（约 220MB）
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-2023-09-14.tar.bz2
tar xf sherpa-onnx-paraformer-zh-2023-09-14.tar.bz2 --strip-components=1
echo "paraformer" > type.txt
```

### Whisper 模型下载示例

```bash
mkdir -p models/stt-whisper-zh
cd models/stt-whisper-zh
# 从 sherpa-onnx releases 下载 Whisper 模型
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2
tar xf sherpa-onnx-whisper-tiny.tar.bz2 --strip-components=1
echo "zh" > language.txt   # Whisper 语言提示
echo "whisper" > type.txt
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
