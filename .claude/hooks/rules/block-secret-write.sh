#!/bin/bash
# Rule 5: 코드에 시크릿 하드코딩 감지 (AWS, GitHub, Stripe, DB URL)
# 대상 도구: Edit, Write

if [ "$TOOL_NAME" != "Edit" ] && [ "$TOOL_NAME" != "Write" ]; then
    exit 0
fi

# new_string (Edit) 또는 content (Write) 확인
CONTENT=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('new_string', '') or d.get('content', ''))
" 2>/dev/null || echo "")

# AWS Access Key (AKIA로 시작하는 20자 영숫자)
if echo "$CONTENT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: AWS Access Key detected in code. Use environment variables instead."}}'
    exit 0
fi

# GitHub Personal Access Token (ghp_, ghs_, gho_, github_pat_)
if echo "$CONTENT" | grep -qE '(ghp_|ghs_|gho_|github_pat_)[A-Za-z0-9_]{20,}'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: GitHub token detected in code. Use environment variables instead."}}'
    exit 0
fi

# Stripe Secret Key (sk_live_, rk_live_)
if echo "$CONTENT" | grep -qE '(sk_live_|rk_live_)[A-Za-z0-9]{20,}'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: Stripe secret key detected in code. Use environment variables instead."}}'
    exit 0
fi

# DB Connection URL with password (postgresql://, mysql://)
if echo "$CONTENT" | grep -qE '(postgresql|mysql|mongodb)://[^:]+:[^@]{6,}@'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Database URL with credentials detected. Make sure this is not a real password. Approve?"}}'
    exit 0
fi
