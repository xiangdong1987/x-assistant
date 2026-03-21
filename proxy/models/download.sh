#!/usr/bin/env bash
# Download voice models for the proxy voice pipeline.
# Run from the proxy root: bash models/download.sh
#
# Total download: ~400MB
# Models:
#   - Silero VAD (offline voice activity detection)
#   - Streaming Zipformer bilingual zh-en (STT)
#   - Kokoro multi-lang v1.0 (TTS, 54 speakers)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAD_DIR="$SCRIPT_DIR/vad"
STT_DIR="$SCRIPT_DIR/stt"
TTS_DIR="$SCRIPT_DIR/tts"

mkdir -p "$VAD_DIR" "$STT_DIR" "$TTS_DIR"

# ─── Utility ────────────────────────────────────────────────────────────────

download() {
  local url="$1"
  local dest="$2"
  if [ -f "$dest" ]; then
    echo "[skip] $(basename "$dest") already exists"
    return
  fi
  echo "[download] $(basename "$dest")"
  curl -L --progress-bar -o "$dest" "$url"
}

# ─── VAD: Silero VAD v4 ─────────────────────────────────────────────────────
echo ""
echo "=== VAD: Silero VAD ==="
download \
  "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx" \
  "$VAD_DIR/silero_vad.onnx"

# ─── STT: Streaming Zipformer bilingual zh-en ────────────────────────────────
echo ""
echo "=== STT: Streaming Zipformer bilingual zh-en ==="
STT_ARCHIVE="sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2"
STT_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$STT_ARCHIVE"

if [ ! -f "$STT_DIR/tokens.txt" ]; then
  TMP="$(mktemp -d)"
  echo "[download] $STT_ARCHIVE (~90MB)"
  curl -L --progress-bar -o "$TMP/$STT_ARCHIVE" "$STT_URL"
  echo "[extract] $STT_ARCHIVE"
  tar -xjf "$TMP/$STT_ARCHIVE" -C "$TMP"
  MODEL_DIR="$(find "$TMP" -maxdepth 2 -name "tokens.txt" | head -1 | xargs dirname)"
  cp "$MODEL_DIR"/encoder-epoch-99-avg-1.int8.onnx "$STT_DIR/encoder.int8.onnx"
  cp "$MODEL_DIR"/decoder-epoch-99-avg-1.int8.onnx "$STT_DIR/decoder.int8.onnx"
  cp "$MODEL_DIR"/joiner-epoch-99-avg-1.int8.onnx  "$STT_DIR/joiner.int8.onnx"
  cp "$MODEL_DIR/tokens.txt" "$STT_DIR/tokens.txt"
  rm -rf "$TMP"
  echo "[done] STT models extracted to $STT_DIR"
else
  echo "[skip] STT models already exist"
fi

# ─── TTS: Kokoro multi-lang v1.0 ────────────────────────────────────────────
echo ""
echo "=== TTS: Kokoro multi-lang v1.0 ==="
TTS_ARCHIVE="kokoro-multi-lang-v1_0.tar.bz2"
TTS_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$TTS_ARCHIVE"

if [ ! -f "$TTS_DIR/model.onnx" ]; then
  TMP="$(mktemp -d)"
  echo "[download] $TTS_ARCHIVE (~310MB)"
  curl -L --progress-bar -o "$TMP/$TTS_ARCHIVE" "$TTS_URL"
  echo "[extract] $TTS_ARCHIVE"
  tar -xjf "$TMP/$TTS_ARCHIVE" -C "$TMP"
  MODEL_DIR="$(find "$TMP" -maxdepth 2 -name "model.onnx" | head -1 | xargs dirname)"
  cp "$MODEL_DIR/model.onnx"   "$TTS_DIR/model.onnx"
  cp "$MODEL_DIR/voices.bin"   "$TTS_DIR/voices.bin"
  [ -f "$MODEL_DIR/tokens.txt" ] && cp "$MODEL_DIR/tokens.txt"  "$TTS_DIR/tokens.txt"  || touch "$TTS_DIR/tokens.txt"
  [ -f "$MODEL_DIR/lexicon.txt" ] && cp "$MODEL_DIR/lexicon.txt" "$TTS_DIR/lexicon.txt" || touch "$TTS_DIR/lexicon.txt"
  rm -rf "$TMP"
  echo "[done] TTS models extracted to $TTS_DIR"
else
  echo "[skip] TTS models already exist"
fi

echo ""
echo "=== All models ready ==="
echo "  VAD : $VAD_DIR/silero_vad.onnx"
echo "  STT : $STT_DIR/{encoder,decoder,joiner}.int8.onnx + tokens.txt"
echo "  TTS : $TTS_DIR/model.onnx + voices.bin"
echo ""
echo "Start with voice enabled:"
echo "  go run . -voice -voice-models-dir ./models"
