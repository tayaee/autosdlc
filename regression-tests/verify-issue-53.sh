#!/usr/bin/env bash
# verify-issue-53: tools→bin 개명 + aacpd/defaults/ 흡수 검증.
#
# 승인 기준:
# 1. autosdlc/tools/ 디렉터리 부재
# 2. autosdlc/bin/ 디렉터리 존재 + 8 wrapper + entry + derive + agent-stats + log-cost-summary
# 3. run-* 5 종 × 4 변종 (.sh/.bat/.ps1/.py) 모두 존재
# 4. aacpd/defaults/ 부재 (= bin/ 으로 흡수)
# 5. SKILL.md 안의 tools/ 잔재 grep 0
# 6. SKILL.md 안의 DEFAULTS_DIR 잔재 grep 0
# 7. aacp.sh 의 DEFAULTS_DIR 변수 갱신 확인
set -euo pipefail

cd /home/user1/git/autosdlc

echo "==> verify-issue-53 (tools → bin migration)"
echo

# --- 1. tools/ 부재 ---
echo "[1] autosdlc/tools/ 부재"
if [ -d tools ]; then
  echo "ERROR: autosdlc/tools/ 가 아직 존재함 — 마이그레이션 미완료" >&2
  exit 1
fi

# --- 2. bin/ 존재 + 필수 파일 ---
echo "[2] autosdlc/bin/ 의 필수 파일"
test -d bin || { echo "ERROR: bin/ 부재"; exit 1; }

for f in cost_entry.py derive_fixing_slug.py \
         log-cost-summary.py agent-stats-archive.py; do
  test -f "bin/$f" || { echo "ERROR: bin/$f 부재"; exit 1; }
done

# 8 wrapper 가 단일 log-cost.py 로 통합되었거나 8 wrapper 그대로 보존된 경우 모두 OK
# 단, 둘 중 하나로 결정 — 둘 다 있는 것은 redundancy
HAS_UNIFIED=0
HAS_PER=0
for f in bin/log-cost.py; do
  if [ -f "$f" ]; then HAS_UNIFIED=1; fi
done
PER_COUNT=$(ls bin/log-cost-*.py 2>/dev/null | wc -l)
HAS_PER=$PER_COUNT
if [ $HAS_UNIFIED -eq 1 ] && [ $HAS_PER -gt 0 ]; then
  echo "ERROR: bin/log-cost.py 와 bin/log-cost-*.py 가 공존 — 통합 또는 8-wrapper 중 하나만" >&2
  exit 1
fi

# --- 3. run-* 5 종 × 4 변종 ---
echo "[3] run-* 5 종 × 4 변종 (.sh/.bat/.ps1/.py)"
for tool in run-ruff run-pyright run-pyright-full run-unit-tests run-regression-tests; do
  for ext in sh bat ps1 py; do
    test -f "bin/${tool}.${ext}" || { echo "ERROR: bin/${tool}.${ext} 부재"; exit 1; }
  done
done

# --- 4. aacpd/defaults/ 부재 ---
echo "[4] aacpd/defaults/ 부재"
if [ -d .claude/skills/aacpd/defaults ]; then
  echo "ERROR: aacpd/defaults/ 가 아직 존재 — bin/ 으로 흡수 미완료" >&2
  exit 1
fi

# aacpd/ 안에 bin/ 이 있으면 안 됨 (사용자 의도: skills 는 SKILL.md 만)
if [ -d .claude/skills/aacpd/bin ]; then
  echo "ERROR: aacpd/bin/ 은 금지 (사용자 의도: 모든 스크립트는 autosdlc/bin/)" >&2
  exit 1
fi

# --- 5. SKILL.md 안 tools/ 잔재 0 ---
echo "[5] SKILL.md 안 tools/ 잔재 grep"
# pipefail + set -e 와 grep 의 zero-match exit 1 이 충돌하므로
# || true 로 grep 결과가 비어도 파이프 실패 방지
HITS=$( (grep -rE 'tools/(log-cost|cost_entry|derive_fixing_slug|agent-stats-archive)' .claude/skills/ 2>/dev/null || true) | wc -l)
if [ "$HITS" -gt 0 ]; then
  echo "ERROR: tools/ 잔재 $HITS 건" >&2
  (grep -rE 'tools/(log-cost|cost_entry|derive_fixing_slug|agent-stats-archive)' .claude/skills/ 2>/dev/null || true)
  exit 1
fi

# --- 6. SKILL.md 안 DEFAULTS_DIR 잔재 0 ---
echo "[6] SKILL.md / aacp.sh 안 DEFAULTS_DIR 잔재 grep"
HITS=$( (grep -rE 'DEFAULTS_DIR|defaults/' .claude/skills/ .claude/skills/aacpd/aacp.sh 2>/dev/null || true) | wc -l)
if [ "$HITS" -gt 0 ]; then
  echo "ERROR: DEFAULTS_DIR 잔재 $HITS 건" >&2
  (grep -rE 'DEFAULTS_DIR|defaults/' .claude/skills/ .claude/skills/aacpd/aacp.sh 2>/dev/null || true)
  exit 1
fi

# aacpd/aacp.sh 의 BIN_DIR 변수 존재 확인
if ! grep -qE 'BIN_DIR|AUTOSDLC_BIN_DIR' .claude/skills/aacpd/aacp.sh 2>/dev/null; then
  echo "ERROR: aacp.sh 안 BIN_DIR / AUTOSDLC_BIN_DIR 변수 없음" >&2
  exit 1
fi

echo "=== ALL CHECKS PASSED ==="
