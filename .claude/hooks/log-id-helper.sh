#!/bin/bash
# log-id-helper.sh — 다음 sequential ID 자동 할당
# Usage: log-id-helper.sh DEC  →  DEC-0043
#        log-id-helper.sh ING  →  ING-0012
#        log-id-helper.sh SRC  →  SRC-0256

TYPE="$1"
[ -z "$TYPE" ] && { echo "Usage: $0 {DEC|ING|SRC|REV|QA}" >&2; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not in git repo" >&2; exit 1; }

# 해당 TYPE entry 중 최대 4자리 NNNN 추출 → +1
# Scope: .harness/, wiki/ 하위 모든 .md 파일
MAX=$(grep -hroE "\[${TYPE}-[0-9]{4}" \
        "${REPO_ROOT}/.harness" \
        "${REPO_ROOT}/wiki" 2>/dev/null \
      | grep -oE "[0-9]{4}" \
      | sort -n \
      | tail -1)

NEXT=$(printf "%04d" $((10#${MAX:-0} + 1)))
echo "${TYPE}-${NEXT}"
