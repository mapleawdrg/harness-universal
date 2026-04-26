#!/bin/bash
# wiki-ingest.sh — SubagentStop 훅: 변경 감지 + additionalContext 반환
# wiki-ingest.py의 JSON stdout을 그대로 전달하여
# Claude가 변경 감지 시 자동으로 /wiki ingest를 실행하도록 한다.

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
INGEST_SCRIPT="${REPO_ROOT}/.claude/skills/llm-wiki/wiki-ingest.py"

[ ! -f "$INGEST_SCRIPT" ] && exit 0

python3 "$INGEST_SCRIPT" "$REPO_ROOT" 2>/dev/null
