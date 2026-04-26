#!/bin/bash
# Rule 1: .env 파일 수정 차단 (.env.example 제외)
# 대상 도구: Edit, Write

if [ "$TOOL_NAME" != "Edit" ] && [ "$TOOL_NAME" != "Write" ]; then
    exit 0
fi

FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null || echo "")
BASENAME=$(basename "$FILE_PATH" 2>/dev/null || echo "")

if [[ "$BASENAME" == .env* ]] && [[ "$BASENAME" != ".env.example" ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: modifying '"$BASENAME"' is not allowed. Use .env.example for templates."}}'
fi
