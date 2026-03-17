#!/bin/sh
# Build Go proxy.
# - BUILD_FOR_APP=1 (Xcode/Flutter): output to Runner/Resources。仅 Release 时签名（SIGN_FOR_APP=1），Debug 不签名避免子进程 trace trap。
# - Run manually: output to proxy/ 不签名，终端直接运行 ./proxy/xassistant-proxy -h 无 trace trap。

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$MACOS_DIR/.." && pwd)"
RESOURCES_DIR="$MACOS_DIR/Runner/Resources"
PROXY_DIR="$PROJECT_ROOT/proxy"

if [ -n "${BUILD_FOR_APP}" ]; then
  OUTPUT="$RESOURCES_DIR/xassistant-proxy"
  mkdir -p "$RESOURCES_DIR"
else
  OUTPUT="$PROXY_DIR/xassistant-proxy"
fi

cd "$PROXY_DIR"
go build -o "$OUTPUT" .

if [ -n "${BUILD_FOR_APP}" ] && [ -n "${SIGN_FOR_APP}" ]; then
  PROXY_ENTITLEMENTS="$MACOS_DIR/Runner/Proxy.entitlements"
  if [ -f "$PROXY_ENTITLEMENTS" ]; then
    codesign --force --sign - --entitlements "$PROXY_ENTITLEMENTS" "$OUTPUT" || echo "Warning: codesign failed (app may get Operation not permitted when starting proxy)"
  fi
fi
echo "Built proxy: $OUTPUT"
if [ -z "${BUILD_FOR_APP}" ]; then
  echo "Run: $OUTPUT -h"
fi
