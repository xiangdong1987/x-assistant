#!/bin/bash
# stream-progress-plan-claude.sh - 使用 claude CLI 流式生成计划
# 执行前/后通过 Proxy API 更新任务状态 planning → planned / failed
# 用法: [TASK_PLAN_TITLE="标题"] [TASK_PLAN_DESC="描述"] [TASK_PLAN_TEMPLATE_PATH=/path/to/plan-template.md] ./stream-progress-plan-claude.sh <task_id> <gen_task_id> <project_dir>
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

echo "🚀 开始流式生成计划 (Claude)..."
echo "📋 任务: $GEN_TASK_ID"
echo "📂 项目: $PROJECT_DIR"
printf '%.0s─' {1..60}; echo ""

cd "$PROJECT_DIR" || exit 1

char_count=0
tool_count=0
start_time=$(date +%s)

CLAUDE_STDERR=$(mktemp)
trap 'rm -f "$CLAUDE_STDERR"' EXIT

PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT
build_prompt > "$PROMPT_FILE"

# --include-partial-messages 实时流式输出；stream-json 按行输出 JSON 事件
claude --dangerously-skip-permissions --output-format stream-json --verbose --include-partial-messages -p "$(cat "$PROMPT_FILE")" 2>"$CLAUDE_STDERR" | \
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
      # content 是数组，遍历各 block
      content_len=$(printf '%s' "$line" | jq '.message.content | length' 2>/dev/null)
      [ -z "$content_len" ] && continue
      i=0
      while [ "$i" -lt "$content_len" ]; do
        block_type=$(printf '%s' "$line" | jq -r ".message.content[$i].type" 2>/dev/null)

        if [ "$block_type" = "text" ]; then
          text=$(printf '%s' "$line" | jq -r ".message.content[$i].text // empty" 2>/dev/null)
          if [ -n "$text" ]; then
            char_count=${#text}
            spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
            spinner_idx=$(( (char_count / 5) % 10 ))
            spinner_char="${spinner_chars:$spinner_idx:1}"
            printf '\r\033[K   %s  📝 生成中: %d 字符' "$spinner_char" "$char_count"
          fi

        elif [ "$block_type" = "tool_use" ]; then
          printf '\r\033[K'
          tool_count=$((tool_count + 1))
          tool_name=$(printf '%s' "$line" | jq -r ".message.content[$i].name // empty" 2>/dev/null)
          tool_input=$(printf '%s' "$line" | jq -c ".message.content[$i].input // {}" 2>/dev/null)
          case "$tool_name" in
            Write | create_file)
              fpath=$(printf '%s' "$tool_input" | jq -r '.path // .file_path // "unknown"' 2>/dev/null)
              echo "🔧 工具 #$tool_count: 创建/修改 $fpath"
              ;;
            Read | read_file)
              fpath=$(printf '%s' "$tool_input" | jq -r '.path // .file_path // "unknown"' 2>/dev/null)
              echo "📖 工具 #$tool_count: 读取 $fpath"
              ;;
            Edit | str_replace_based_edit_tool)
              fpath=$(printf '%s' "$tool_input" | jq -r '.path // .file_path // "unknown"' 2>/dev/null)
              echo "✏️  工具 #$tool_count: 编辑 $fpath"
              ;;
            Bash | bash)
              cmd=$(printf '%s' "$tool_input" | jq -r '.command // "unknown"' 2>/dev/null | head -c 80)
              echo "💻 工具 #$tool_count: \`$cmd\`"
              ;;
            Glob | glob)
              pat=$(printf '%s' "$tool_input" | jq -r '.pattern // "unknown"' 2>/dev/null)
              echo "📁 工具 #$tool_count: Glob $pat"
              ;;
            Grep | grep)
              pat=$(printf '%s' "$tool_input" | jq -r '.pattern // .query // "unknown"' 2>/dev/null)
              echo "🔍 工具 #$tool_count: Grep \`$pat\`"
              ;;
            *)
              echo "🔧 工具 #$tool_count: $tool_name"
              ;;
          esac
        fi

        i=$((i + 1))
      done
      ;;

    "user")
      # tool_result 来自 user 消息
      content_len=$(printf '%s' "$line" | jq '.message.content | length' 2>/dev/null)
      [ -z "$content_len" ] && continue
      i=0
      while [ "$i" -lt "$content_len" ]; do
        block_type=$(printf '%s' "$line" | jq -r ".message.content[$i].type" 2>/dev/null)
        if [ "$block_type" = "tool_result" ]; then
          is_error=$(printf '%s' "$line" | jq -r ".message.content[$i].is_error // false" 2>/dev/null)
          if [ "$is_error" = "true" ]; then
            err=$(printf '%s' "$line" | jq -r ".message.content[$i].content[0].text // \"\"" 2>/dev/null | head -c 120)
            echo "   ❌ 错误: $err"
          else
            echo "   ✅ 完成"
          fi
        fi
        i=$((i + 1))
      done
      ;;

    "result")
      printf '\r\033[K'
      duration=$(printf '%s' "$line" | jq -r '.duration_ms // 0' 2>/dev/null)
      end_time=$(date +%s)
      total_time=$((end_time - start_time))
      echo ""
      echo "🎯 计划生成完成，Claude 耗时 ${duration}ms (脚本总计 ${total_time}s)"
      echo "📊 统计: $tool_count 个工具，生成 $char_count 字符"
      ;;
  esac
done

CLAUDE_EXIT=${PIPESTATUS[0]}
echo ""
if [ "$CLAUDE_EXIT" -ne 0 ]; then
  _task_status_put "failed"
  echo "❌ 计划生成失败 (claude 退出码: $CLAUDE_EXIT)"
  if [ -s "$CLAUDE_STDERR" ]; then
    echo "错误输出:"
    cat "$CLAUDE_STDERR"
  fi
  exit "$CLAUDE_EXIT"
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
