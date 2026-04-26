#!/bin/bash
# post-change-tracker.sh — PostToolUse: 변경된 파일 추적 (graphify 연동용)
# Input: stdin (tool call JSON) → Output: 없음 (사이드이펙트만)
# graphify가 설치된 경우, 변경 파일 목록을 .harness/changed-files.log에 기록

set -euo pipefail

INPUT=$(cat 2>/dev/null || echo "{}")

FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', d)
    print(inp.get('file_path', ''))
except:
    print('')
" 2>/dev/null || echo "")

[ -z "$FILE_PATH" ] && exit 0

# .harness/ 디렉토리가 있는 프로젝트에서만 기록
HARNESS_DIR="${HARNESS_DIR_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null)/.harness}"
[ ! -d "$HARNESS_DIR" ] && exit 0

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $FILE_PATH" >> "${HARNESS_DIR}/changed-files.log"

# Turn 단위 변경 누적 (Stop 훅이 읽고 비움). 경로만 기록.
PROJECT_ROOT_FOR_TURN="${PROJECT_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
REL_FOR_TURN=$(python3 -c "
import os, sys
try:
    print(os.path.relpath(sys.argv[1], sys.argv[2]))
except:
    print(sys.argv[1])
" "$FILE_PATH" "$PROJECT_ROOT_FOR_TURN" 2>/dev/null || echo "$FILE_PATH")
echo "$REL_FOR_TURN" >> "${HARNESS_DIR}/.turn-files"

# Wiki 소스 변경 감지 — docs/, README, CLAUDE.md, .harness/, graphify-out/ 변경 시 트리거
PROJECT_ROOT="${PROJECT_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
REL_PATH=$(python3 -c "
import os, sys
try:
    print(os.path.relpath(sys.argv[1], sys.argv[2]))
except:
    print(sys.argv[1])
" "$FILE_PATH" "$PROJECT_ROOT" 2>/dev/null || echo "$FILE_PATH")

WIKI_PATTERN="\.harness/|^docs/|README\.|CLAUDE\.md|CHANGELOG\.|CONTRIBUTING\.|^graphify-out/"
if echo "$REL_PATH" | grep -qE "$WIKI_PATTERN"; then
    echo "$REL_PATH" >> "${HARNESS_DIR}/.wiki-pending" 2>/dev/null || true
fi
