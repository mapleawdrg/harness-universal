#!/bin/bash
# Rule 7: main/master 브랜치에 직접 git push 차단
# 대상 도구: Bash

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null || echo "")

# git push origin main 또는 git push origin master (force push는 Rule 3에서 이미 처리)
if echo "$COMMAND" | grep -qE 'git\s+push\s+[^\s]*\s+(main|master)(\s|$)'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Direct push to main/master detected. Are you sure? Consider using a feature branch and PR instead."}}'
    exit 0
fi

# git push (브랜치 미지정, 현재 브랜치가 main일 수 있음)
if echo "$COMMAND" | grep -qE 'git\s+push\s+origin\s*$'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"git push without branch name — if current branch is main/master, this pushes to production. Approve?"}}'
    exit 0
fi
