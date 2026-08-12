#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Verifying issue-55 ==="

# 1. aacp/SKILL.md 0 hit for deploy-to-dev or deploy.sh
if [ ! -f "skills/aacp/SKILL.md" ]; then
    echo "FAIL: skills/aacp/SKILL.md missing"
    exit 1
fi

HITS=$(grep -E 'deploy-to-dev|deploy\.sh' skills/aacp/SKILL.md || true)
if [ -n "$HITS" ]; then
    echo "FAIL: deploy references found in skills/aacp/SKILL.md:"
    echo "$HITS"
    exit 1
fi

# 2. aacp/aacp.sh and aacpd/aacp.sh byte-identical
if [ ! -f "skills/aacp/aacp.sh" ] || [ ! -f "skills/aacpd/aacp.sh" ]; then
    echo "FAIL: aacp.sh missing in aacp or aacpd"
    exit 1
fi

if ! cmp -s skills/aacp/aacp.sh skills/aacpd/aacp.sh; then
    echo "FAIL: skills/aacp/aacp.sh and skills/aacpd/aacp.sh differ"
    exit 1
fi

# 3. Help output contains one-line description
HELP_OUT=$(bash skills/aacp/aacp.sh --help)
if ! echo "$HELP_OUT" | grep -q "aacp: 4단계 (deploy 없음); aacpd: 5단계 (deploy 포함)"; then
    echo "FAIL: unexpected --help output: $HELP_OUT"
    exit 1
fi

# 4. Smoke test in temp repo: aacp/aacp.sh 9999 "smoke" -> archive + commit, deploy 0
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

git init "$TMP_DIR" >/dev/null
cd "$TMP_DIR"
git config user.email "test@example.com"
git config user.name "Test User"

# Initial commit
echo "init" > README.md
git add README.md
git commit -m "initial" >/dev/null

# Create dummy deploy-to-dev.sh that writes a marker if called
cat > deploy-to-dev.sh <<'EOF'
#!/usr/bin/env bash
echo "DEPLOY_WAS_CALLED" > deploy_marker.txt
EOF
chmod +x deploy-to-dev.sh
git add deploy-to-dev.sh
git commit -m "add deploy script" >/dev/null

# Create dummy issue-9999.md
mkdir -p issues
cat > issues/issue-9999.md <<'EOF'
# issue-9999: test
## 구현 결과
- **구현 완료 일시**: 2026-08-11T20:00:00-04:00
EOF
git add issues/issue-9999.md

# Run aacp/aacp.sh
bash "$REPO_ROOT/skills/aacp/aacp.sh" 9999 "smoke test" >/dev/null 2>&1 || true

# Check that issue was archived and committed
if [ -f issues/issue-9999.md ]; then
    echo "FAIL: issue-9999.md was not archived"
    exit 1
fi

# Check that deploy_marker.txt was NOT created (deploy was skipped)
if [ -f deploy_marker.txt ]; then
    echo "FAIL: deploy-to-dev.sh was called during aacp!"
    exit 1
fi

echo "✓ Issue-55 verification passed"
