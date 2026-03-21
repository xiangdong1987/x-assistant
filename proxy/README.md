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

下载完成后目录结构：

```
models/
├── vad/
│   └── silero_vad.onnx          # Silero VAD (~2MB)
├── stt/
│   ├── encoder.int8.onnx        # Zipformer 双语 zh-en
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

### 语音相关 Flag

| Flag | 默认值 | 说明 |
|------|--------|------|
| `-voice` | false | 启用语音流水线 |
| `-voice-models-dir` | `./models` | 模型文件目录 |
| `-voice-vad-threshold` | `0.5` | VAD 检测阈值（0.0-1.0） |
| `-voice-vad-silence-ms` | `500` | 静音多少毫秒后结束一句话 |
| `-voice-stt-threads` | `2` | STT 推理线程数 |
| `-voice-tts-threads` | `2` | TTS 推理线程数 |
| `-voice-tts-speaker` | `0` | 默认 TTS 说话人 ID（0-52） |

### 语音 API

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