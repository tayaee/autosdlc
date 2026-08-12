# issue-57: 단계별 5h/7d 쿼터 계측 + reason 필드 + 단일 `log-cost.py` 통합

agent-tier: local-ok

## 배경

현재 aacpd 의 archive 단계에서 `agent-stats.json` 의 `cost_details` 에
`before mvp` / `after mvp` 두 이벤트만 박힌다. 둘 다 `five_hour_used_pct`
가 `null` — 각 단계마다 누적된 quota 를 가시화하지 못한다. 사용자 의도:

```
mvp 구현: 37% → 22%   (-15%p)
ruff:      22% → 21%   (-1%p)
pytest:    21% → 19%   (-2%p)
review:    19% → 18%   (-1%p)
지적 수정:  18% → 16%   (-2%p)
```

이 가시화를 가능하게 하려면 (a) `CostDetailEntry` 스키마에 reason 필드 추가,
(b) provider 미지원 시 stub 으로라도 이벤트를 박아야 감사 흔적이 남고,
(c) `log-cost-*.sh` 8 wrapper → 단일 `log-cost.py` 로 통합 + 호출자/메타
필드 추가, (d) tdd2 / aacpd / autotddreviewfix 의 각 단계 끝마다 snapshot
호출 의무화.

모든 변경은 **autosdlc 안에서 자기완결** — 외부 harness-project 의존 0.

## 요구사항

### 스키마 + 비용 항목 (`cost_entry.py`, `aacpd/bin/`)

1. `aacpd/bin/cost_entry.py::CostDetailEntry` 에 필드 추가:
   - `coder: str` — 어떤 wrapper 가 호출됐는지 (사람 가독 식별자). 예: `"minimax"`.
   - `model: str` — 풀 모델명. 예: `"MiniMax-M3"`.
   - `reasoning_effort: str | None` — 현재 세션 effort 단계.
   - `bucket: str | None` — claude-dashboard 의 어느 bucket 에서 떙겼는지.
   - `reason: str | None` — null pct 시 사유.
     `'unsupported_provider' | 'lookup_unavailable' | 'lookup_failed' | 'api_error' | None`.
2. 호환성: 기존 `model` 필드는 그대로 두고 새 `coder` 별도. Pydantic 마이그레이션은 issue 53 의 bin/ 흡수 시점에 같이 처리.

### 단일 `log-cost.py` 통합 (`aacpd/bin/`)

3. `aacpd/bin/log-cost-*.py` 8 wrapper 삭제 → **단일 `aacpd/bin/log-cost.py`** 가 호출자(`coder`)/모델(`model`)을 argument 로 받음:
   ```bash
   log-cost.py [--quiet|--verbose] [--auto] <repo-path> <issue-N|autofix-N> "<description>"
   ```
4. 내부적으로 `query_check_usage_pct` 가 **provider 키 미지원이어도 일단 모든 bucket 을 순회** 후 가장 가까운 매칭의 pct 를 박음. 미지원은 `reason="unsupported_provider"` 와 함께 pct=null 박기 (SKIP 금지).
5. `claude-dashboard` 플러그인 미설치 시 reason=`"lookup_unavailable"`, node 실패 시 `"lookup_failed"`. 둘 모두 박기.
6. **stderr WARN 한 줄 + exit 0** 유지 — 호출자가 pct=null 여도 다음 단계로 갈 수 있어야 함.
7. **`reasoning_effort` 자동 read**: `$CLAUDE_CODE_REASONING_EFFORT` / `--reasoning-effort` / API 응답 메타 순 fallback. 모두 실패 시 `null`.

### 각 단계 끝 snapshot 의무화

8. **tdd2** SKILL.md: step 5 (before mvp), step 6 (after ruff), step 7 (after pytest), step 8 (after regression), step 9 (after pyright-full), step 11 (after mvp) — 각 끝마다 `bash $AACP_BIN/log-cost.py <quiet>` 호출.
9. **aacpd** SKILL.md: step 0 끝, step 4 끝, step 6(배포) 직전, step 6 끝 — 같은 호출.
10. **autotddreviewfix** SKILL.md: review 전후, fix 전후 — 같은 호출.
11. **호출은 silent** — wrapper 의 default 는 stdout/stderr 모두 /dev/null (Q15). `AACP_VERBOSE=1` 일 때만 진단 출력. **단**, 호출자(=driver skill) 의 진행 메시지를 유지해야 하므로 driver skill 이 verbose 모드를 켜는 옵션을 한 줄 가짐.

### 요약/리포트

12. `aacpd/bin/log-cost-summary.py` 가 한 줄 stdout 출력:
    ```
    cost_summary: mvp -15%p (37→22), ruff -1%p (22→21), pytest -2%p (21→19), review -1%p (19→18), fix -2%p (18→16)
    ```
13. `agent-stats.json::cost_details` 가 50개 초과 시 FIFO drop (윈도우 회전).
14. `aacpd` step 4 종료 직전에 `aacpd/bin/log-cost-summary.py <repo> <issue-N>` 호출.

## 승인 기준

- [ ] `aacpd/bin/cost_entry.py::CostDetailEntry` 가 coder/model/reasoning_effort/bucket/reason 5개 필드를 가짐
- [ ] `aacpd/bin/log-cost.py` 가 단일 진입점 — 8 wrapper 부재
- [ ] `bash $AACP_BIN/log-cost.py <repo> issue-N "before mvp"` 호출이
      exit 0 으로 종료, agent-stats.json 의 cost_details 에 1 이벤트 추가,
      `reasoning_effort`/`bucket`/`reason` 중 가능한 한 채워짐
- [ ] minimax 같은 미지원 provider 에서도 event 가 박히고 pct=null + reason="unsupported_provider" 가 들어가 있음
- [ ] `aacpd/bin/log-cost-summary.py <repo> issue-N` 이 마지막 50 이벤트의 인접 diff 를 한 줄 stdout 으로 출력 (UTC 로컬 오프셋 유지)
- [ ] **모든 snapshot 호출이 silent** — AACP_VERBOSE=1 없을 때 stdout/stderr 0 byte
- [ ] **외부 harness-project 의존 0** — 모든 wrapper 가 `aacpd/bin/` 안에서 자기완결

## 검증

`regression-tests/verify-issue-57.sh`:
1. `cost_entry.py` 의 Pydantic 모델이 5개 추가 필드를 받는지
2. 임시 repo 에 빈 `agent-stats.json` 만든 뒤 `log-cost.py` 호출 → cost_details
   1개 추가, coder/model/reasoning_effort 필드 채워짐 (가능 범위 내)
3. `reason` 필드가 null pct 일 때 `"unsupported_provider"` 또는
   `"lookup_unavailable"` 임
4. `log-cost-summary.py` 가 cost_details 인접 diff 한 줄 stdout — 가짜 4
   이벤트로 pcts `37 → 22 → 21 → 19` 를 박고 실행하면 `cost_summary:
   mvp -15%p (37→22), step2 -1%p (22→21), step3 -2%p (21→19)` 같은 출력
5. **silent 패스**: `bash $BIN/log-cost.py ...` 후 stdout/stderr capture 가
   0 byte (verbose 모드 아닐 때)

## 구현 결과

- **구현 완료 일시**: 2026-08-11T20:56:04-04:00
- **수정/신규 파일**:
  - `bin/cost_entry.py` - `CostDetailEntry` Pydantic 모델에 coder, model, reasoning_effort, bucket, reason 5개 필드 추가 및 50개 FIFO drop 추가
  - `bin/log-cost.py` - 단일 계측 진입점 신규 작성 (8개 개별 log-cost-*.py 삭제)
  - `bin/log-cost.sh`, `bin/log-cost.bat`, `bin/log-cost.ps1` 및 기존 shell wrapper 갱신
  - `bin/log-cost-summary.py` - cost_details 인접 diff 한 줄 출력 갱신
  - `pyrightconfig.json` 신규 작성
  - `regression-tests/verify-issue-57.sh` 신규 작성
- **계획 대비 차이점**: 없음
- **검증 결과**: `verify-issue-57.sh`, `run-ruff`, `run-pyright`, `run-unit-tests`, `run-regression-tests`, `run-pyright-full` 모두 성공 (PASS)

