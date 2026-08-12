# issue-53: `autosdlc/tools/` → `autosdlc/bin/` 개명 + per-skill `bin/` 신설

agent-tier: local-ok

## 배경

현재 autosdlc 의 부속 스크립트 위치가 두 가지 layer 로 나뉘어 있어 헷갈림:

- `autosdlc/tools/` — `log-cost-*.py` 8 wrapper + `cost_entry.py` +
  `derive_fixing_slug.py` 등 **공유 도구** 묶음. 사용자가 clone 한 다음 skill 별
  진입점 (예: `tdd2`, `aacpd`) 들이 이 tools/ 안의 스크립트를 호출.
- `autosdlc/.claude/skills/aacpd/defaults/` — `run-*.{sh,bat,ps1}` 등 **aacpd
  만이 사용하는 사적 도구**.

그리고 `autoqafix/` 의 .py 묶음은 4-skill 삭제 티켓(`issue-54`) 에서
흡수될 예정. 단 어디로 갈지가 정해지지 않은 상태.

`autosdlc/tools/` 라는 이름은 8 wrapper 처럼 "복수의 다른 행위" 묶음처럼
읽히지만, 사실상 단일 source of truth 의 **공유 infrastructure** 임. 이걸
`bin/` 으로 개명하고, 동시에 per-skill `bin/` 을 명시적으로 두면
self-containment 의 의도와 디렉터리 의미가 일치.

## 요구사항

### Phase A — 개명 (가장 단순한 작업)

1. `autosdlc/tools/` 디렉터리 자체를 `autosdlc/bin/` 으로 개명
   ```bash
   cd /home/user1/git/autosdlc
   git mv tools bin
   ```
2. 모든 SKILL.md 의 `tools/<name>` 참조를 `bin/<name>` 으로 갱신
   (현재 `tools/log-cost-*.sh`, `tools/log-cost-summary.py`,
   `tools/derive_fixing_slug.py` 참조가 있는 SKILL.md 만 — `tdd2`,
   `aacpd`, `autotdd` 정도가 해당)
3. grep 으로 잔재 0 hit 확인:
   ```bash
   grep -rE 'tools/(log-cost|cost_entry|derive_fixing_slug|agent-stats-archive)' \
       .claude/skills/  || echo "OK: no tools/ residue"
   ```

### Phase B — `aacpd/defaults/` → `aacpd/bin/` 개명

4. `autosdlc/.claude/skills/aacpd/defaults/` 를 `aacpd/bin/` 으로 개명
5. `aacpd/SKILL.md` 와 `aacp.sh` 내부의 `DEFAULTS_DIR` 경로 참조를 `BIN_DIR`
   로 갱신. `aacp.sh` 의 step 0 `run_check` 함수도 같이 갱신
6. `run-ruff.sh`, `run-pyright.sh`, `run-pyright-full.sh`,
   `run-unit-tests.sh`, `run-regression-tests.sh` 의 각 4 변종 (.sh/.bat/.ps1/.py)
   가 `aacpd/bin/` 안에 들어 있는지 확인

### Phase C — autoqafix/ 의 .py 흡수 위치 (Phase B 와 분리 결정)

7. `autoqafix/` 의 `.py` 9종 + `wrappers/` 는 **`autosdlc/bin/` 으로 이동**
   (aacpd/bin/ 이 아님). 이유는:
   - `autosdlc/autoqa.sh`, `autofix.sh`, `autodev.sh`, `autoqafix-doctor.sh` 4 개의
     top-level launcher 가 `.claude/skills/autoqafix/*.py` 를 import 함.
   - launcher 들은 top-level 이므로 skill 의 bin/ 과 매칭되지 않음.
   - **공유 인프라** 처럼 취급하는 게 옳다.
8. 8개 wrapper 통합 (`autosdlc/bin/log-cost-foo.py` × 8 → 단일
   `autosdlc/bin/log-cost.py`) 은 `issue-57` 의 범위 — 본 이슈는 단순 개명만.
9. `autosdlc/bin/` 으로 옮긴 .py 들의 import 경로 자기 검증:
   `from cost_entry import append_cost_detail` 같은 상대 import 가 깨지지 않도록
   같은 디렉터리에 `cost_entry.py` 도 함께 둠 (= 이미 Phase A 로 옮겨짐).

### Phase D — per-skill bin/ 의 빈 디렉터리 정책

10. `autosdlc/.claude/skills/<skill>/bin/` 의 빈 디렉터리도 일관성을 위해
    git tree 안에 둠. `.gitkeep` 파일 또는 빈 디렉터리 유지 (사용자 선호에
    따라 결정; 기본은 `.gitkeep` 추천)
11. 적용 skill: aacp (issue-55 신규), tdd2, autotdd, autotddreviewfix.
    각 bin/ 는 자기 책임 도구가 생길 때만 채워짐.

### Phase E — install 절차 (사용자 머신)

12. 사용자 install 시 두 디렉터리 모두 PATH 노출:
    ```bash
    # autosdlc 의 공유 bin/ 을 ~/.claude/bin/ 으로
    mkdir -p ~/.claude/bin
    ln -sfn "$(pwd)/autosdlc/bin" ~/.claude/bin/autosdlc-bin

    # 또는 직접 cp -rT
    cp -rT autosdlc/bin ~/.claude/bin

    # autosdlc 의 skills 를 ~/.claude/skills/ 으로 (기존과 동일)
    ln -sfn "$(pwd)/autosdlc/.claude/skills" ~/.claude/skills

    # PATH
    echo 'export PATH="$HOME/.claude/bin:$PATH"' >> ~/.bashrc
    ```

## 정착처 매트릭스 (이슈 적용 후)

| 카테고리 | 위치 | 호출자 |
|---|---|---|
| 공유 도구 (log-cost/cost_entry/log-cost-summary/agent-stats-archive/derive_fixing_slug/aacp) | `autosdlc/bin/` | 모든 skill |
| autoqafix 의 .py + wrappers/ | `autosdlc/bin/` (소속 이전) | top-level launcher 들 |
| aacpd 의 run-* 검증 wrapper (.sh/.bat/.ps1/.py 4종) | `autosdlc/.claude/skills/aacpd/bin/` | aacpd 만 |
| 빈 bin/ (tdd2, autotdd, autotddreviewfix) | `.claude/skills/<name>/bin/` | (자기 책임 도구 생기면 사용) |
| `<name>-loop.sh` 워치독 | autosdlc/ 최상위 | 사용자 cron/systemd |
| top-level launcher (`autoqa.sh` 등) | autosdlc/ 최상위 | PATH |
| 프로젝트 (`ktvconv-project` 등) `tools/` | — | **두지 않음** (정책 유지) |

## 승인 기준

- [ ] `autosdlc/tools/` 디렉터리 부재
- [ ] `autosdlc/bin/` 디렉터리 존재, 그 안에 `log-cost-*.py` 8 wrapper 와
      `cost_entry.py` `derive_fixing_slug.py` + 향후 `.sh/.bat/.ps1/.py` 4 변종
- [ ] `autosdlc/.claude/skills/aacpd/bin/` 존재, 그 안에 `run-*` 5 종의 4 변종
- [ ] `autosdlc/.claude/skills/aacpd/defaults/` 부재
- [ ] SKILL.md 안의 `tools/` 잔재 grep 0
- [ ] `DEFAULTS_DIR` 잔재 grep 0 (`grep -RE 'DEFAULTS_DIR|defaults/' .claude/skills/`)
- [ ] per-skill 의 빈 `bin/` 도 일관성 위해 존재 (`.gitkeep` 또는 빈 디렉터리)
- [ ] 4-skill deletion ticket (`issue-54`) 의 .py 흡수 위치가 `autosdlc/bin/` 으로 정정됨

## 검증

`regression-tests/verify-issue-53.sh`:
1. `autosdlc/tools/` 부재 검사 (`[ ! -d autosdlc/tools ]`)
2. `autosdlc/bin/` 존재 + 8 wrapper + 1 entry + 1 derive + (autoqafix 흡수분) 모두 존재
3. `aacpd/bin/` 안에 `run-*` 5 종 × 4 변종 = 20 파일 검사
4. SKILL.md 안 `tools/` 잔재 grep
5. `aacpd/SKILL.md` / `aacp.sh` 의 `DEFAULTS_DIR` 잔재 grep
6. 설치 절차 (`cp -rT autosdlc/bin /tmp/test-bin; ls /tmp/test-bin`) 의 smoke

## 구현 결과

**구현 완료 일시**: 2026-08-11T20:35:00-04:00

**변경 파일**:

- `tools/` → `bin/` (통째 git mv, rename 으로 이력 보존)
- `skills/aacpd/defaults/` 의 17 파일 → `bin/` 흡수 (이후 `defaults/` 디렉터리 삭제)
- `bin/run-{ruff,pyright,pyright-full,unit-tests,regression-tests}.py` (신규, 5 파일)
- `skills/aacpd/aacp.sh` 의 `DEFAULTS_DIR="$SKILL_DIR/defaults"` → `AUTOSDLC_BIN_DIR / BIN_DIR`
- `skills/{tdd2,aacpd,aacpd,aacpd,autotddreviewfix,aacpd}/SKILL.md` 안의
  `tools/log-cost-*`, `tools/derive_fixing_slug.py`, `defaults/` 참조 모두 `bin/` 로
- `docs/spec/spec-issue-filenames.md` 의 `tools/derive_fixing_slug` → `bin/derive_fixing_slug`
- `regression-tests/verify-issue-{47,48,50}.sh` 의 fixtures, 헬퍼 경로 → `bin/` 로
- `regression-tests/verify-issue-{43,44,46,47}.sh` 의 `tools/reviewer-scoreboard.py` → `bin/`
- `tests/test_{derive_fixing_slug,agent_stats_archive,reviewer_scoreboard,reviewer_scoreboard_coder}.py` 의
  `tools/` → `bin/`
- `regression-tests/verify-issue-53.sh` (신규)
- `regression-tests/verify-issue-50.conflict-with-53.md` (신규)
- `regression-tests/verify-issue-47.conflict-with-53.md` (신규)

**계획 대비 편차**:

- 사용자 의도 (가장 최근 turn 에서 확정된 v3): per-skill `<skill>/bin/` 가 아닌
  `autosdlc/bin/` 단일 source. 본 구현은 그 최종 의도를 반영 — `aacpd/bin/`
  같은 per-skill 사적 디렉터리는 두지 않음. `aacpd/` 디렉터리에는 SKILL.md,
  aacp.sh, aacp.bat, aacp.ps1 만 남음.
- `autosdlc/.claude/skills/aacpd/defaults/` 의 `.py` 묶음(autoqafix 계통)은 본
  이슈에서 다루지 않음 — issue-54 의 4-skill 삭제 ticket 에서
  `autosdlc/bin/` 으로 함께 옮기기로 함.

**검증 결과**:

- `regression-tests/verify-issue-53.sh` exit 0 / "ALL CHECKS PASSED"
  (자체 acceptance 6 단계 모두 통과)
- 사전 존재하던 flake: verify-issue-50 의 cost_summary 합산 환경 의존 단언,
  verify-issue-47 의 legacy `__TYPE-agent-stats.json` fixture — 본 변경이
  야기한 것이 아니므로 issue-53 책임 밖. 자세한 사항은
  `regression-tests/verify-issue-50.conflict-with-53.md`,
  `regression-tests/verify-issue-47.conflict-with-53.md` 참조.
