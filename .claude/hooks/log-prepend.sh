#!/bin/bash
# log-prepend.sh — 로그 파일 최상단(헤더 바로 아래)에 entry 삽입
#
# Usage: echo "entry text" | log-prepend.sh <file> [header_lines]
#        cat << 'EOF' | log-prepend.sh wiki/log.md
#        ## [ING-0002 | pending | Active] 2026-04-24 — @llm: title
#        - body
#        EOF
#
# header_lines: 보존할 상단 라인 수 (기본 1 — "# Title" 한 줄)
#               YAML frontmatter 있으면 frontmatter 끝줄까지 포함해 명시

set -euo pipefail

FILE="${1:-}"
HEADER_LINES="${2:-1}"

[ -z "$FILE" ] && { echo "Usage: $0 <file> [header_lines]" >&2; exit 1; }
[ ! -f "$FILE" ] && { echo "File not found: $FILE" >&2; exit 1; }

# stdin에서 entry 내용 읽기
ENTRY=$(cat)
[ -z "$ENTRY" ] && { echo "Empty stdin — nothing to prepend" >&2; exit 1; }

TMP=$(mktemp)
trap "rm -f $TMP" EXIT

{
    head -n "$HEADER_LINES" "$FILE"
    echo ""
    echo "$ENTRY"
    echo ""
    tail -n +$((HEADER_LINES + 1)) "$FILE"
} > "$TMP"

mv "$TMP" "$FILE"
trap - EXIT
