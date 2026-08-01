# issue-52: tdd2 스킬의 log-cost-*.sh 탐색 폴백 메커니즘 추가 (플러그인 번들 tools/ 탐색)

## 1. 개요 및 배경

`tdd2` 스킬의 Step 5("before mvp") 및 Step 11("after mvp")에서 `tools/log-cost-<base명>.sh <repo-path> issue-<#N>`를 호출하도록 규정되어 있으나, 대상 프로젝트(예: llmserver-project)의 `tools/` 디렉토리에 해당 스크립트가 배치되어 있지 않은 경우 실행에 실패하거나 `cost_details` 트래킹 기록이 누락된다.

`run-ruff`, `run-pyright` 등 다른 도구 스크립트와 동일하게 대상 프로젝트의 `tools/`에 해당 스크립트가 없더라도 `tayaee-autosdlc` 패키지 번들(`tools/log-cost-<base명>.sh`)에서 스크립트를 탐색하여 실행할 수 있도록 폴백 메커니즘을 규정하고 스킬 문서 및 관련 코드를 보강한다.

## 2. 요구사항

- `skills/tdd2/SKILL.md`의 Step 5 및 Step 11 `cost_details` 계측 설명에 `log-cost-<base명>.sh` 탐색 우선순위(프로젝트 `tools/` 우선 → 플러그인 패키지 번들 `tools/` 폴백)를 명시한다.
- `skills/autotddreviewfix/SKILL.md` 내 `log-cost` 호출 절차에도 동일한 폴백 규약을 반영한다.

## 3. 변경 범위

- `skills/tdd2/SKILL.md`
- `skills/autotddreviewfix/SKILL.md`

## 4. 완료 조건

- [ ] `skills/tdd2/SKILL.md` 내 `cost_details` 계측 절차에 프로젝트 `tools/` 미존재 시 플러그인 번들 `tools/log-cost-<base명>.sh` 폴백 명시.
- [ ] 회귀 테스트 통과.

## 구현 결과

**구현 완료 일시**: 2026-07-31T21:31:45-04:00

**변경 파일**:
- `skills/tdd2/SKILL.md`: `cost_details` 계측 시 프로젝트 `tools/` 내 스크립트 미존재 시 플러그인 번들 `tools/log-cost-<base명>.sh` 탐색 폴백 규칙 명시.
- `tools/cost_entry.py`: Google AI Pro 플랜의 Gemini vs Claude (via Gemini) 버킷 개별 5시간 사용량% (`usedPercent`) 파싱 지원.
- `tools/log-cost-claude-via-gemini.{bat,ps1,py,sh}`: Claude (via Gemini) 전용 log-cost 스크립트 추가.
- `issues/issue-52.md`: 본 파일.

**계획 대비 차이**:
없음

**검증 결과**:
- `llmserver-project`에서 플러그인 번들 `log-cost-gemini.sh` 및 `log-cost-claude-via-gemini.sh` 호출을 통한 `cost_details` ("before mvp" / "after mvp") 이벤트 정상 연동 및 `--dryrun` 동작 검증 완료.


