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
    coder='minimax',
    model='MiniMax-M3',
    reasoning_effort='medium',
    bucket='default',
    reason='unsupported_provider',
    five_hour_used_pct=None,
    seven_day_used_pct=None,
    description='test'
)
assert entry.coder == 'minimax'
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
LOG_OUT=$(python3 bin/log-cost.py "$TMP_REPO" issue-999 "before mvp" 2>&1)
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
assert e['description'] == 'before mvp'
assert 'coder' in e
assert 'reason' in e
"

# 4. log-cost-summary.py diff test
cat > "$TMP_REPO/issues/issue-999__agent-stats.json" <<'EOF'
{
  "issue": 999,
  "started": "2026-08-11T20:00:00-04:00",
  "cost_details": [
    {"ts": "2026-08-11T20:00:00-04:00", "coder": "sonnet", "model": "Sonnet", "five_hour_used_pct": 37.0, "seven_day_used_pct": null, "description": "start"},
    {"ts": "2026-08-11T20:05:00-04:00", "coder": "sonnet", "model": "Sonnet", "five_hour_used_pct": 22.0, "seven_day_used_pct": null, "description": "mvp"},
    {"ts": "2026-08-11T20:10:00-04:00", "coder": "sonnet", "model": "Sonnet", "five_hour_used_pct": 21.0, "seven_day_used_pct": null, "description": "step2"},
    {"ts": "2026-08-11T20:15:00-04:00", "coder": "sonnet", "model": "Sonnet", "five_hour_used_pct": 19.0, "seven_day_used_pct": null, "description": "step3"}
  ]
}
EOF

SUMMARY_OUT=$(python3 bin/log-cost-summary.py "$TMP_REPO" issue-999)
if ! echo "$SUMMARY_OUT" | grep -q "cost_summary: mvp -15%p (37→22), step2 -1%p (22→21), step3 -2%p (21→19)"; then
    echo "FAIL: log-cost-summary.py unexpected output: $SUMMARY_OUT"
    exit 1
fi

echo "✓ Issue-57 verification passed"
