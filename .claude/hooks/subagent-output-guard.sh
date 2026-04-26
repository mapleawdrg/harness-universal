#!/bin/bash
# Requires: bash 4.0+, python3 (stdlib json), git
# subagent-output-guard.sh — SubagentStop: 에이전트 출력 파일 검증
# 에이전트 종료 시 State Handoff 파일이 생성됐는지 확인한다.
# 매핑은 .claude/agents-manifest.json 에서 읽는다 (없으면 legacy case 문 fallback).

set -euo pipefail

INPUT=$(cat 2>/dev/null || echo "{}")

AGENT_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('agent_name', d.get('name', '')))
except:
    print('')
" 2>/dev/null || echo "")

[ -z "$AGENT_NAME" ] && exit 0

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
HARNESS_DIR="${HARNESS_DIR_OVERRIDE:-${REPO_ROOT}/.harness}"
[ ! -d "$HARNESS_DIR" ] && exit 0

# PHASE 추출: agent 호출 메시지 첫 줄 "Phase: P{N}" 또는 세션 전역 env
# Manifest 기반 매니페스트 경로
MANIFEST="${HARNESS_MANIFEST_OVERRIDE:-${REPO_ROOT}/.claude/agents-manifest.json}"

resolve_expected_from_manifest() {
    local agent="$1"
    local phase="${HARNESS_PHASE:-}"
    [ ! -f "$MANIFEST" ] && return 1
    python3 - "$agent" "$phase" "$MANIFEST" <<'PY' 2>/dev/null || return 1
import json, sys, re, glob, os
agent, phase, manifest_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(manifest_path) as f:
    data = json.load(f)
spec = data.get("agents", {}).get(agent)
if not spec:
    sys.exit(1)
out = spec.get("expected_output", "")
if "{PHASE}" in out:
    if phase:
        # strip leading P (P4.5 -> 4.5)
        p = phase[1:] if phase.startswith("P") else phase
        out = out.replace("{PHASE}", p)
    else:
        # glob: find any matching phase artifact in .harness/
        pat = out.replace("{PHASE}", "*")
        print(f"GLOB:{pat}")
        sys.exit(0)
print(out)
PY
}

EXPECTED_RAW="$(resolve_expected_from_manifest "$AGENT_NAME" || true)"

# Fallback: legacy case 문 (manifest 없을 때)
if [ -z "$EXPECTED_RAW" ]; then
    case "$AGENT_NAME" in
        architect)          EXPECTED_RAW="architect-output.md" ;;
        architect-reviewer) EXPECTED_RAW="review-report.md" ;;
        planner)            EXPECTED_RAW="sprint-contract.md" ;;
        dev)                EXPECTED_RAW="dev-report.md" ;;
        qa)                 EXPECTED_RAW="qa-report.md" ;;
        explain)            EXPECTED_RAW="error-log.md" ;;
        *)                  exit 0 ;;
    esac
fi

warn_missing() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[SubagentStop 경고] @${AGENT_NAME} 종료"
    echo "기대 출력 파일 없음: .harness/${1}"
    echo "State Handoff를 완료하지 않았을 수 있습니다."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

if [[ "$EXPECTED_RAW" == GLOB:* ]]; then
    PATTERN="${EXPECTED_RAW#GLOB:}"
    # shellcheck disable=SC2086
    if ! compgen -G "${HARNESS_DIR}/${PATTERN}" > /dev/null; then
        warn_missing "${PATTERN}"
    fi
else
    if [ ! -f "${HARNESS_DIR}/${EXPECTED_RAW}" ]; then
        warn_missing "${EXPECTED_RAW}"
    fi
fi
