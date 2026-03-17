#!/bin/bash
# stream-progress-claude.sh - 调用 claude CLI 并展示 stream-json 进度
# claude CLI stream-json 格式：
#   {"type":"system","subtype":"init","model":"..."}
#   {"type":"assistant","message":{"content":[{"type":"text","text":"..."},{"type":"tool_use","name":"Bash","input":{...}}]}}
#   {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"...","content":[{"type":"text","text":"..."}]}]}}
#   {"type":"result","subtype":"success","duration_ms":...,"is_error":false}
# 执行前/后按 TASK_PHASE 更新任务状态（与 stream-progress.sh 一致）
# 用法: [TASK_PHASE=plan|code|test|done] [CLAUDE_PHASE_PROMPT="..."] ./stream-progress-claude.sh <plan_file_path> [project_dir]

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

# 从计划文件路径解析任务 ID（plan-TASK-xxx.md → TASK-xxx）；TASK_ID env 可覆盖
if [ -z "${TASK_ID:-}" ]; then
  TASK_ID=$(basename "$PLAN_FILE" | sed 's/\.[^.]*$//' | sed 's/^plan-input-//' | sed 's/^plan-//')
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

# 开始执行：按 TASK_PHASE 置为进行中状态
case "${TASK_PHASE:-}" in
  plan)  _task_status_put "planning" ;;
  code)  _task_status_put "coding" ;;
  test)  _task_status_put "testing" ;;
  done)  _task_status_put "submitting" ;;
  *)     _task_status_put "inProgress" ;;
esac

echo "🚀 开始执行 claude agent..."
echo "📋 计划: $(basename "$PLAN_FILE")"
echo "📂 项目: $PROJECT_DIR"
printf '%.0s─' {1..60}; echo ""

cd "$PROJECT_DIR"

# Auto-build phase prompt from TASK_PHASE if CLAUDE_PHASE_PROMPT not explicitly set
if [ -z "${CLAUDE_PHASE_PROMPT:-}" ]; then
  PLAN_FILE_REF="${PLAN_FILE}"
  case "${TASK_PHASE:-}" in
    code)
      CLAUDE_PHASE_PROMPT="We are now in the Code phase. Read the plan file carefully and implement the coding tasks. As you complete each item, update the plan file by changing '- [ ]' to '- [x]' ONLY within the '### Code 阶段' section of Execution Log. Do NOT modify Test or Done checklist items. Do not add new features beyond the plan. Proceed automatically."
      ;;
    test)
      CLAUDE_PHASE_PROMPT="We are now in the Test phase. Execute the test plan, run tests, and fix any related bugs. As you complete each item, update the plan file by changing '- [ ]' to '- [x]' ONLY within the '### Test 阶段' section of Execution Log. Do NOT modify Code or Done checklist items. Do not add new features. Proceed automatically."
      ;;
    done)
      CLAUDE_PHASE_PROMPT="We are now in the Done phase. Review the changes, finalize the code, and auto commit the work. Write a Result Summary in the plan file. Update the plan file by changing '- [ ]' to '- [x]' ONLY within the '### Done 阶段' section of Execution Log. Proceed automatically."
      ;;
  esac
fi

# 构建 prompt：如有 CLAUDE_PHASE_PROMPT 则前置阶段约束指令
PLAN_CONTENT=$(cat "$PLAN_FILE")
if [ -n "${CLAUDE_PHASE_PROMPT:-}" ]; then
  FULL_PROMPT="${CLAUDE_PHASE_PROMPT}

---

${PLAN_CONTENT}"
else
  FULL_PROMPT="$PLAN_CONTENT"
fi

char_count=0
tool_count=0
start_time=$(date +%s)

CLAUDE_STDERR=$(mktemp)
trap 'rm -f "$CLAUDE_STDERR"' EXIT

# --include-partial-messages 实时流式输出；stream-json 按行输出 JSON 事件
claude --dangerously-skip-permissions --output-format stream-json --verbose --include-partial-messages -p "$FULL_PROMPT" 2>"$CLAUDE_STDERR" | \
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
      end_time=$(date +%s)
      total_time=$((end_time - start_time))
      duration=$(printf '%s' "$line" | jq -r '.duration_ms // 0' 2>/dev/null)
      echo ""
      echo "🎯 完成，耗时 ${duration}ms (脚本总计 ${total_time}s)"
      echo "📊 最终统计: $tool_count 个工具，生成 $char_count 字符"
      ;;
  esac
done

CLAUDE_EXIT=${PIPESTATUS[0]}
echo ""
if [ "$CLAUDE_EXIT" -ne 0 ]; then
  _task_status_put "failed"
  echo "❌ 执行失败 (claude 退出码: $CLAUDE_EXIT)"
  if [ -s "$CLAUDE_STDERR" ]; then
    echo "   Claude stderr:"
    cat "$CLAUDE_STDERR" | sed 's/^/   /'
  fi
  _task_phase_release
  exit "$CLAUDE_EXIT"
fi

# 成功：标记阶段完成并推进 phase，再置为下一阶段状态
case "${TASK_PHASE:-}" in
  plan)  _task_mark_phase_complete "plan";  _task_status_put "planned" ;;
  code)  _task_mark_phase_complete "code";  _task_phase_advance "code";  _task_status_put "testing" ;;
  test)  _task_mark_phase_complete "test";  _task_phase_advance "test";  _task_status_put "submitting" ;;
  done)  _task_mark_phase_complete "done";  _task_phase_advance "done";  _task_status_put "completed" ;;
  *)     _task_status_put "completed" ;;
esac
_task_phase_release
echo "🏁 执行结束"
