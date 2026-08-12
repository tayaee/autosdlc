#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Verifying issue-57 ==="

# 1. Pydantic CostDetailEntry schema check
python3 -c "
from bin.cost_entry import CostDetailEntry
entry = CostDetailEntry(
    ts='2026-08-11T20:00:00-04:00',
    script_id='minimax',
    model='MiniMax-M3',
    reasoning_effort='medium',
    bucket='default',
    reason='unsupported_provider',
    five_hour_used_pct=None,
    seven_day_used_pct=None,
    ts_description='implement-start'
)
assert entry.script_id == 'minimax'
assert entry.ts_description == 'implement-start'
assert entry.reason == 'unsupported_provider'
"

# 2. Temp repo test for log-cost.py
TMP_REPO=$(mktemp -d)
trap 'rm -rf "$TMP_REPO"' EXIT

mkdir -p "$TMP_REPO/issues"
cat > "$TMP_REPO/issues/issue-999__agent-stats.json" <<'EOF'
{
  "issue": 999,
  "started": "2026-08-11T20:00:00-04:00",
  "cost_details": []
}
EOF

# 5. Silent pass check: stdout and stderr 0 byte when not in verbose mode
LOG_OUT=$(python3 bin/log-cost.py "$TMP_REPO" issue-999 "implement-start" 2>&1)
if [ -n "$LOG_OUT" ]; then
    echo "FAIL: log-cost.py not silent by default: $LOG_OUT"
    exit 1
fi

# Check that entry was added to agent-stats.json
python3 -c "
import json
from pathlib import Path

p = Path('$TMP_REPO/issues/issue-999__agent-stats.json')
data = json.loads(p.read_text())
details = data.get('cost_details', [])
assert len(details) == 1
e = details[0]
assert e['ts_description'] == 'implement-start'
assert 'script_id' in e
assert 'reason' in e
"

# 4. log-cost-summary.py net diff & sum test (user requirement: 65 -> 68 = 3.0)
cat > "$TMP_REPO/issues/issue-999__agent-stats.json" <<'EOF'
{
  "issue": 999,
  "started": "2026-08-11T20:00:00-04:00",
  "cost_details": [
    {"ts": "2026-08-11T22:06:53-04:00", "script_id": "minimax", "model": "minimax", "five_hour_used_pct": 65.0, "seven_day_used_pct": 39.0, "ts_description": "implement-start"},
    {"ts": "2026-08-11T22:12:09-04:00", "script_id": "minimax", "model": "minimax", "five_hour_used_pct": 68.0, "seven_day_used_pct": 39.0, "ts_description": "implement-end"}
  ]
}
EOF

SUMMARY_OUT=$(python3 bin/log-cost-summary.py "$TMP_REPO" issue-999)
if ! echo "$SUMMARY_OUT" | grep -q "cost_summary: implement-end +3%p (65→68)"; then
    echo "FAIL: log-cost-summary.py unexpected text output: $SUMMARY_OUT"
    exit 1
fi

python3 -c "
import json
from pathlib import Path
p = Path('$TMP_REPO/issues/issue-999__agent-stats.json')
data = json.loads(p.read_text())
cs = data.get('cost_summary', {})
bm = cs.get('by_model', {}).get('minimax', {})
assert bm.get('five_hour_sum') == 3.0, f'Expected 3.0, got {bm.get(\"five_hour_sum\")}'
assert bm.get('seven_day_sum') == 0.0, f'Expected 0.0, got {bm.get(\"seven_day_sum\")}'
"

echo "✓ Issue-57 verification passed"
