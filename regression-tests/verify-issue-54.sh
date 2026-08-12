#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Verifying issue-54 ==="

# 1. 4 skill directories non-existence
for skill in autoqa autodev autofix autoqafix; do
    if [ -d "skills/$skill" ]; then
        echo "FAIL: skills/$skill still exists"
        exit 1
    fi
done

# 2. Check no references to old skill paths in repo (excluding issues/archive/ and issues/issue-54.md)
HITS=$(grep -rnE '\.claude/skills/(autoqafix|autoqa|autofix|autodev)' . \
    | grep -v 'issues/archive/' \
    | grep -v 'issues/issue-54.md' \
    | grep -v 'regression-tests/verify-issue-' || true)

if [ -n "$HITS" ]; then
    echo "FAIL: Unexpected skill path references found:"
    echo "$HITS"
    exit 1
fi

# 3. Check bin/ has autoqafix*.py and wrappers/
if [ ! -f "bin/autoqafix_core.py" ] || [ ! -f "bin/autoqafix-doctor.py" ]; then
    echo "FAIL: autoqafix*.py missing in bin/"
    exit 1
fi
if [ ! -d "bin/wrappers" ]; then
    echo "FAIL: bin/wrappers missing"
    exit 1
fi

# 4. bash -n on autoqa-loop.sh
bash -n autoqa-loop.sh

# 5. Check CHANGELOG line
if ! grep -q "BREAKING: autoqa/autodev/autofix/autoqafix SKILL.md 제거" CHANGELOG.md; then
    echo "FAIL: CHANGELOG breaking change line missing"
    exit 1
fi

echo "✓ Issue-54 verification passed"
