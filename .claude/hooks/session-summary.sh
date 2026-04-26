#!/bin/bash
# session-summary.sh — Stop 훅: 세션 종료 시 .harness/ 상태 요약 출력
# Input: 없음 → Output: stdout (Claude가 마지막으로 보는 메시지)

set -euo pipefail

HARNESS_DIR="${HARNESS_DIR_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null)/.harness}" 2>/dev/null || exit 0
[ ! -d "$HARNESS_DIR" ] && exit 0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "세션 종료 — .harness/ 상태 요약"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for FILE in architect-output review-report sprint-contract dev-report qa-report decisions-log; do
    PATH_FULL="${HARNESS_DIR}/${FILE}.md"
    if [ -f "$PATH_FULL" ]; then
        MODIFIED=$(date -r "$PATH_FULL" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
        echo "  [존재] ${FILE}.md (${MODIFIED})"
    else
        echo "  [없음] ${FILE}.md"
    fi
done

if [ -f "${HARNESS_DIR}/changed-files.log" ]; then
    COUNT=$(wc -l < "${HARNESS_DIR}/changed-files.log" | tr -d ' ')
    echo ""
    echo "이번 세션 변경 파일: ${COUNT}개"
fi

# .turn-files 리셋 (기존 turn auto-log 블록 제거됨 — change-log.md 폐지, DEC-0003)
TURN_FILES="${HARNESS_DIR}/.turn-files"
[ -f "$TURN_FILES" ] && : > "$TURN_FILES"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
