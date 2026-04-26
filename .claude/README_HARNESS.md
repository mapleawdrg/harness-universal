# Claude Code Harness — 범용 배포 가이드

9-Agent Generator-Evaluator 하네스를 신규 프로젝트에 이식하는 가이드. Anthropic 공식 엔지니어링 블로그의 [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps), [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents), [Scaling Managed Agents](https://www.anthropic.com/engineering/managed-agents) 원칙을 따름.

## 구성

| 파일 | 역할 | 이식 시 |
|---|---|---|
| `.claude/agents/*.md` (9개) | 에이전트 시스템 프롬프트 | 복사 + 도메인 누출 치환 (하단 참조) |
| `.claude/hooks/*.sh` + `rules/*.sh` | PreToolUse / PostToolUse / SubagentStop 자동화 | 복사 (대부분 generic) |
| `.claude/harness.config.json` | 프로젝트 고유 설정 중앙화 | **필수 수정** |
| `.claude/agents-manifest.json` | 에이전트 → 산출물 매핑 | 에이전트 추가 시에만 수정 |
| `.claude/settings.json` | 훅 등록 + 권한 | 경로 검증 |
| `.harness/` | 런타임 산출물 (decisions-log, *-p{N}.md) | 빈 디렉토리 생성 |

## 에이전트 루프 (Generator-Evaluator)

```
product-designer → product-reviewer (max 3)
       ↓ PASS
architect → architect-reviewer (max 3)
       ↓ PASS
planner → plan-reviewer (max 3)
       ↓ PASS
dev → qa (max 3)
       ↓ PASS
(complete)

cross-cutting: explain (layer triage when dev is blocked)
```

모든 페어는 **generator는 산출물을 쓰고 evaluator는 판정만** (evaluator는 코드/TC 수정 금지). `*-p{N}.md` 네이밍으로 병렬 phase 충돌 방지.

## 이식 절차

### 1. 파일 복사

```bash
# 신규 프로젝트 루트에서
cp -r {SOURCE}/.claude .claude
mkdir -p .harness
```

### 2. `.claude/harness.config.json` 수정

| 필드 | 타입 | 의미 | 예시 |
|---|---|---|---|
| `project_name` | string | 프로젝트 표시명 | `"MyApp"` |
| `actor_role` | string | 주 사용자 호칭 (에이전트가 Actor 자리에 주입) | `"Owner"`, `"PM"`, `"User"` |
| `roadmap_doc` | string \| null | 전체 로드맵 문서 경로 (없으면 null) | `"docs/roadmap.md"` |
| `scenario_id_pattern` | string \| null | 유저 시나리오 ID 패턴 | `"UC-1~UC-10"` |
| `drift_check_docs[]` | string[] | plan-reviewer Step 4.5 침묵 충돌 검사 대상 문서 목록. 빈 배열 `[]`이면 Step 4.5 전체 skip | `["docs/architecture.md", "docs/TRD.md"]` |
| `domain_vocab` | object | 도메인 어휘 사전 (product-designer/reviewer가 API·계정·채널 용어 파악에 사용). 구조: `{"data_sources": [...], "accounts": [...], "channels": [...]}` | `{"data_sources": ["REST API", "PostgreSQL"], "accounts": ["Free", "Pro"], "channels": ["Web", "CLI"]}` |
| `test_commands` | object | lint/test/coverage/ci 명령어 매핑. 키는 `lint`, `test`, `coverage`, `ci` 고정 | `{"lint": "npm run lint", "test": "npm test", "coverage": "npm run coverage", "ci": "npm run ci"}` |
| `coverage_targets` | object | 모듈 유형별 커버리지 목표(%). 키는 프로젝트 모듈명 (plan-reviewer Step 3 기준) | `{"business_logic": 90, "utility": 70, "io_layer": 60, "overall": 70}` |

**`roadmap_doc` / `scenario_id_pattern`이 null이면** qa/product-reviewer의 시나리오 완결 체크가 generic AC 체크로 fallback.

**`drift_check_docs[]`가 빈 배열이면** plan-reviewer Step 4.5 전체 skip.

### 3. 에이전트 도메인 누출 치환 ← **§2 설정만으로는 끝이 아님 — 이 단계 필수**

> ⚠️ **v1 한계**: `harness.config.json`의 값은 에이전트가 실행 시 읽어 "참고"하지만, 에이전트 파일 내부에 하드코딩된 stock_project 고유 문자열은 **자동 치환되지 않는다**. 아래 파일들을 직접 편집해야 한다. (차기 릴리스에서 Jinja2/`{{KEY}}` 프리프로세서 템플릿화 예정)

현재 6개 에이전트 파일에 stock_project 고유 문자열이 남아있음. 신규 프로젝트 이식 시 아래 grep으로 찾아 프로젝트 용어로 교체:

```bash
grep -rn "Investment Coach\|Captain\|rebuild_plan_v2\|S1-S17\|KIS\|Telegram\|Finnhub\|ISA\|IRP\|trade_log\|analyst_facts\|YouTube\|올랜도킴" .claude/agents/
```

해당 파일:
- `.claude/agents/qa.md` — Step 4.5 (Scenario 완결 AC 체크)
- `.claude/agents/product-designer.md` — 데이터 매핑 예시
- `.claude/agents/product-reviewer.md` — Step 2 missing-scenario 패턴 매트릭스
- `.claude/agents/planner.md` — Mode 판정 예시
- `.claude/agents/plan-reviewer.md` — Step 4.5 drift-check 예시 (harness.config 참조로 대체 권장)
- `.claude/agents/architect.md` — 모듈 breakdown 예시

**치환 원칙**: 
- "Captain" → `{actor_role}`
- "rebuild_plan_v2.md" → `{roadmap_doc}`
- "S1-S17" → `{scenario_id_pattern}`
- 도메인 용어(KIS/Finnhub 등) → 프로젝트별 데이터 소스 용어

### 4. `.claude/settings.json` 확인

훅 경로는 상대경로 (`.claude/hooks/...`) — 이식 후 수정 불필요. 단, `settings.local.json`의 permissions allowlist는 프로젝트별 재작성:
- `make` 기반이 아니면 `npm run` / `cargo` 등으로 교체
- test runner 실행 허가 (`pytest`, `jest`, `go test` 등)

### 5. 훅 rules 확인

`.claude/hooks/rules/*.sh` (9개)는 전부 generic (secret-read/write block, branch protect, test-tamper block 등). 신규 프로젝트에서 그대로 사용.

### 6. 첫 사이클 smoke test

```bash
# 빈 프로젝트에서
echo "# Product Vision" > .harness/product-vision.md
# @product-designer 호출 ("Phase: P1" 첫줄)
# → product-design-p1.md 생성되는지 확인
# → @product-reviewer → @architect → ... → @qa 까지 E2E
```

## Anthropic 공식 원칙과의 정렬

| 원칙 | 출처 | 하네스 구현 |
|---|---|---|
| Generator-Evaluator 분리 | [harness-design blog](https://www.anthropic.com/engineering/harness-design-long-running-apps) | 9 에이전트 전부 페어링, `*-reviewer` 는 generator 산출물 수정 금지 |
| Context reset via structured handoff | harness-design blog | `.harness/*-p{N}.md`가 SSOT, 세션 간 state 공유 없음 |
| Prompt caching | [caching docs](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching) | `app/agent/workers/*.md` 로딩 시 `cache_control: ephemeral` |
| Simplicity in agent design | [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents) | 각 에이전트 200줄 내외, DoD/Anti-Patterns 명시 |
| Event log for replay | [managed-agents blog](https://www.anthropic.com/engineering/managed-agents) | `decisions-log.md` 시간순 append, ID 체계 (DEC-NNNN), commit hash 치환 |
| Loop termination | harness-design blog | 모든 페어 max 3 iter, N=3 시 사용자 판단 요구 |

## 현재 v1 한계 (후속 릴리스 예정)

- **에이전트 프롬프트 템플릿 엔진 없음**: 현재 `{{var}}` 치환이 아닌 수동 치환. 차기: Jinja2 or 단순 `{{KEY}}` 프리프로세서.
- **`agents-manifest.json`의 `escalate_after_n_failures` 필드는 현재 hook 라우팅 미사용**: 문서화 메타로만 존재 (`_field_semantics` 명시). 실제 트리거는 `dev.md` Step 4a / `qa.md` Step 6a에 박힘. 차기: hook이 이 필드 읽고 자동 라우팅.
- **중복 체크리스트**: qa/product-reviewer/architect에 review-rubric, scenario-matrix, security-checklist 중복. 차기: `.claude/agents/_shared/*.md` 추출 후 에이전트는 참조만.
- **user-facing transparency**: 에이전트가 "현재 step / 남은 step"을 Stop 훅에 노출하지 않음. 차기: session-summary.sh에 "다음 제안 에이전트" 힌트 추가.
- **sprint-contract 테스트 스냅샷 필드 미강제**: dev-report 자유기술. 차기: `test_snapshot: {count, coverage, hash}` schema 강제.

## 파일 인덱스 (이식 체크리스트)

```
.claude/
├── agents/                         # 9 에이전트 (각 ~200줄)
│   ├── product-designer.md
│   ├── product-reviewer.md
│   ├── architect.md
│   ├── architect-reviewer.md
│   ├── planner.md
│   ├── plan-reviewer.md
│   ├── dev.md
│   ├── qa.md
│   └── explain.md
├── hooks/
│   ├── sandbox-guard.sh           # PreToolUse 라우터 (generic)
│   ├── post-change-tracker.sh     # PostToolUse 변경 추적 (generic)
│   ├── subagent-output-guard.sh   # SubagentStop 핸드오프 검증 (manifest 기반)
│   ├── session-summary.sh         # Stop 훅 요약 (generic)
│   ├── log-id-helper.sh           # DEC/ING ID 생성기 (generic)
│   ├── log-prepend.sh             # Atomic prepend (generic)
│   ├── wiki-ingest.sh             # /wiki ingest 트리거 (optional)
│   ├── hot-refresh-prompt.txt     # Wiki hot cache 리프레시 (project-specific — 차기 템플릿화)
│   └── rules/                     # 9 security rules (generic)
├── harness.config.json            # 프로젝트 고유 설정 ← 이식 시 주 수정 대상
├── agents-manifest.json           # 에이전트 → 산출물 매핑
├── settings.json                  # 훅 등록
└── settings.local.json            # 권한 allowlist (프로젝트별)
```

## 트러블슈팅

**Q. `subagent-output-guard.sh` 가 경고를 안 띄운다**
- manifest 파일 존재 확인: `.claude/agents-manifest.json`
- PHASE 전달 채널 (우선순위 순):
  1. `HARNESS_PHASE` env (수동 override, 최우선)
  2. agent 호출 첫 메시지의 `Phase: P{N}` 라인 — hook이 SubagentStop payload의 `agent_transcript_path` JSONL을 읽어 자동 추출
  3. 둘 다 없으면 명시적 경고 + glob fallback (silent pass 아님)
- payload 필드: 공식 스키마는 `agent_type` (구버전 `agent_name`도 호환). 매니페스트 키와 매칭 필요.

**Q. PHASE 추출 실패 경고가 매번 뜬다**
- 원인: 사용자가 agent 호출 시 첫 줄에 `Phase: P{N}` 명시 안 함
- 해결: agent 호출 메시지 템플릿에 첫 줄 `Phase: P{N}` 강제 (예: `@planner` 호출 시 항상 `Phase: P5\n실제 요청...`)
- 또는 세션 시작 시 `export HARNESS_PHASE=P5`

**Q. plan-reviewer Step 4.5가 모든 prop을 HIGH로 올린다**
- `harness.config.json`의 `drift_check_docs`에 존재하지 않는 파일이 있는지 확인
- 존재하지 않는 문서는 자동 soft-skip (HIGH→INFO)

**Q. decisions-log ID 충돌**
- `log-id-helper.sh`가 stateless scan 이므로 병렬 에이전트 실행 시 race 가능성
- 해결: 에이전트 호출 순차화, 또는 ID 할당 후 즉시 log-prepend 실행
