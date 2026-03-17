#!/bin/bash

# Claude Voice Proxy 启动脚本
# 自动检测 Cursor 位置并启动服务器

set -e

echo "🚀 启动 Claude Voice Proxy 服务器"

# 检查是否在正确的目录
if [ ! -f "main.go" ]; then
    echo "错误: 请在 proxy 目录中运行此脚本"
    exit 1
fi

# 默认 Cursor 路径
CURSOR_PATH="cursor"

# 尝试查找 Cursor
if [ ! -x "$(command -v cursor)" ]; then
    # 检查常见的安装位置
    if [ -f "/Applications/Cursor.app/Contents/MacOS/Cursor" ]; then
        CURSOR_PATH="/Applications/Cursor.app/Contents/MacOS/Cursor"
        echo "✅ 找到 Cursor 在: $CURSOR_PATH"
    elif [ -f "$HOME/Applications/Cursor.app/Contents/MacOS/Cursor" ]; then
        CURSOR_PATH="$HOME/Applications/Cursor.app/Contents/MacOS/Cursor"
        echo "✅ 找到 Cursor 在: $CURSOR_PATH"
    else
        echo "⚠️  警告: 未找到 Cursor"
        echo ""
        echo "请确保 Cursor 已安装。您可以从以下位置下载:"
        echo "  https://cursor.sh"
        echo ""
        echo "或者手动指定 Cursor 路径:"
        echo "  ./start_server.sh /path/to/cursor"
        echo ""
        read -p "是否继续尝试? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    echo "✅ Cursor 已在 PATH 中找到"
fi

# 如果提供了参数，使用指定的路径
if [ $# -eq 1 ]; then
    CURSOR_PATH="$1"
    echo "使用指定的 Cursor 路径: $CURSOR_PATH"
fi

# 检查 Cursor 是否存在
if [ "$CURSOR_PATH" != "cursor" ] && [ ! -f "$CURSOR_PATH" ]; then
    echo "❌ 错误: Cursor 不存在于: $CURSOR_PATH"
    exit 1
fi

echo ""
echo "📋 服务器配置:"
echo "  Cursor 路径: $CURSOR_PATH"
echo "  传输方式: stdio"
echo "  端口: 8443"
echo "  主机: 0.0.0.0"
echo ""

echo "🔄 启动服务器..."
echo "按 Ctrl+C 停止服务器"
echo ""

# 启动服务器
go run main.go \
    --mcp-transport=stdio \
    --mcp-cursor-path="$CURSOR_PATH" \
    --port=8443 \
    --host=0.0.0.0