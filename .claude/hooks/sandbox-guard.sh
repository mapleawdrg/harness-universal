#!/bin/bash
# sandbox-guard.sh — Claude Code PreToolUse 메인 라우터
# 역할: tool call JSON 파싱 → rules/ 디렉토리 순차 실행 → 첫 deny/ask에서 즉시 반환
# Install: ~/.claude/hooks/sandbox-guard.sh
# No hardcoded paths. No external dependencies (python3 required for JSON parsing).

set -euo pipefail

# Read tool call JSON from stdin (한 번만 읽기)
INPUT=$(cat)

# --- JSON 파싱 (python3 필수) ---
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
TOOL_INPUT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('tool_input',{})))" 2>/dev/null || echo "{}")

# 환경변수로 export (rules/ 스크립트가 참조)
export TOOL_NAME
export TOOL_INPUT

# --- rules/ 디렉토리 경로 결정 ---
# 설치 위치: ~/.claude/hooks/rules/ 또는 동일 디렉토리 내 rules/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_DIR="${SCRIPT_DIR}/rules"

# rules/ 없으면 경고 없이 allow (graceful degradation)
if [ ! -d "$RULES_DIR" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# --- 개별 비활성화 지원 ---
# HARNESS_RULE_DISABLE=block-env-modify,warn-transmission 처럼 설정하면 해당 규칙 건너뜀
DISABLED_RULES="${HARNESS_RULE_DISABLE:-}"

# --- 규칙 순차 실행 ---
# 파일명 기준 정렬 (block-env-modify → warn-transmission → ... 알파벳 순)
for RULE_FILE in $(ls "${RULES_DIR}"/*.sh 2>/dev/null | sort); do
    RULE_NAME=$(basename "$RULE_FILE" .sh)

    # 비활성화 체크 (쉼표 구분 파일명 목록)
    if [ -n "$DISABLED_RULES" ]; then
        if echo ",$DISABLED_RULES," | grep -q ",${RULE_NAME},"; then
            continue
        fi
    fi

    # 규칙 실행 (환경변수로 TOOL_NAME, TOOL_INPUT 전달)
    RESULT=$(bash "$RULE_FILE" 2>/dev/null || echo "")

    if [ -z "$RESULT" ]; then
        continue
    fi

    # deny 또는 ask 결정이면 즉시 반환
    DECISION=$(echo "$RESULT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    o = d.get('hookSpecificOutput', {})
    print(o.get('permissionDecision', 'allow'))
except:
    print('allow')
" 2>/dev/null || echo "allow")

    if [ "$DECISION" = "deny" ] || [ "$DECISION" = "ask" ]; then
        echo "$RESULT"
        exit 0
    fi
done

# 모든 규칙 통과 → allow
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
