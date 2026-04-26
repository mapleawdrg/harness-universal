#!/bin/bash
# Rule 4: 시크릿 읽기 차단 (cat .env, echo $KEY, printenv 등)
# 대상 도구: Bash

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null || echo "")

# cat/head/tail로 .env 파일 읽기
if echo "$COMMAND" | grep -qE '(cat|head|tail|less|more|bat)\s+.*\.env(\s|$|[^e])'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: reading .env file content is not allowed. Use os.getenv() in code instead."}}'
    exit 0
fi

# printenv / env (환경변수 전체 출력)
if echo "$COMMAND" | grep -qE '^\s*(printenv|env)\s*$'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: dumping all environment variables may expose secrets."}}'
    exit 0
fi

# echo $SECRET_KEY / echo ${API_KEY} 패턴 (언더스코어 포함 대문자 환경변수 — PATH/HOME 등 시스템 변수 제외)
if echo "$COMMAND" | grep -qE 'echo\s+\$\{?[A-Z][A-Z0-9]*_[A-Z0-9_]+\}?'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This command may print a secret environment variable. Approve?"}}'
    exit 0
fi
