#!/bin/bash
# Rule 8: 코드 인젝션 패턴 경고 (eval, exec, innerHTML, pickle, dangerouslySetInnerHTML)
# 대상 도구: Edit, Write

if [ "$TOOL_NAME" != "Edit" ] && [ "$TOOL_NAME" != "Write" ]; then
    exit 0
fi

CONTENT=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('new_string', '') or d.get('content', ''))
" 2>/dev/null || echo "")

FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null || echo "")

# Python eval() / exec() — 사용자 입력이 들어올 수 있는 컨텍스트
if echo "$CONTENT" | grep -qE 'eval\(|exec\('; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"eval() or exec() detected. These functions can execute arbitrary code if user input reaches them. Approve only if input is trusted."}}'
    exit 0
fi

# dangerouslySetInnerHTML (React XSS)
if echo "$CONTENT" | grep -q 'dangerouslySetInnerHTML'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"dangerouslySetInnerHTML detected. This can cause XSS if content is not sanitized. Approve?"}}'
    exit 0
fi

# innerHTML 직접 할당
if echo "$CONTENT" | grep -qE '\.innerHTML\s*='; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"innerHTML assignment detected. Use textContent or a sanitizer library to prevent XSS. Approve?"}}'
    exit 0
fi

# Python pickle.loads (untrusted data deserialization)
if echo "$CONTENT" | grep -qE 'pickle\.loads?\('; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"pickle.load/loads detected. Deserializing untrusted data with pickle can execute arbitrary code. Approve?"}}'
    exit 0
fi
