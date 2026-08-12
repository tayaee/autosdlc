# issue-56: aacpd 검증 게이트 silent-pass / loud-fail 가드 + `run-*.py` 변종 추가

agent-tier: local-ok

## 배경

aacpd 의 step 0 검증 게이트 (`run-ruff`, `run-pyright`, `run-unit-tests`,
`run-regression-tests`, `run-pyright-full`) 가 출력을 **stdout 으로 직접
뿜기** 때문에 LLM 의 다음 컨텍스트에 그대로 들어와 토큰을 잡아먹는다.
도구 자체는 0-token 이지만 출력 전체를 다시 읽는 행위가 누적된다.

autotddreviewfix 흐름(가장 긴 path) 에서 이 효과가 누적되어
`/autotddreviewfix 3` 한 사이클에 검증 게이트 5개 × 통과 = 컨텍스트 폭탄
5회가 박힌다. 그리고 aacpd 의 검증 게이트 wrapper 는 4 도구 모두 `.sh` 만
제공 — `.py` 변종은 사용자가 별도로 부를 수도 있어 self-contained 가 약하다.

## 요구사항

1. **`aacpd/bin/run-*.sh` (및 .bat, .ps1) 의 stdout 을 모두 파일로 redirect**:
   ```bash
   REPORT="${TMPDIR:-/tmp}/aacpd-<gate>-$$.log"
   bash "$BIN/run-<name>.sh" >"$REPORT" 2>&1
   EXIT=$?
   if [ "$EXIT" -eq 0 ]; then
     exit 0   # silent pass
   else
     # loud fail — tail 만 보여줘서 LLM 이 디버그
     tail -n 60 "$REPORT"
     exit "$EXIT"
   fi
   rm -f "$REPORT"
   ```
2. **`.py` 변종은 `aacpd/bin/run-<name>.py` 로 추가** — `.sh` 가 인터프리터
   박고 `uv run` 으로 동일 동작 (또는 lint/check 단일 호출이면 python 모듈
   자체). 어느 쪽이든 `bash run-<name>.py` 가 작동하도록 PEP 723 인라인
   의존성으로 `click` 또는 자체 의존성을 박음
3. **`.bat` 변종은 Windows cmd 용, `.ps1` 은 PowerShell 용** — 둘 다 같은
   silent-pass / loud-fail 규약. Windows 에서 `tail -n 60` 대신 `Get-Content -Tail`
   또는 동등
4. **aacp.sh 의 `run_check()` 함수가 silent-pass 자동 적용** — 디폴트가
   silent 이고 `AACP_VERBOSE=1` 환경변수일 때만 stdout 전체 출력
5. **`AACP_VERBOSE=1` 일 때 `REPORT` 파일 위치 + 마지막 10 줄도 stdout 에
   같이 출력** (디버깅 편의)
6. **fail 시 LLM 이 `Read` 로 `$REPORT` 파일 자체를 짧게 열어서** 진단할 수
   있도록 `$REPORT` 경로를 stderr 에 박음

## 승인 기준

- [ ] `aacpd/bin/` 의 모든 `run-*` 변종 4종(.sh/.bat/.ps1/.py) 존재
- [ ] `aacpd/bin/run-pyright.sh` 가 (a) exit 0 시 stdout 0 byte, (b) exit != 0
      시 tail 60 + exit code 보존
- [ ] `aacpd/bin/run-pyright.py` 가 `bash run-pyright.py` 로도 동작 (PEP 723)
- [ ] `aacp.sh` 의 `run_check()` 가 silent 패스 시 stdout 출력 0 byte
- [ ] `AACP_VERBOSE=1` 로 실행 시 통과 시점의 full 출력 + REPORT 경로 표시
- [ ] 검증 게이트가 실패한 fixture 환경에서 `run-pyright.sh` 가 마지막 60줄 +
      REPORT 파일 경로를 stderr 에 박고 종료코드 != 0 으로 끝남
- [ ] PASS 케이스의 LLM 컨텍스트 누적 byte = 0 (한 사이클 검증 게이트 5개 통과 기준)

## 검증

`regression-tests/verify-issue-56.sh`:
1. 4 변종 파일 존재
2. **pass case**: 가짜 ruff/bin 만들어 `EXIT=0` 리턴 → stdout 0 byte 확인
   (`out=$(bash run-ruff.sh); test -z "$out"`)
3. **fail case**: 가짜가 `EXIT=42` + stderr 출력 → 마지막 60줄 + REPORT 경로
   stderr 박힘 확인
4. `.py` 변종 `bash -n` (또는 `uv run --help`) 통과
5. `AACP_VERBOSE=1 bash run-pyright.sh` 시 통과라도 full 출력 stdout 에 나옴

## 구현 결과

(작업 후 기입)
