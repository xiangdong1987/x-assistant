#!/bin/bash
# run-with-status.sh - 执行前/后通过 Proxy API 更新任务状态（阶段级：plan/coding/testing/submitting）
# 用法: TASK_API_URL=... TASK_API_TOKEN=... [TASK_PHASE=plan|code|test|done] run-with-status.sh <task_id> -- <command...>
# plan→planning/planned；code→coding/testing；test→testing/submitting；done→submitting/completed

TASK_ID="$1"
shift
while [ $# -gt 0 ] && [ "$1" != "--" ]; do shift; done
[ "$1" == "--" ] && shift
if [ $# -eq 0 ]; then
  echo "用法: run-with-status.sh <task_id> -- <command...>"
  exit 1
fi

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

# 开始时：按 TASK_PHASE 置为对应进行中状态，否则 inProgress
case "${TASK_PHASE:-}" in
  plan)  _task_status_put "planning" ;;
  code)  _task_status_put "coding" ;;
  test)  _task_status_put "testing" ;;
  done)  _task_status_put "submitting" ;;
  *)     _task_status_put "inProgress" ;;
esac

"$@"
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
  # 成功：标记 plan 文件当前阶段的 checklist 已完成，再置为下一阶段状态
  case "${TASK_PHASE:-}" in
    plan)  _task_mark_phase_complete "plan";  _task_status_put "planned" ;;
    code)  _task_mark_phase_complete "code";  _task_phase_advance "code";  _task_status_put "testing" ;;
    test)  _task_mark_phase_complete "test";  _task_phase_advance "test";  _task_status_put "submitting" ;;
    done)  _task_mark_phase_complete "done";  _task_phase_advance "done";  _task_status_put "completed" ;;
    *)     _task_status_put "completed" ;;
  esac
else
  _task_status_put "failed"
fi
_task_phase_release
exit "$EXIT_CODE"
