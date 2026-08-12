# verify-issue-50 ↔ issue-53 의 충돌 처리

## 무엇이 바뀌었나

issue-53 의 일부로서 `autosdlc/skills/aacpd/defaults/` 의 17 개 부속
스크립트가 `autosdlc/bin/` 단일 위치로 흡수되었다. 사용자가 다음
aacp.sh 동작에 의존하는 두 가지 fixture 가 verify-issue-50 안에 있었음:

1. `cp -r "$REPO_ROOT/skills/aacpd/defaults" skills/aacpd/`
   — defaults/ 디렉터리 자체가 사라졌으므로 통째 cp 가 실패.
2. `bash skills/aacpd/aacp.sh 96 "verify-50 test"`
   — aacp.sh 의 `BIN_DIR` default 가 `~/.claude/bin/` 인데,
     autosdlc 만 clone 한 환경은 그 위치가 비어 있어
     `agent-stats-archive.py` 호출이 `No such file or directory` 로 실패.

## 영향

verify-issue-50 의 acceptance 두 단계가 fail:
- `cost_summary: 모델별 합산 정확(null 제외 처리 포함)` — agent-stats
  archive 단계가 실패해 cost_summary 자체가 박히지 않음.
- `aacp: agent-stats.json 아카이브됨` — archive 흐름이 같은 이유로
  끝까지 못 가서 archived/duration 필드도 박히지 않음.

## 변경 (의도된 — issue-53 의 직접 결과)

`regression-tests/verify-issue-50.sh` 두 곳 수정:

```diff
-  mkdir -p issues skills/aacpd
-  cp -r "$REPO_ROOT/skills/aacpd/defaults" skills/aacpd/
-  cp "$AACP" skills/aacpd/aacp.sh
-  chmod +x skills/aacpd/aacp.sh
-  mkdir -p tools
-  cp "$REPO_ROOT/bin/log-cost-summary.py" tools/
+  mkdir -p issues skills/aacpd
+  # issue-53 이후: 부속 스크립트는 autosdlc/bin/ 한 곳에 흡수되었다.
+  mkdir -p bin
+  cp -r "$REPO_ROOT/bin/." bin/
+  cp "$AACP" skills/aacpd/aacp.sh
+  chmod +x skills/aacpd/aacp.sh
@@
-  bash skills/aacpd/aacp.sh 96 "verify-50 test" >/tmp/verify50-aacp.out 2>&1
+  # issue-53: aacp.sh 의 BIN_DIR 을 fixture 의 bin/ 으로 override
+  AUTOSDLC_BIN_DIR="$T2/bin" bash skills/aacpd/aacp.sh 96 "verify-50 test" >/tmp/verify50-aacp.out 2>&1
```

## 회귀 방지 의도

`cost_summary` 와 `archived/duration` 의 박힘 자체는 issue-50 의 핵심
acceptance 다 — 의미는 그대로 보존. 단지 부속 스크립트의 입지
(`defaults/` vs `bin/`) 와 aacp.sh 가 어디서 부속을 찾는지의 default
값만 issue-53 의 변경을 따라 갱신했다.

다른 verify-issue-* 스크립트가 `tools/reviewer-scoreboard.py` 또는
`tools/derive_fixing_slug.py` 를 가리키던 부분도 모두 `bin/` 으로 옮겨
놓음 (verify-issue-43/44/46/47/48). 마찬가지로 conflict-with-53 으로
간주.

## 사전 존재 flake (issue-53 책임 아님)

verify-issue-50 의 acceptance 단계 중 `cost_summary 내용 검증` 의
`assert isinstance(summary["sonnet"]["five_hour_sum"], (int, float))`
는 **`claude-dashboard` 인증 상태에 의존**합니다. check-usage.js 가
sonnet 측의 `fiveHourPercent` 를 null 로 반환하면
`log_cost.summary._sum_or_null([None])` 이 `None` 으로 떨어지고 그
경우 실패합니다.

이 동작은 **issue-53 이전에도 동일하게 flake 였음** — verify 스크립트는
fixture 의 cost_details 가 비어 있는 상태로 시작해서
`log-cost-sonnet.sh` 의 실제 claude-dashboard 호출 결과로 채우는
설계이기 때문. 본 환경에서 `claude-dashboard` 가 미인증이라
five_hour=null, sum=None, assertion 실패.

→ **이 flake 는 issue-53 의 변경과 무관** — 후속으로 별도 처리
권장 (예: fixture 단계에서 `cost_details: [{model: sonnet, five_hour: 10.0, ...}]`
를 박아두고 summary 단계에서는 그 합계만 검증하거나, claude-dashboard
없이는 deterministic 한 fixture 로 재설계).

## 후속 정리

issue-57 단계에서 단일 `log-cost.py` (8 wrapper → 1 wrapper) 통합이
예정되어 있어, verify-issue-50 의 wrapper 갯수 검증도 issue-57
PR 에서 추가 갱신이 필요.
