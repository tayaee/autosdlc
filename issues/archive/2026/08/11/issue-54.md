# issue-54: 4개 obsolete skill SKILL.md 삭제 — autoqa, autodev, autofix, autoqafix

agent-tier: local-ok

## 배경

이 4 skill 은 본래 **autonomous loop 워치독** (예: `autoqa-loop.sh` 가 무한히
로그를 떙기고 결함을 autofix 스트림으로 보고) 을 위한 것이었다. 그런데
Claude Code 의 skill dispatch 는 **사용자/에이전트의 턴 경계**에서만 호출되므로
무인 워치독으로는 동작하지 못한다.

같은 이름의 standalone loop 스크립트(`autosdlc/<name>-loop.sh`,
`<name>-doctor.sh`, `<name>.sh`) 가 이미 최상위에 존재해 사실상 skill 의 가치가
0 — 두 진입점(`/autoqa` 슬래시 커맨드 vs `./autoqa-loop.sh &`)이 모호한 채로
남아 있다.

가장 큰 비용: skill 이 매번 LLM 컨텍스트에 적재되며 토큰을 잡아먹는다. 자기
완결성 티켓(`issue-53`) 에서 `autoqafix/` 의 `.py` 9 종은 `autosdlc/bin/` 으로
흡수 — 본 이슈는 `SKILL.md` 만 삭제하는 마무리 작업. `.py` 의 흡수 위치는 본
이슈가 아닌 `issue-53` (또는 그 후속 PR) 에서 처리.

## 요구사항

1. `.claude/skills/autoqa/` 디렉터리 통째 삭제 (이 skill 은 `SKILL.md` 한 파일만 있음)
2. `.claude/skills/autodev/` 디렉터리 통째 삭제
3. `.claude/skills/autofix/` 디렉터리 통째 삭제
4. `.claude/skills/autoqafix/SKILL.md` 만 삭제 (`.py` 9 종 + `wrappers/` 는 `issue-53` 의 Phase C 에서 `autosdlc/bin/` 으로 이동 완료여야 함)
5. `autosdlc/autoqa.sh`, `.bat`, `.ps1` 의 `PY_SCRIPT` 변수가 더 이상 `.claude/skills/autoqafix/*.py` 를 가리키지 않도록 — `~/.claude/bin/<name>.py` 로 경로 재지정 (= `autosdlc/bin/` 의 사본, 사용자 install 위치)
6. `autosdlc/autofix.sh`, `autodev.sh`, `<name>-loop.sh`, `<name>-doctor.sh` 동일 처리
7. README / INSTALL 문서에서 `<skill>` 슬래시 커맨드 안내 제거 — 대신
   `bash autoqa-loop.sh &` / `bash autofix-loop.sh &` 같은 워치독 안내로 교체
8. **BREAKING CHANGES** 한 줄을 CHANGELOG 에 추가

## autoqafix .py 의 `autosdlc/bin/` 흡수 (issue-53 Phase C 와 통합)

이전 ticket 의 가정(aacpd/bin/ 으로 흡수) 은 잘못. Phase A 의 `autosdlc/bin/` 신설
로 인해 **.py 묶음의 정착처는 `autosdlc/bin/`**. 이유:
- 4개 top-level launcher (`autosdlc/autoqa.sh`, `autofix.sh`, `autodev.sh`,
  `autoqafix-doctor.sh`) 가 `.claude/skills/autoqafix/*.py` 를 import — launcher 가
  top-level 이므로 skill 의 bin/ 과 매칭되지 않음.
- **공유 인프라** 의 의미와 부합.

import 경로 점검:
```bash
grep -rE 'from autoqafix|from \.autoqafix|import autoqafix' /home/user1/git/autosdlc/ \
  | grep -v '\.claude/skills/autoqafix/'
```
hits 0 → 무난 이동. hits > 0 → import 경로 갱신.

이동 대상: `autoqafix.py`, `autoqafix_core.py`, `autoqafix-doctor.py`,
`autoqa.py`, `autofix.py`, `error-to-autofix.py`, `log-scan.py`, `role-loop.py`,
`select-llm.py`, `usage-claudecli.py`, `usage-minimaxcli.py`, `usage-qwencli.py`,
`wrappers/` — `autosdlc/bin/` 으로.

```bash
cd /home/user1/git/autosdlc
mkdir -p bin
git mv .claude/skills/autoqafix/*.py bin/
git mv .claude/skills/autoqafix/wrappers bin/wrappers

git rm -rf .claude/skills/autoqa .claude/skills/autodev .claude/skills/autofix
git rm .claude/skills/autoqafix/SKILL.md
rmdir .claude/skills/autoqafix 2>/dev/null

git add README.md INSTALL.md   # standalone 안내로 갱신
git commit -m "autoqa/autodev/autofix/autoqafix: SKILL.md 제거, .py 는 autosdlc/bin/ 으로"
```

## 사용자 설치본 정리

```bash
rm -rf /home/user1/.claude/skills/autoqa
rm -rf /home/user1/.claude/skills/autodev
rm -rf /home/user1/.claude/skills/autofix
rm -rf /home/user1/.claude/skills/autoqafix

# autosdlc/bin/ 을 ~/.claude/bin/ 으로
mkdir -p ~/.claude/bin
ln -sfn "$(pwd)/autosdlc/bin" ~/.claude/bin/autosdlc-bin
```

## 승인 기준

- [ ] `autosdlc/.claude/skills/{autoqa,autodev,autofix,autoqafix}/` 의 어느 것도 더 이상 존재하지 않음
- [ ] `~/.claude/skills/` 에서 위 4 이름 부재 (사용자 측 install 도 동일하게 정리됨)
- [ ] `autoqa.sh`, `autofix.sh`, `autodev.sh` 가 더 이상 `.claude/skills/autoqafix/*.py` 를 import 하지 않음 — `~/.claude/bin/autosdlc-bin/<name>.py` 경로로 재지정 (또는 `PATH` 검색). `grep -RE '\.claude/skills/(autoqafix|autoqa|autofix|autodev)' autosdlc/` → 0 hit
- [ ] `autosdlc/bin/` 안에 `autoqafix*.py` 9종 + `wrappers/` 가 모두 포함
- [ ] `autoqa-loop.sh` 가 그대로 동작 (smoke: `bash autoqa-loop.sh --help` 또는 인자 오류 메시지 확인)
- [ ] CHANGELOG 에 `BREAKING: autoqa/autodev/autofix/autoqafix SKILL.md 제거 — standalone loop 스크립트로 통일` 한 줄 추가

## 검증

`regression-tests/verify-issue-54.sh`:
1. 4 디렉터리 부재 확인
2. `autosdlc/` 의 어디에서도 `.claude/skills/(autoqafix|autoqa|autofix|autodev)` 잔재 grep 0 hit
3. `autosdlc/bin/` 안에 `autoqafix*.py`, `wrappers/` 존재 확인
4. `autoqa-loop.sh` 의 `bash -n` 통과
5. CHANGELOG 의 BREAKING 한 줄 grep 확인

## 구현 결과

- **구현 완료 일시**: 2026-08-11T20:51:30-04:00
- **수정/신규 파일**:
  - `skills/{autoqa,autodev,autofix,autoqafix}/SKILL.md` 삭제
  - `skills/autoqafix/*.py` 및 `skills/autoqafix/wrappers/` -> `bin/`으로 이동
  - launcher 스크립트 21종 (`*.sh`, `*.bat`, `*.ps1`) `PY_SCRIPT` 경로 `bin/`으로 갱신
  - `install.sh`, `CHANGELOG.md`, `CONTEXT.md`, `cheatsheet.md`, `docs/autoqafix-design.md` 경로 및 안내 갱신
  - `regression-tests/verify-issue-54.sh` 신규 작성
- **계획 대비 차이점**: 없음
- **검증 결과**: `verify-issue-54.sh`, `run-ruff`, `run-pyright`, `run-unit-tests`, `run-regression-tests`, `run-pyright-full` 모두 성공 (PASS)

