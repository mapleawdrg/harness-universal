#!/bin/bash
# Rule 6: 보호 파일 수정 차단 (.pem, .key, .ssh/, credentials.json, package-lock.json)
# 대상 도구: Edit, Write

if [ "$TOOL_NAME" != "Edit" ] && [ "$TOOL_NAME" != "Write" ]; then
    exit 0
fi

FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null || echo "")

# 인증서/키 파일
if echo "$FILE_PATH" | grep -qE '\.(pem|key|p12|pfx|cer|crt)$'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: modifying certificate/key files is not allowed."}}'
    exit 0
fi

# .ssh/ 디렉토리
if echo "$FILE_PATH" | grep -q '\.ssh/'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: modifying SSH directory files is not allowed."}}'
    exit 0
fi

# credentials.json, service-account*.json
BASENAME=$(basename "$FILE_PATH" 2>/dev/null || echo "")
if [[ "$BASENAME" == "credentials.json" ]] || echo "$BASENAME" | grep -qE '^service-account.*\.json$'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: modifying credential files is not allowed."}}'
    exit 0
fi

# package-lock.json (직접 수정 방지 — npm install이 담당)
if [[ "$BASENAME" == "package-lock.json" ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"package-lock.json should be managed by npm install, not edited directly. Approve manual edit?"}}'
    exit 0
fi
