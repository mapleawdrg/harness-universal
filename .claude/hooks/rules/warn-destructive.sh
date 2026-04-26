#!/bin/bash
# Rule 3: 파괴적 명령 경고 (빌드 아티팩트 삭제는 예외)
# 대상 도구: Bash

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null || echo "")

# 예외: 빌드 아티팩트 삭제 (안전한 rm -rf)
# node_modules, __pycache__, dist, .cache, build, .pytest_cache, .ruff_cache
if echo "$COMMAND" | grep -qE 'rm\s+-rf?\s+.*(node_modules|__pycache__|dist/|\.cache|build/|\.pytest_cache|\.ruff_cache)'; then
    exit 0
fi

# 파괴적 명령 감지
# git push --force: --force가 어느 위치에 오더라도 감지 (git push origin branch --force 포함)
if echo "$COMMAND" | grep -qE '(rm\s+-rf\s|DROP\s+TABLE|DROP\s+DATABASE|git\s+push\s+.*--force(\s|$)|git\s+push\s+-f(\s|$)|git\s+reset\s+--hard|TRUNCATE\s+TABLE)'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Destructive operation detected. This may cause irreversible data loss. Approve?"}}'
    exit 0
fi
