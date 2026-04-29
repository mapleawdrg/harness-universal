#!/bin/bash
# Requires: bash 4.0+, python3 (stdlib json)
# session-summary.sh — Stop 훅: 세션 종료 시 .harness/ 상태 요약 출력
# Input: 없음 → Output: stdout (Claude가 마지막으로 보는 메시지)
#
# 매니페스트(.claude/agents-manifest.json)의 expected_output 패턴을 읽어
# phase-scoped 파일들을 glob으로 매칭한다. 매니페스트 부재 시 legacy 이름 fallback.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
HARNESS_DIR="${HARNESS_DIR_OVERRIDE:-${REPO_ROOT}/.harness}"
[ ! -d "$HARNESS_DIR" ] && exit 0

MANIFEST="${HARNESS_MANIFEST_OVERRIDE:-${REPO_ROOT}/.claude/agents-manifest.json}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "세션 종료 — .harness/ 상태 요약"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 매니페스트에서 expected_output 패턴 목록 추출 (phase-scoped는 *로 치환해 glob)
PATTERNS_AND_NAMES=""
if [ -f "$MANIFEST" ]; then
    PATTERNS_AND_NAMES="$(python3 -u <<PY 2>/dev/null || echo "")
import json
with open("$MANIFEST") as f:
    data = json.load(f)
agents = data.get("agents", {})
for name, spec in agents.items():
    out = spec.get("expected_output", "")
    if "{PHASE}" in out:
        glob_pat = out.replace("{PHASE}", "*")
        print(f"{name}|{glob_pat}|phase-scoped")
    elif out:
        print(f"{name}|{out}|fixed")
PY
"
fi

# Fallback: 매니페스트 없을 때 legacy + 표준 이름
if [ -z "$PATTERNS_AND_NAMES" ]; then
    PATTERNS_AND_NAMES="$(printf '%s\n' \
        "product-designer|product-design-p*.md|phase-scoped" \
        "product-reviewer|product-review-p*.md|phase-scoped" \
        "architect|architect-design-p*.md|phase-scoped" \
        "architect-reviewer|architect-review-p*.md|phase-scoped" \
        "planner|sprint-contract-p*.md|phase-scoped" \
        "plan-reviewer|plan-review-p*.md|phase-scoped" \
        "dev|dev-report-p*.md|phase-scoped" \
        "qa|qa-report-p*.md|phase-scoped" \
        "explain|error-log.md|fixed")"
fi

# 산출물 확인 및 출력
while IFS='|' read -r AGENT PATTERN KIND; do
    [ -z "$AGENT" ] && continue
    # shellcheck disable=SC2206
    if [ "$KIND" = "phase-scoped" ]; then
        # glob 매치된 파일 중 가장 최신 1건 + 매치 갯수
        MATCHES=$(compgen -G "${HARNESS_DIR}/${PATTERN}" 2>/dev/null || true)
        if [ -z "$MATCHES" ]; then
            printf "  [없음] %-22s (pattern: %s)\n" "$AGENT" "$PATTERN"
        else
            COUNT=$(echo "$MATCHES" | wc -l | tr -d ' ')
            LATEST=$(echo "$MATCHES" | xargs -r ls -1t 2>/dev/null | head -1)
            BASE=$(basename "$LATEST")
            MTIME=$(date -r "$LATEST" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "?")
            printf "  [존재] %-22s %s (%s, %d phase)\n" "$AGENT" "$BASE" "$MTIME" "$COUNT"
        fi
    else
        FULL="${HARNESS_DIR}/${PATTERN}"
        if [ -f "$FULL" ]; then
            MTIME=$(date -r "$FULL" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "?")
            printf "  [존재] %-22s %s (%s)\n" "$AGENT" "$PATTERN" "$MTIME"
        else
            printf "  [없음] %-22s (%s)\n" "$AGENT" "$PATTERN"
        fi
    fi
done <<< "$PATTERNS_AND_NAMES"

# 추가: decisions-log + changed-files 카운트
if [ -f "${HARNESS_DIR}/decisions-log.md" ]; then
    MTIME=$(date -r "${HARNESS_DIR}/decisions-log.md" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "?")
    printf "  [존재] %-22s %s (%s)\n" "decisions-log" "decisions-log.md" "$MTIME"
fi
if [ -f "${HARNESS_DIR}/changed-files.log" ]; then
    COUNT=$(wc -l < "${HARNESS_DIR}/changed-files.log" | tr -d ' ')
    echo ""
    echo "이번 세션 변경 파일: ${COUNT}개"
fi

# .turn-files 리셋
TURN_FILES="${HARNESS_DIR}/.turn-files"
[ -f "$TURN_FILES" ] && : > "$TURN_FILES"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
