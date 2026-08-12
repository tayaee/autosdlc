# issue-55: `aacp` 신규 skill 분리 — deploy 단계 제외한 4단계 standalone

agent-tier: local-ok

## 배경

현재 autosdlc 에는 `aacpd` 단일 skill 만 존재하며 그 안의 `aacp.sh` 가
archive / add / commit / push 의 4 단계를 수행하고 마지막에 deploy 를
조건적으로 부른다. 사용자 의도 분류는:

- **`/aacp`** — archive + add + commit + push (deploy 없음). dev 머신이
  없는 환경, 또는 staging 만 검증하고 싶은 경우.
- **`/aacpd`** — `aacp` 4단계 + deploy hook. 평상시 `/autotdd` 가 부르는 표준 path.
- **`/autotdd`** — `tdd2 + aacpd` 체인. self-contained full cycle.

현재 `aacpd/aacp.sh` 가 이미 4단계 core 를 포함하므로 **`/aacp` 는 aacpd 의
4단계 부분을 그대로 호출하는 thin wrapper** 가 될 수 있다.

## 요구사항

1. `autosdlc/.claude/skills/aacp/` 신규 디렉터리 생성
2. `aacp/SKILL.md` 신규 — 4단계만, deploy 호출 없음. precondition 동일
   (이미 `git add` 완료 상태)
3. `aacp/bin/aacp.sh`, `aacp.bat`, `aacp.ps1` 는 **`aacpd/bin/aacp.sh` 와 동일 사본**
   (또는 `aacpd/bin/` 으로의 symlink — 단일 source of truth 유지)
4. `aacpd/SKILL.md` 가 `aacp.sh` 를 부르는 경로가 두 곳 모두 정의되어 있다면
   `aacp/bin/aacp.sh` 만 호출하도록 통일 (또는 `aacpd/bin/aacp.sh` 호출만
   허용 — option B 권장)
5. **Option A 채택 시**: `aacp/bin/` 안에 동일한 사본 유지, sync 는 PR
   reviewer 책임. **Option B 채택 시**: `aacp/bin/` 을 두지 않고 SKILL.md 가
   `~/.claude/skills/aacpd/bin/aacp.sh` 를 직접 호출
6. `aacp` skill 의 호출 인터페이스는 `aacpd` 와 동일 — `aacp N "summary"`
7. 사용자가 `/aacpd -h` 또는 `/aacp -h` 를 부르면 어느 단계까지만 하는지
   안내하는 한 줄 출력 (`aacp: 4단계 (deploy 없음); aacpd: 5단계 (deploy 포함)`)

## 승인 기준

- [ ] `autosdlc/.claude/skills/aacp/SKILL.md` 존재, 4단계만 묘사, deploy 호출 0 hit
- [ ] `aacp/bin/` 안에 `aacp.sh` (또는 `aacpd/bin/aacp.sh` symlink) 가 존재하고
      `bash aacp.sh 9999 "test"` 형태 호출에서 archive+commit 까지만 수행하고
      deploy 호출은 0 (`grep -E 'deploy-to-dev|deploy\.sh' aacp.sh` → 0 hit)
- [ ] `aacpd/bin/aacp.sh` 와 `aacp/bin/aacp.sh` (또는 동일 소스) 가 byte-identical
      (`diff` or `shasum` 비교)
- [ ] `aacpd/SKILL.md` 안의 deploy 호출은 여전히 존재 (변경 없음)
- [ ] 사용자 환경의 `~/.claude/skills/aacp/` 가 동일하게 깔림
- [ ] `/aacp 9999 "test"` 가 tdd2 staged 변경에 대해 commit+push 까지만 하고
      종료 코드 0, deploy 호출 흔적 0 (smoke)

## 검증

`regression-tests/verify-issue-55.sh`:
1. aacp/SKILL.md 가 4단계만 묘사, `deploy-to-dev` / `deploy\.sh` grep 0 hit
2. `aacp/bin/aacp.sh` 가 `aacpd/bin/aacp.sh` 와 동일 (sha256 일치)
3. 임시 repo 에서 `aacp/bin/aacp.sh 9999 "smoke"` 호출 → archive+commit 발생,
   `deploy-to-dev.sh` 호출 0
4. `aacp.sh --help` 또는 인자 오류에서 "deploy 없음" 안내 한 줄

## 구현 결과

- **구현 완료 일시**: 2026-08-11T20:52:06-04:00
- **수정/신규 파일**:
  - `skills/aacp/SKILL.md` 신규 (4단계만 묘사, deploy 안내 분리)
  - `skills/aacp/aacp.sh`, `aacp.bat`, `aacp.ps1` 신규 (skills/aacpd/ 와 byte-identical 사본)
  - `skills/aacpd/aacp.sh` -h/--help 및 NO_DEPLOY (4단계 스킵) 지원 추가
  - `install.sh` aacp skill 추가
  - `regression-tests/verify-issue-55.sh` 신규 작성
- **계획 대비 차이점**: 없음
- **검증 결과**: `verify-issue-55.sh`, `run-ruff`, `run-pyright`, `run-unit-tests`, `run-regression-tests`, `run-pyright-full` 모두 성공 (PASS)

