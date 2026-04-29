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
    PATTERNS_AND_NAMES="$(MANIFEST_PATH="$MANIFEST" python3 -u - <<'PY' 2>/dev/null || true
import json, os
path = os.environ["MANIFEST_PATH"]
with open(path) as f:
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
)"
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

# Transparency: 매니페스트 + 가장 최근 산출물 mtime 으로 다음 추천 에이전트 추정
if [ -f "$MANIFEST" ]; then
    HINT="$(MANIFEST_PATH="$MANIFEST" HARNESS_DIR_HINT="$HARNESS_DIR" python3 -u - <<'PY' 2>/dev/null || true
import json, os, glob
manifest_path = os.environ["MANIFEST_PATH"]
harness = os.environ["HARNESS_DIR_HINT"]
with open(manifest_path) as f:
    data = json.load(f)
agents = data.get("agents", {})

# 각 에이전트의 가장 최근 산출물 mtime 매핑
latest = {}  # agent_name -> (mtime, file)
for name, spec in agents.items():
    out = spec.get("expected_output", "")
    pattern = out.replace("{PHASE}", "*") if "{PHASE}" in out else out
    if not pattern:
        continue
    paths = glob.glob(os.path.join(harness, pattern))
    if not paths:
        continue
    paths.sort(key=os.path.getmtime, reverse=True)
    latest[name] = (os.path.getmtime(paths[0]), os.path.basename(paths[0]))

if not latest:
    print("INIT|@product-designer 또는 @architect — 첫 사이클 시작")
    raise SystemExit(0)

# 가장 최근 활동한 에이전트
last_agent = max(latest.items(), key=lambda kv: kv[1][0])[0]
last_file = latest[last_agent][1]

# 다음 추천: manifest의 next/next_on_pass 사용
spec = agents[last_agent]
next_hint = spec.get("next") or spec.get("next_on_pass") or "(complete or user judgment)"

print(f"FLOW|마지막 활동: @{last_agent} → {last_file}")
print(f"NEXT|다음 추천: @{next_hint}  (manifest 기반 — verdict가 PASS 인 경우)")
PY
)"
    if [ -n "$HINT" ]; then
        echo ""
        echo "$HINT" | while IFS='|' read -r KIND TEXT; do
            case "$KIND" in
                INIT) echo "  → $TEXT" ;;
                FLOW) echo "  · $TEXT" ;;
                NEXT) echo "  → $TEXT" ;;
            esac
        done
    fi
fi

# .turn-files 리셋
TURN_FILES="${HARNESS_DIR}/.turn-files"
[ -f "$TURN_FILES" ] && : > "$TURN_FILES"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
