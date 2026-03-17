#!/bin/bash
# stream-progress.sh - 调用 cursor agent 并展示 stream-json 进度（集成官方逻辑）
# 执行前/后按 TASK_PHASE 更新任务状态（code→coding/testing, test→testing/submitting, done→submitting/completed），与 run-with-status.sh 一致
# 用法: [TASK_PHASE=code|test|done] ./stream-progress.sh <plan_file_path> [project_dir]

PLAN_FILE="${1:-}"
PROJECT_DIR="${2:-$(pwd)}"

if [ -z "$PLAN_FILE" ]; then
  echo "用法: $0 <plan_file_path> [project_dir]"
  exit 1
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "❌ 计划文件不存在: $PLAN_FILE"
  exit 1
fi

# 从计划文件路径解析任务 ID（与 CCR 状态机联动，供 Proxy 任务体系展示）
TASK_ID=$(basename "$PLAN_FILE" .md | sed 's/^plan-//')
if [ -z "$TASK_ID" ]; then
  TASK_ID=""
fi

# 通知 Proxy 更新任务状态（与 task-status-states.md / CCR 一致）
_task_status_put() {
  local status="$1"
  [ -z "$TASK_API_URL" ] && return 0
  [ -z "$TASK_ID" ] && return 0
  local url="${TASK_API_URL%/}/api/tasks/${TASK_ID}"
  local auth="${TASK_API_TOKEN:-}"
  if [ -n "$auth" ]; then
    curl -s -X PUT -H "Content-Type: application/json" -H "Authorization: Bearer $auth" -d "{\"status\":\"$status\"}" "$url" >/dev/null || true
  else
    curl -s -X PUT -H "Content-Type: application/json" -d "{\"status\":\"$status\"}" "$url" >/dev/null || true
  fi
}

_task_mark_phase_complete() {
  local phase="$1"
  [ -z "$TASK_API_URL" ] && return 0
  [ -z "$TASK_ID" ] && return 0
  [ -z "$phase" ] && return 0
  local url="${TASK_API_URL%/}/api/tasks/${TASK_ID}/mark-phase-complete?phase=${phase}"
  local auth="${TASK_API_TOKEN:-}"
  if [ -n "$auth" ]; then
    curl -s -X POST -H "Authorization: Bearer $auth" "$url" >/dev/null || true
  else
    curl -s -X POST "$url" >/dev/null || true
  fi
}

_task_phase_advance() {
  local phase="$1"
  [ -z "$TASK_API_URL" ] && return 0
  [ -z "$TASK_ID" ] && return 0
  [ -z "$phase" ] && return 0
  local url="${TASK_API_URL%/}/api/tasks/${TASK_ID}/phase-advance?phase=${phase}"
  local auth="${TASK_API_TOKEN:-}"
  if [ -n "$auth" ]; then
    curl -s -X POST -H "Authorization: Bearer $auth" "$url" >/dev/null || true
  else
    curl -s -X POST "$url" >/dev/null || true
  fi
}

_task_phase_release() {
  [ -z "$TASK_API_URL" ] && return 0
  [ -z "$TASK_ID" ] && return 0
  local phase="${TASK_PHASE:-}"
  local url="${TASK_API_URL%/}/api/tasks/${TASK_ID}/phase-release"
  if [ -n "$phase" ]; then
    url="${url}?phase=${phase}"
  fi
  local auth="${TASK_API_TOKEN:-}"
  if [ -n "$auth" ]; then
    curl -s -X POST -H "Authorization: Bearer $auth" "$url" >/dev/null || true
  else
    curl -s -X POST "$url" >/dev/null || true
  fi
}

# 开始执行：按 TASK_PHASE 置为进行中状态，否则 inProgress
case "${TASK_PHASE:-}" in
  code)  _task_status_put "coding" ;;
  test)  _task_status_put "testing" ;;
  done)  _task_status_put "submitting" ;;
  *)     _task_status_put "inProgress" ;;
esac

echo "🚀 开始执行 cursor agent..."
echo "📋 计划: $(basename "$PLAN_FILE")"
echo "📂 项目: $PROJECT_DIR"
printf '%.0s─' {1..60}; echo ""

cd "$PROJECT_DIR"

char_count=0
tool_count=0
start_time=$(date +%s)

# 将 agent 的 stderr 暂存，失败时再输出
AGENT_STDERR=$(mktemp)
trap 'rm -f "$AGENT_STDERR"' EXIT

agent --output-format stream-json --stream-partial-output --trust \
  -p "请严格按照以下计划文件执行开发任务：

计划文件路径：$PLAN_FILE

$(cat "$PLAN_FILE")" 2>"$AGENT_STDERR" | \
while IFS= read -r line; do
  type=$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null)
  subtype=$(printf '%s' "$line" | jq -r '.subtype // empty' 2>/dev/null)

  case "$type" in
    "system")
      if [ "$subtype" = "init" ]; then
        model=$(printf '%s' "$line" | jq -r '.model // "unknown"' 2>/dev/null)
        echo "🤖 使用模型: $model"
      fi
      ;;

    "assistant")
      # 累积增量文本以实现流畅的进度显示
      text=$(printf '%s' "$line" | jq -r '.message.content[0].text // empty' 2>/dev/null)
      if [ -n "$text" ]; then
        char_count=${#text}
        
        # 旋转动画
        spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        spinner_idx=$(( (char_count / 5) % 10 ))
        spinner_char="${spinner_chars:$spinner_idx:1}"
        
        # 显示实时进度
        printf '\r\033[K   %s  📝 生成中: %d 字符' "$spinner_char" "$char_count"
      fi
      ;;

    "tool_call")
      # 清除动画行以打印新行
      printf '\r\033[K'
      
      if [ "$subtype" = "started" ]; then
        tool_count=$((tool_count + 1))

        # 提取工具信息并高亮不同类型的工具
        if echo "$line" | jq -e '.tool_call.writeToolCall' > /dev/null 2>&1; then
          path=$(printf '%s' "$line" | jq -r '.tool_call.writeToolCall.args.path // "unknown"' 2>/dev/null)
          echo -e "🔧 工具 #$tool_count: 创建/修改 $path"
        elif echo "$line" | jq -e '.tool_call.readToolCall' > /dev/null 2>&1; then
          path=$(printf '%s' "$line" | jq -r '.tool_call.readToolCall.args.path // "unknown"' 2>/dev/null)
          echo -e "📖 工具 #$tool_count: 读取 $path"
        elif echo "$line" | jq -e '.tool_call.runTerminalCommand' > /dev/null 2>&1; then
          cmd=$(printf '%s' "$line" | jq -r '.tool_call.runTerminalCommand.args.command // "unknown"' 2>/dev/null)
          echo -e "💻 工具 #$tool_count: 终端执行 \`$cmd\`"
        elif echo "$line" | jq -e '.tool_call.listDirectoryToolCall' > /dev/null 2>&1; then
          path=$(printf '%s' "$line" | jq -r '.tool_call.listDirectoryToolCall.args.path // "unknown"' 2>/dev/null)
          echo -e "� 工具 #$tool_count: 列出目录 $path"
        else
          # 未知类型捕捉 fallback
          echo -e "🔧 工具 #$tool_count: 调用中..."
        fi

      elif [ "$subtype" = "completed" ]; then
        # 提取并显示工具结果
        if echo "$line" | jq -e '.tool_call.writeToolCall.result.success' > /dev/null 2>&1; then
          lines=$(printf '%s' "$line" | jq -r '.tool_call.writeToolCall.result.success.linesCreated // 0' 2>/dev/null)
          size=$(printf '%s' "$line" | jq -r '.tool_call.writeToolCall.result.success.fileSize // 0' 2>/dev/null)
          echo "   ✅ 已创建/修改 $lines 行 ($size 字节)"
        elif echo "$line" | jq -e '.tool_call.readToolCall.result.success' > /dev/null 2>&1; then
          lines=$(printf '%s' "$line" | jq -r '.tool_call.readToolCall.result.success.totalLines // 0' 2>/dev/null)
          echo "   ✅ 已读取 $lines 行"
        elif echo "$line" | jq -e '.tool_call.runTerminalCommand.result' > /dev/null 2>&1; then
          ecode=$(printf '%s' "$line" | jq -r '.tool_call.runTerminalCommand.result.exitCode // "0"' 2>/dev/null)
          if [ "$ecode" = "0" ]; then
            echo "   ✅ 命令执行成功"
          else
            echo "   ❌ 执行失败(退出码 $ecode)"
          fi
        else
          is_error=$(printf '%s' "$line" | jq -r '.is_error // false' 2>/dev/null)
          if [ "$is_error" = "true" ]; then
            err=$(printf '%s' "$line" | jq -r '.content[0].text // ""' 2>/dev/null | head -c 120)
            echo "   ❌ 错误: $err"
          else
            echo "   ✅ 执行完毕"
          fi
        fi
      fi
      ;;

    "result")
      printf '\r\033[K'
      duration=$(printf '%s' "$line" | jq -r '.duration_ms // 0' 2>/dev/null)
      end_time=$(date +%s)
      total_time=$((end_time - start_time))

      echo ""
      echo -e "🎯 完成，Agent 耗时 ${duration}ms (脚本总计 ${total_time}s)"
      echo "📊 最终统计: $tool_count 个工具，生成 $char_count 字符"
      ;;
  esac
done

AGENT_EXIT=${PIPESTATUS[0]}
echo ""
if [ "$AGENT_EXIT" -ne 0 ]; then
  _task_status_put "failed"
  echo "❌ 执行失败 (agent 退出码: $AGENT_EXIT)"
  echo "   可能原因: 1) Agent 超时或中断 2) 计划步骤执行报错 3) Cursor CLI 未登录或异常"
  if [ -s "$AGENT_STDERR" ]; then
    echo "   Agent stderr:"
    cat "$AGENT_STDERR" | sed 's/^/   /'
  fi
  echo "   任务状态已更新为 failed，请根据上方错误排查后重试执行。"
  _task_phase_release
  exit "$AGENT_EXIT"
fi
# 成功：标记阶段完成并推进 phase，再置为下一阶段状态
case "${TASK_PHASE:-}" in
  code)  _task_mark_phase_complete "code";  _task_phase_advance "code";  _task_status_put "testing" ;;
  test)  _task_mark_phase_complete "test";  _task_phase_advance "test";  _task_status_put "submitting" ;;
  done)  _task_mark_phase_complete "done";  _task_phase_advance "done";  _task_status_put "completed" ;;
  *)     _task_status_put "completed" ;;
esac
_task_phase_release
echo "🏁 流式处理结束"
