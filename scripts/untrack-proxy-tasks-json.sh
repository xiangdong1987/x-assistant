#!/usr/bin/env bash
# 按计划 TASK-20260308 执行：从 Git 索引移除 proxy/data/tasks.json，保留本地文件
set -e
cd "$(dirname "$0")/.."

echo "1. 检查 proxy/data/tasks.json 是否被跟踪..."
if [ -n "$(git ls-files proxy/data/tasks.json 2>/dev/null)" ]; then
  echo "   文件当前被跟踪，执行从索引移除..."
  git rm --cached proxy/data/tasks.json
  echo "2. 提交变更..."
  git commit -m "修复: 将 proxy/data/tasks.json 从 Git 跟踪中移除"
  echo "完成。本地 proxy/data/tasks.json 已保留。"
else
  echo "   文件未被跟踪，无需操作。"
fi

echo ""
echo "验证: git ls-files proxy/data/tasks.json 应无输出"
git ls-files proxy/data/tasks.json || true
