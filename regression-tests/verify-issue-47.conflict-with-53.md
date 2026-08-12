# verify-issue-47 ↔ issue-53 의 충돌 처리

## 무엇이 바뀌었나

issue-53 의 일부로서 `autosdlc/skills/aacpd/defaults/` 가
`autosdlc/bin/` 으로 흡수되었다. verify-issue-47 의 fixture 단계가
이전 경로를 참조하던 두 곳을 갱신.

## 영향 (수정)

`regression-tests/verify-issue-47.sh`:

```diff
- mkdir -p issues .claude/skills/aacpd
- cp -r "$REPO_ROOT/.claude/skills/aacpd/defaults" .claude/skills/aacpd/
+ mkdir -p issues .claude/skills/aacpd
+ # issue-53: 모든 부속 스크립트는 autosdlc/bin/ 으로 흡수. fixture 도 bin/ 에서 복사.
+ mkdir -p bin
+ cp -r "$REPO_ROOT/bin/." bin/
@@
- bash .claude/skills/aacpd/aacp.sh 95 "verify-47 test" >/tmp/verify47-aacp.out 2>&1
+ AUTOSDLC_BIN_DIR="$T2/bin" bash .claude/skills/aacpd/aacp.sh 95 "verify-47 test" >/tmp/verify47-aacp.out 2>&1
```

## 사전 존재 잔여 실패 (issue-53 책임 아님)

수정 후에도 5 건의 FAIL 이 남아 있음 — 모두 **legacy `__TYPE-agent-stats.json`
파일명** 검증 경로 (issue-47 자체 의도와도 연관된 기존 결함).

- `archive 헬퍼 exit 1: ERROR: agent-stats.json 없음` — fixture 가
  `issue-90__TYPE-agent-stats.json` 으로 만들지만 archive 헬퍼는
  `__agent-stats.json` 만 봄.
- `archive 헬퍼: 필드 검증 실패` — 같은 이유로 archive 가 안 돼서
  `archived`/`duration` 필드 검증도 fail.
- `archive 헬퍼: started 누락 안내 없음` — stderr 출력 형식 변경 가능성.
- `aacp: agent-stats.json 아카이브 안 됨` — archive 헬퍼 실패의 연쇄.
- `aacp: code-review 파일 아카이브 안 됨` — `git push` 가 `fatal: No
  configured push destination` 으로 실패해 fixture 가 incomplete 상태.

이들은 모두 issue-53 이전부터의 (혹은 issue-47 자체의) 결함이며
verify 스크립트의 fixture 가 `__TYPE-` legacy 파일명을 그대로 쓰는
것이 근본 원인. **issue-53 의 책임이 아닙니다**.

verify-script 의 legacy-cleanup 은 별도 후속 ticket 으로 빼는 것을
권장 (예: `autofix-1: legacy __TYPE-* fixture 일관화`).
