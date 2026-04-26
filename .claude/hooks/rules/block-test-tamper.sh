#!/bin/bash
# block-test-tamper.sh — 테스트 변조 감지 규칙 (Rule 9)
# Input: $TOOL_NAME, $TOOL_INPUT (env) → Output: JSON ask/allow
# 탐지: assert 제거, pytest.skip 삽입, @pytest.mark.skip 추가, test_ 함수 내 조기 return

TOOL_NAME="${TOOL_NAME:-}"
: "${TOOL_INPUT:={}}"

# Edit 또는 Write 도구만 검사
if [ "$TOOL_NAME" != "Edit" ] && [ "$TOOL_NAME" != "Write" ]; then
    exit 0
fi

# 대상 파일 경로 추출
FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('file_path', ''))
" 2>/dev/null || echo "")

# 테스트 파일이 아니면 pass
case "$FILE_PATH" in
    *test_*.py|*/tests/*.py|*_test.py) ;;
    *) exit 0 ;;
esac

# 변경 내용 추출 (Edit: new_string, Write: content)
CONTENT=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('new_string', d.get('content', '')))
" 2>/dev/null || echo "")

# 변조 패턴 탐지
REASON=""

# assert → pass 교체 패턴
if echo "$CONTENT" | grep -qE '^\s*pass\s*$|^\s*\.\.\.\s*$'; then
    # old_string에 assert가 있었는지 확인
    OLD=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('old_string', ''))
" 2>/dev/null || echo "")
    if echo "$OLD" | grep -q 'assert'; then
        REASON="assert 구문이 pass/...로 교체될 수 있습니다"
    fi
fi

# pytest.skip 삽입
if echo "$CONTENT" | grep -qE 'pytest\.skip\(|pytest\.mark\.skip'; then
    REASON="pytest.skip 또는 @pytest.mark.skip이 추가됩니다"
fi

# test_ 함수 맨 앞에 return 삽입 (테스트 무력화)
if echo "$CONTENT" | python3 -c "
import sys, re
content = sys.stdin.read()
# test_ 함수 본문 첫 줄이 return인 패턴
if re.search(r'def test_\w+[^:]*:\s*\n\s+return\b', content):
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    REASON="test_ 함수 본문 첫 줄에 return이 추가됩니다 (테스트 무력화)"
fi

if [ -z "$REASON" ]; then
    exit 0
fi

cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"[테스트 변조 감지] ${REASON}\n파일: ${FILE_PATH}\n테스트를 무력화하는 변경인지 확인하세요."}}
EOF
