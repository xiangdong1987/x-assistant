#!/bin/bash
# stream-progress-plan.sh - 使用 stream-json 流式生成计划（与 stream-progress.sh 同风格）
# 执行前/后通过 Proxy API 更新任务状态 planning → planned / failed
# 用法: [TASK_PLAN_TITLE="标题"] [TASK_PLAN_DESC="描述"] [TASK_PLAN_TEMPLATE_PATH=/path/to/plan-template.md] ./stream-progress-plan.sh <task_id> <gen_task_id> <project_dir>
#   task_id     = Proxy 内部任务 ID，用于 PUT /api/tasks/{id} 状态
#   gen_task_id = 计划文件名与 prompt 用，如 TASK-20260308-xxx，产出 docs/plan-${gen_task_id}.md
#   project_dir = 项目目录，agent 在此目录下运行

TASK_ID="${1:-}"
GEN_TASK_ID="${2:-}"
PROJECT_DIR="${3:-$(pwd)}"
TITLE="${TASK_PLAN_TITLE:-}"
DESC="${TASK_PLAN_DESC:-$TITLE}"
TEMPLATE_PATH="${TASK_PLAN_TEMPLATE_PATH:-}"

if [ -z "$TASK_ID" ] || [ -z "$GEN_TASK_ID" ]; then
  echo "用法: $0 <task_id> <gen_task_id> <project_dir>"
  echo "  env: TASK_PLAN_TITLE, TASK_PLAN_DESC, TASK_PLAN_TEMPLATE_PATH 可选"
  exit 1
fi

# 通知 Proxy 更新任务状态
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

# 构建 prompt：若提供模板则要求严格按模板结构输出
build_prompt() {
  if [ -n "$TEMPLATE_PATH" ] && [ -f "$TEMPLATE_PATH" ]; then
    echo "Task ID: ${GEN_TASK_ID}"
    echo "Title: ${TITLE}"
    echo "Description: ${DESC}"
    echo ""
    echo "You MUST write the plan to file: docs/plan-${GEN_TASK_ID}.md"
    echo "The file MUST follow the structure below (replace {{placeholders}} with actual values for this task; keep all section headers and the meta block at the end)."
    echo "Use: {{taskId}}=${GEN_TASK_ID}, {{taskTitle}}=title above, {{description}}=description above, {{expectedOutput}}=derive from description, {{projectPath}}=${PROJECT_DIR}, and fill other placeholders as appropriate. status in meta must be 'planned', phase 'plan'."
    echo "You MAY add one optional section '## 分析与实现细节' between Overview and Execution Log for analysis and step-by-step implementation; the rest must match the template."
    echo "---BEGIN TEMPLATE---"
    cat "$TEMPLATE_PATH"
    echo "---END TEMPLATE---"
  else
    cat <<PROMPT
Task ID: ${GEN_TASK_ID}
Title: ${TITLE}
Description: ${DESC}

Please generate a comprehensive development plan for this task. The plan should include:
1. Analysis of current codebase structure
2. Implementation approach and architecture decisions
3. Detailed step-by-step implementation plan
4. Testing strategy
5. Potential risks and mitigation strategies

Please write plan to a file at docs/plan-${GEN_TASK_ID}.md following project's plan template format.
PROMPT
  fi
}

_task_status_put "planning"

echo "🚀 开始流式生成计划 (Cursor Agent)..."
echo "📋 任务: $GEN_TASK_ID"
echo "📂 项目: $PROJECT_DIR"
printf '%.0s─' {1..60}; echo ""

cd "$PROJECT_DIR" || exit 1

char_count=0
tool_count=0
start_time=$(date +%s)

AGENT_STDERR=$(mktemp)
trap 'rm -f "$AGENT_STDERR"' EXIT

PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT
build_prompt > "$PROMPT_FILE"

agent --output-format stream-json --stream-partial-output --trust \
  -p "$(cat "$PROMPT_FILE")" 2>"$AGENT_STDERR" | \
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
      text=$(printf '%s' "$line" | jq -r '.message.content[0].text // empty' 2>/dev/null)
      if [ -n "$text" ]; then
        char_count=${#text}
        spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        spinner_idx=$(( (char_count / 5) % 10 ))
        spinner_char="${spinner_chars:$spinner_idx:1}"
        printf '\r\033[K   %s  📝 生成中: %d 字符' "$spinner_char" "$char_count"
      fi
      ;;

    "tool_call")
      printf '\r\033[K'
      if [ "$subtype" = "started" ]; then
        tool_count=$((tool_count + 1))
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
          echo -e "📁 工具 #$tool_count: 列出目录 $path"
        else
          echo -e "🔧 工具 #$tool_count: 调用中..."
        fi
      elif [ "$subtype" = "completed" ]; then
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
      echo -e "🎯 计划生成完成，Agent 耗时 ${duration}ms (脚本总计 ${total_time}s)"
      echo "📊 统计: $tool_count 个工具，生成 $char_count 字符"
      ;;
  esac
done

AGENT_EXIT=${PIPESTATUS[0]}
echo ""
if [ "$AGENT_EXIT" -ne 0 ]; then
  _task_status_put "failed"
  echo "❌ 计划生成失败 (agent 退出码: $AGENT_EXIT)"
  if [ -s "$AGENT_STDERR" ]; then
    echo "错误输出:"
    cat "$AGENT_STDERR"
  fi
  exit "$AGENT_EXIT"
fi

PLAN_PATH="${PROJECT_DIR}/docs/plan-${GEN_TASK_ID}.md"
if [ ! -f "$PLAN_PATH" ]; then
  _task_status_put "failed"
  echo "❌ 计划文件未产出: $PLAN_PATH"
  exit 1
fi

_task_status_put "planned"
echo "🏁 流式计划生成结束: $PLAN_PATH"
exit 0
