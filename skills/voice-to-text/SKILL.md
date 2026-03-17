---
name: voice-to-text
description: >
  Google Speech-to-Text 语音转录工具。接收音频文件路径，返回转录文字。
  不含 Telegram/Claude，纯工具层，由 OpenClaw 调用后将结果交给 Italian Tutor 处理。
  当需要将语音文件转为文字时使用。
metadata:
  openclaw:
    emoji: 🎤
    requires:
      anyBins: ["node"]
---

# 🎤 Voice-to-Text — 语音转录工具

## 职责

只做一件事：**音频文件 → 转录文字**。

OpenClaw 是大脑，负责调用此工具并将结果传递给 Italian Tutor 或其他技能。

```
音频文件 (.ogg / .mp3 / .wav)
        ↓
  Google Speech-to-Text API
        ↓
  HANDOFF: { transcript, language }
        ↓
  OpenClaw → Italian Tutor
```

---

## 调用方式

```bash
# 基本用法
node scripts/transcribe.js <audio_file_path> [language]

# 示例：转录意大利语
node scripts/transcribe.js /tmp/voice.ogg it-IT

# 输出（stdout）
HANDOFF:{"transcript":"buongiorno, come stai?","language":"it-IT"}
```

### 支持格式

| 扩展名 | 编码 |
|--------|------|
| `.ogg` / `.opus` | OGG_OPUS (48000 Hz) |
| `.mp3` | MP3 |
| `.flac` | FLAC |
| `.wav` | LINEAR16 |

### 支持语言

默认 `it-IT`，同时检测 `zh-CN` / `en-US` 作为备选。

---

## 配置

在 `skills/voice-to-text/.env` 中设置：

```env
GOOGLE_SPEECH_API_KEY=AIzaSyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

获取方式：Google Cloud Console → APIs & Services → Credentials → 启用 Cloud Speech-to-Text API → 创建 API Key

---

## 无外部依赖

只使用 Node.js 内置模块（`https`、`fs`），无需 `npm install`。
