#!/bin/bash
# Requires: bash 4.0+, python3, sed
# init-project.sh — 신규 프로젝트 이식 후 1회 실행. harness.config.json 값을 읽어
# 에이전트 본문의 generic placeholder를 프로젝트 고유 값으로 치환.
#
# 동작:
#   1. .claude/harness.config.json 읽기
#   2. 본문의 placeholder 토큰을 config 값으로 sed 치환:
#        {{actor_role}}     → config.actor_role
#        {{project_name}}   → config.project_name
#        {{roadmap_doc}}    → config.roadmap_doc (null이면 그대로)
#   3. 치환 결과를 git diff로 보여주고 사용자 확인 후 적용 (--apply)
#
# Usage:
#   .claude/scripts/init-project.sh           # dry-run (변경 미리보기)
#   .claude/scripts/init-project.sh --apply   # 실제 치환
#
# 안전성:
#   - {lint_cmd}/{test_cmd}/{coverage_cmd} 같이 에이전트가 런타임에 채우는 토큰은 건드리지 않음.
#   - 치환 대상은 명시적으로 {{double-brace}} 형태만.
#   - config 값에 sed 메타문자(/, &) 포함 시 자동 escape.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../.." && pwd)")"
CONFIG="${REPO_ROOT}/.claude/harness.config.json"
APPLY=0

for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        -h|--help)
            head -25 "$0" | grep -E "^# ?" | sed 's/^# \?//'
            exit 0
            ;;
    esac
done

[ ! -f "$CONFIG" ] && { echo "Error: $CONFIG not found." >&2; exit 1; }

# config 값 추출 (Python으로 안전하게)
read -r PROJECT_NAME ACTOR_ROLE ROADMAP_DOC SCENARIO_ID_PATTERN < <(
    python3 - "$CONFIG" <<'PY'
import json, sys, shlex
cfg = json.load(open(sys.argv[1]))
def safe(v):
    if v is None: return ""
    return str(v).replace("'", "'\"'\"'")
print(shlex.quote(safe(cfg.get("project_name", ""))),
      shlex.quote(safe(cfg.get("actor_role", ""))),
      shlex.quote(safe(cfg.get("roadmap_doc", ""))),
      shlex.quote(safe(cfg.get("scenario_id_pattern", ""))))
PY
)
# shlex.quote 결과를 다시 평가
PROJECT_NAME=$(eval echo "$PROJECT_NAME")
ACTOR_ROLE=$(eval echo "$ACTOR_ROLE")
ROADMAP_DOC=$(eval echo "$ROADMAP_DOC")
SCENARIO_ID_PATTERN=$(eval echo "$SCENARIO_ID_PATTERN")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "init-project.sh — placeholder 치환"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "config 값:"
echo "  project_name        = ${PROJECT_NAME:-(empty)}"
echo "  actor_role          = ${ACTOR_ROLE:-(empty)}"
echo "  roadmap_doc         = ${ROADMAP_DOC:-(null/empty)}"
echo "  scenario_id_pattern = ${SCENARIO_ID_PATTERN:-(null/empty)}"
echo ""

# sed 메타문자 escape
sed_escape() {
    printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

ACTOR_ESC=$(sed_escape "$ACTOR_ROLE")
PROJECT_ESC=$(sed_escape "$PROJECT_NAME")
ROADMAP_ESC=$(sed_escape "$ROADMAP_DOC")
SCENARIO_ESC=$(sed_escape "$SCENARIO_ID_PATTERN")

# 치환 대상 파일 (에이전트 본문 + _shared)
TARGETS=$(find "${REPO_ROOT}/.claude/agents" -name "*.md" 2>/dev/null)

if [ $APPLY -eq 0 ]; then
    echo "[DRY-RUN] 변경될 파일과 치환 위치:"
    echo ""
    found=0
    for f in $TARGETS; do
        if grep -nE '\{\{(actor_role|project_name|roadmap_doc|scenario_id_pattern)\}\}' "$f" >/dev/null 2>&1; then
            echo "── $f"
            grep -nE '\{\{(actor_role|project_name|roadmap_doc|scenario_id_pattern)\}\}' "$f" | sed 's/^/    /'
            found=1
        fi
    done
    if [ $found -eq 0 ]; then
        echo "치환 대상 placeholder 없음 — 모든 에이전트가 이미 치환됐거나 placeholder 미사용."
    fi
    echo ""
    echo "실제 치환은 --apply 플래그로 실행:"
    echo "  $0 --apply"
    exit 0
fi

echo "[APPLY] 치환 시작..."
count=0
for f in $TARGETS; do
    if grep -qE '\{\{(actor_role|project_name|roadmap_doc|scenario_id_pattern)\}\}' "$f" 2>/dev/null; then
        # macOS/BSD sed는 -i '' 필요, GNU sed는 -i 만. 임시 파일로 통일.
        tmp="${f}.init-tmp"
        sed -e "s/{{actor_role}}/${ACTOR_ESC}/g" \
            -e "s/{{project_name}}/${PROJECT_ESC}/g" \
            -e "s/{{roadmap_doc}}/${ROADMAP_ESC}/g" \
            -e "s/{{scenario_id_pattern}}/${SCENARIO_ESC}/g" \
            "$f" > "$tmp" && mv "$tmp" "$f"
        echo "  치환됨: $f"
        count=$((count + 1))
    fi
done
echo ""
echo "총 ${count}개 파일 치환 완료."
echo "git diff 로 결과 확인 후 commit 권장."
