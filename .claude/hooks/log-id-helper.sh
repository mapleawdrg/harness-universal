#!/bin/bash
# Requires: bash 4.0+, git, flock (util-linux)
# log-id-helper.sh — 다음 sequential ID 자동 할당 (race-safe)
#
# Usage: log-id-helper.sh DEC  →  DEC-0043
#        log-id-helper.sh ING  →  ING-0012
#        log-id-helper.sh SRC  →  SRC-0256
#
# Concurrency: .harness/.id-helper.lock 기반 flock 으로 동시 호출 시 ID 충돌 차단.
# flock 미존재 환경(macOS 기본 등)은 best-effort 로 fallback (race 가능, 단일 호출 시 영향 없음).

set -euo pipefail

TYPE="${1:-}"
[ -z "$TYPE" ] && { echo "Usage: $0 {DEC|ING|SRC|REV|QA}" >&2; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not in git repo" >&2; exit 1; }

LOCK_DIR="${REPO_ROOT}/.harness"
LOCK_FILE="${LOCK_DIR}/.id-helper.lock"
mkdir -p "$LOCK_DIR" 2>/dev/null || true

compute_next_id() {
    # 해당 TYPE entry 중 최대 4자리 NNNN 추출 → +1
    # Scope: .harness/, wiki/ 하위 모든 .md 파일
    local max
    max=$(grep -hroE "\[${TYPE}-[0-9]{4}" \
            "${REPO_ROOT}/.harness" \
            "${REPO_ROOT}/wiki" 2>/dev/null \
          | grep -oE "[0-9]{4}" \
          | sort -n \
          | tail -1)
    printf "%s-%04d\n" "$TYPE" $((10#${max:-0} + 1))
}

if command -v flock >/dev/null 2>&1; then
    # Linux/util-linux: flock으로 직렬화
    exec 9>"$LOCK_FILE"
    flock -w 5 9 || { echo "log-id-helper: lock timeout — try again" >&2; exit 1; }
    compute_next_id
    # exec 9 닫힘 시 lock 자동 해제
elif [ -d /System/Library ] && command -v shlock >/dev/null 2>&1; then
    # macOS: shlock fallback (있으면)
    PID_LOCK="${LOCK_FILE}.pid"
    for _ in 1 2 3 4 5; do
        if shlock -p $$ -f "$PID_LOCK" 2>/dev/null; then
            trap 'rm -f "$PID_LOCK"' EXIT
            compute_next_id
            exit 0
        fi
        sleep 0.5
    done
    echo "log-id-helper: shlock timeout — falling back to best-effort" >&2
    compute_next_id
else
    # Best-effort: race 가능. 단일 사용자 환경에선 충분.
    compute_next_id
fi
