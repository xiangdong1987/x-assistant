#!/bin/bash

# 关机脚本 - 支持 macOS (darwin)
# 用法: ./shutdown.sh now | ./shutdown.sh <分钟数>

set -e

case "$(uname -s)" in
    Darwin)
        if [[ "$1" == "now" || -z "$1" ]]; then
            echo "正在关机..."
            sudo shutdown -h now
        elif [[ "$1" =~ ^[0-9]+$ ]]; then
            echo "将在 $1 分钟后关机，可使用 sudo shutdown -c 取消"
            sudo shutdown -h +"$1"
        else
            echo "用法: $0 now | $0 <分钟数>"
            echo "  now     - 立即关机"
            echo "  <分钟数> - 指定分钟后关机"
            exit 1
        fi
        ;;
    Linux)
        if [[ "$1" == "now" || -z "$1" ]]; then
            echo "正在关机..."
            sudo shutdown -h now
        elif [[ "$1" =~ ^[0-9]+$ ]]; then
            echo "将在 $1 分钟后关机，可使用 sudo shutdown -c 取消"
            sudo shutdown -h +"$1"
        else
            echo "用法: $0 now | $0 <分钟数>"
            echo "  now     - 立即关机"
            echo "  <分钟数> - 指定分钟后关机"
            exit 1
        fi
        ;;
    *)
        echo "不支持的操作系统: $(uname -s)"
        exit 1
        ;;
esac
