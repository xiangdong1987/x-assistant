#!/usr/bin/env bash
# Start the Claude Voice Proxy with voice pipeline enabled.
# Usage: bash start.sh
#
# Override via environment variables:
#   OPENCLAW_TOKEN   OpenClaw authentication token
#   VOICE_MODELS_DIR Path to voice model files (default: ./models)
#   PORT             Server port (default: 8443)
#   SKILLS_PATH      Skills directory (default: ../skills)

set -euo pipefail
cd "$(dirname "$0")"

PORT="${PORT:-8443}"
SKILLS_PATH="${SKILLS_PATH:-../skills}"
VOICE_MODELS_DIR="${VOICE_MODELS_DIR:-./models}"
OPENCLAW_TOKEN="${OPENCLAW_TOKEN:-a209a8575433805d2078a6519eae190934fff456dbd70d76}"

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
  -voice-models-dir "$VOICE_MODELS_DIR"
