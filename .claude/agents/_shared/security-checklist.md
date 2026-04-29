# Security Checklist — SSOT

이 문서는 dev / qa / architect-reviewer 에이전트가 공유하는 **보안 체크리스트의 단일 진실 공급원(SSOT)**이다.

**원칙**: 각 에이전트 본문에 보안 항목을 그대로 유지(self-contained + prompt caching 효율). 항목을 **추가·수정·삭제**할 때만 본 문서를 먼저 갱신하고, 영향받는 에이전트들의 본문을 동기화한다.

---

## 핵심 보안 항목 (4축)

### 1. 시크릿 하드코딩 금지

- API 키, 비밀번호, DB URL, 토큰 등을 코드에 직접 쓰지 않는다.
- 모든 시크릿은 환경변수 (`os.getenv()`, `process.env.X`, 등)로 주입한다.
- `.env` 파일은 `.gitignore`에 포함되어야 하며, repo에 커밋되어서는 안 된다.

**적용 시점**:
- @architect (TDD §Security Considerations): 시크릿 관리 방식 명시
- @architect-reviewer Step 1: "민감 데이터 — 코드에 하드코딩 금지 언급이 있는가?"
- @dev Step 3 보안 규칙: 구현 시 위반 즉시 중단
- @qa Step 5 보안 검토: 코드에서 발견 시 P1

---

### 2. 환경변수 값 노출 금지

- 환경변수 값을 print, echo, log, 에러 메시지에 출력하지 않는다.
- 디버깅용 임시 출력도 금지 — 로그가 외부로 유출될 수 있다.

**적용 시점**:
- @dev Step 3 보안 규칙
- @dev Anti-Patterns: `print(api_key)`, `logging.info(secret)` 금지
- @qa Step 5 보안 검토

---

### 3. 사용자 입력 검증

- 외부에서 들어오는 모든 입력 (HTTP body, query params, 파일 경로, CLI args)은 검증 후 사용한다.
- 검증 항목: 타입, 범위, 허용 문자, 길이, SQL injection 패턴, 경로 탐색 (path traversal).

**적용 시점**:
- @architect TDD §Security Considerations
- @architect-reviewer Step 1: "외부 입력 검증 언급되었는가?"
- @dev Step 3 보안 규칙
- @qa Step 5 보안 검토: SQL injection / 경로 탐색 / XSS 등

---

### 4. 테스트 더미값 사용

- 테스트 코드에서 실제 API 키, 실제 DB, 실제 외부 서비스 사용 금지.
- 더미 상수 (`DUMMY_KEY_FOR_TEST`) 또는 mock/fixture 사용.
- 테스트가 외부에 실제 요청을 보내지 않아야 한다 (CI 비용·rate limit·data corruption 방지).

**적용 시점**:
- @dev Step 3 보안 규칙: 더미값 사용
- @qa Step 4 테스트 독립성: 실제 키/DB 사용 금지
- @qa Step 5 보안 검토

---

## 동기화 규칙

본 SSOT를 수정할 때:
1. 본 문서의 항목을 먼저 갱신한다.
2. 영향받는 에이전트(들)의 본문을 grep으로 찾아 동시에 갱신한다:
   ```bash
   # SSOT 키워드 + architect-reviewer의 도메인 표현(민감 데이터/외부 입력)을 함께 매칭
   grep -nE "시크릿|환경변수|입력 검증|더미값|민감 데이터|외부 입력|보안 규칙|보안 검토|보안 설계" .claude/agents/{dev,qa,architect-reviewer}.md
   # dev.md Anti-Patterns 섹션도 별도 확인 (보안 항목 2줄 박혀있음)
   grep -nA1 "Anti-Patterns" .claude/agents/dev.md
   ```
3. plan-reviewer Step 4.5의 `drift_check_docs[]` 에 본 파일을 포함시키면 sprint-contract가 보안 정책을 변경할 때 침묵 충돌이 자동 탐지된다 (선택, 프로젝트별 결정).

## 적용 우선순위 (Severity)

| Severity | 예시 | 차단 시점 |
|---|---|---|
| **CRITICAL** | 비밀번호 평문 저장, API 키 코드 직접 포함 | @architect-reviewer / @qa P1 — 즉시 NEEDS_WORK |
| **HIGH** | 인증 방식 미정, 사용자 입력 무검증 | @architect-reviewer / @qa P2 |
| **MEDIUM** | 에러 메시지에 내부 정보 노출 가능성 | @qa P3 |
| **LOW** | 권장 보안 설정 미언급 | @qa P4 |

## 비-목표

본 체크리스트는 **공통 핵심 4축**만 다룬다. 도메인별 추가 보안 (예: 금융 PCI-DSS, 의료 HIPAA, 결제 PA-DSS)은 프로젝트 자체 보안 정책 문서에서 정의하고, sprint-contract AC에 명시한다.
