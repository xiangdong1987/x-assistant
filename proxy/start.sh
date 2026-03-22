#!/usr/bin/env bash
# Start the Claude Voice Proxy with voice pipeline enabled.
# Usage: bash start.sh
#
# Override via environment variables:
#   OPENCLAW_TOKEN   OpenClaw authentication token（本地开发可使用任意非空字符串，
#                    因为 --allow-local-no-auth 已跳过本地请求的 JWT 验证）
#   VOICE_MODELS_DIR Path to voice model files (default: ./models)
#   PORT             Server port (default: 8443)
#   SKILLS_PATH      Skills directory (default: ../skills)

set -euo pipefail
cd "$(dirname "$0")"

PORT="${PORT:-8443}"
SKILLS_PATH="${SKILLS_PATH:-../skills}"
VOICE_MODELS_DIR="${VOICE_MODELS_DIR:-./models}"
if [ -z "${OPENCLAW_TOKEN:-}" ]; then
  echo "Error: OPENCLAW_TOKEN is required. Set it via environment variable:"
  echo "  OPENCLAW_TOKEN=<token> bash start.sh"
  echo ""
  echo "Note: 本地开发可使用任意非空字符串作为 token，例如："
  echo "  OPENCLAW_TOKEN=dev bash start.sh"
  exit 1
fi

# Check models exist
if [ ! -f "$VOICE_MODELS_DIR/vad/silero_vad.onnx" ]; then
  echo "[warn] Voice models not found. Run: bash models/download.sh"
fi

echo "Starting proxy on port $PORT (voice: $VOICE_MODELS_DIR) ..."

CGO_ENABLED=1 go run main.go \
  --openclaw \
  --openclaw-token="$OPENCLAW_TOKEN" \
  --allow-local-no-auth \
  --skills-path="$SKILLS_PATH" \
  --port="$PORT" \
  -voice \
  -voice-models-dir "$VOICE_MODELS_DIR" \
  -voice-stt-dir "$VOICE_MODELS_DIR/stt"
