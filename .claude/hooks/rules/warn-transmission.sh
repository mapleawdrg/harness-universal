#!/bin/bash
# Rule 2: 외부 데이터 전송 경고 (curl, wget, nc, scp, rsync + pipe-to-bash)
# 대상 도구: Bash

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null || echo "")

# pipe-to-bash 패턴 (가장 위험 — 먼저 체크)
if echo "$COMMAND" | grep -qE '(curl|wget)[^|]*\|[^|]*(bash|sh|zsh|python|node)'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"pipe-to-bash detected: downloading and executing remote code. Approve only if you trust the source."}}'
    exit 0
fi

# 외부 네트워크 전송 명령
if echo "$COMMAND" | grep -qE '(curl\s|wget\s|nc\s+-[^h]|ncat\s|scp\s+[^-].*:|rsync\s+[^-].*:)'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This command may send data to an external server. Approve?"}}'
    exit 0
fi
