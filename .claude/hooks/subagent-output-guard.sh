#!/bin/bash
# Requires: bash 4.0+, python3 (stdlib json), git
# subagent-output-guard.sh — SubagentStop: 에이전트 출력 파일 검증
#
# 역할: 서브에이전트 종료 시 State Handoff 파일(.harness/{expected}.md)이 생성됐는지 확인.
# 매핑은 .claude/agents-manifest.json 에서 읽고, 없으면 legacy case 문 fallback.
#
# Claude Code SubagentStop event payload 스키마 (공식):
#   - hook_event_name: "SubagentStop"
#   - agent_id: 서브에이전트 고유 ID
#   - agent_type: 에이전트 타입 (커스텀 에이전트명 — 우리 매니페스트의 키)
#   - agent_transcript_path: 서브에이전트 자신의 JSONL transcript 경로
#   - last_assistant_message: 에이전트 최종 응답
#   - session_id, transcript_path, cwd, stop_hook_active
# Source: https://code.claude.com/docs/en/hooks.md
#
# PHASE 해석 우선순위:
#   1) HARNESS_PHASE env (수동 override, 최우선)
#   2) agent_transcript_path JSONL 첫 user message에서 'Phase: P{N}' grep
#   3) 못 찾으면 PHASE-scoped artifact는 명시적 경고 + glob fallback (silent pass 금지)

set -euo pipefail

INPUT=$(cat 2>/dev/null || echo "{}")

# 1. Payload 파싱: agent_type 우선 (공식 필드), 호환을 위해 agent_name/name 도 시도
AGENT_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # 공식 필드는 agent_type. agent_name/name 은 구버전 호환.
    print(d.get('agent_type', d.get('agent_name', d.get('name', ''))))
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$AGENT_NAME" ] && exit 0

# 2. agent_transcript_path 추출 (PHASE 추론에 사용)
AGENT_TRANSCRIPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('agent_transcript_path', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
HARNESS_DIR="${HARNESS_DIR_OVERRIDE:-${REPO_ROOT}/.harness}"
[ ! -d "$HARNESS_DIR" ] && exit 0

MANIFEST="${HARNESS_MANIFEST_OVERRIDE:-${REPO_ROOT}/.claude/agents-manifest.json}"

# 3. PHASE 추론 함수
extract_phase_from_transcript() {
    local transcript="$1"
    [ -z "$transcript" ] || [ ! -f "$transcript" ] && return 1
    # JSONL 첫 user message → content → 'Phase: P{N}' regex
    python3 - "$transcript" <<'PY' 2>/dev/null
import sys, json, re
path = sys.argv[1]
try:
    with open(path) as f:
        for line in f:
            try:
                msg = json.loads(line)
            except Exception:
                continue
            if msg.get('type') == 'user':
                content = msg.get('message', {}).get('content', '')
                # content 가 list of blocks 인 경우 (Claude API format) 처리
                if isinstance(content, list):
                    text = ' '.join(b.get('text', '') for b in content if isinstance(b, dict))
                else:
                    text = str(content)
                m = re.search(r'Phase:\s*(P[\w.\-]+)', text)
                if m:
                    print(m.group(1))
                    sys.exit(0)
                # 첫 user message 본 후 PHASE 못 찾았으면 종료 (그 이후는 follow-up)
                break
except Exception:
    pass
sys.exit(1)
PY
}

# PHASE 결정: env override → transcript 추론 → 빈값
PHASE="${HARNESS_PHASE:-}"
if [ -z "$PHASE" ] && [ -n "$AGENT_TRANSCRIPT" ]; then
    PHASE="$(extract_phase_from_transcript "$AGENT_TRANSCRIPT" 2>/dev/null || echo "")"
fi

# 4. Manifest 에서 expected_output 해석
resolve_expected_from_manifest() {
    local agent="$1"
    local phase="$2"
    [ ! -f "$MANIFEST" ] && return 1
    python3 - "$agent" "$phase" "$MANIFEST" <<'PY' 2>/dev/null || return 1
import json, sys
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
        # PHASE 미확인 — glob 으로 fallback 하지만 호출자가 NO_PHASE 표식 처리
        pat = out.replace("{PHASE}", "*")
        print(f"NO_PHASE_GLOB:{pat}")
        sys.exit(0)
print(out)
PY
}

EXPECTED_RAW="$(resolve_expected_from_manifest "$AGENT_NAME" "$PHASE" || true)"

# 5. Fallback: legacy case 문 (manifest 없을 때)
if [ -z "$EXPECTED_RAW" ]; then
    case "$AGENT_NAME" in
        product-designer)   EXPECTED_RAW="product-design.md" ;;
        product-reviewer)   EXPECTED_RAW="product-review.md" ;;
        architect)          EXPECTED_RAW="architect-design.md" ;;
        architect-reviewer) EXPECTED_RAW="architect-review.md" ;;
        planner)            EXPECTED_RAW="sprint-contract.md" ;;
        plan-reviewer)      EXPECTED_RAW="plan-review.md" ;;
        dev)                EXPECTED_RAW="dev-report.md" ;;
        qa)                 EXPECTED_RAW="qa-report.md" ;;
        explain)            EXPECTED_RAW="error-log.md" ;;
        *)                  exit 0 ;;
    esac
fi

# 6. 검증 + 경고 (silent pass 금지)
warn_box() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[SubagentStop 경고] @${AGENT_NAME} 종료"
    echo "$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

if [[ "$EXPECTED_RAW" == NO_PHASE_GLOB:* ]]; then
    # PHASE 미확인 — phase-scoped artifact 인데 phase 가 없음.
    # silent pass 금지: 명시적 경고 후 임의 매칭 fallback 도 시도(안전망).
    PATTERN="${EXPECTED_RAW#NO_PHASE_GLOB:}"
    warn_box "PHASE 메타데이터를 추출하지 못했습니다.
원인: agent 호출 첫 메시지에 'Phase: P{N}' 라인이 없거나 transcript 파일을 읽지 못함.
영향: phase-scoped 산출물(${PATTERN})을 PHASE 단위로 검증할 수 없습니다.
임시 매칭: ${HARNESS_DIR}/${PATTERN} 의 임의 일치 파일로 fallback 합니다.
권장 조치: agent 호출 시 첫 줄에 'Phase: P{N}' 명시 또는 HARNESS_PHASE env 설정."
    if ! compgen -G "${HARNESS_DIR}/${PATTERN}" > /dev/null 2>&1; then
        warn_box "기대 출력 파일 없음 (PHASE 미확인 + glob 매치 0건): .harness/${PATTERN}
State Handoff 미완료 가능성. 사용자 확인 필요."
    fi
elif [ ! -f "${HARNESS_DIR}/${EXPECTED_RAW}" ]; then
    warn_box "기대 출력 파일 없음: .harness/${EXPECTED_RAW}
State Handoff 미완료 가능성. agent 본문의 State Handoff 섹션 확인."
fi

# SubagentStop 은 observational. 차단 대신 stderr 경고만.
exit 0
