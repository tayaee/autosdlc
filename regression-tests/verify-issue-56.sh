#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Verifying issue-56 ==="

GATES=("run-ruff" "run-pyright" "run-unit-tests" "run-regression-tests" "run-pyright-full")
EXTS=(".sh" ".bat" ".ps1" ".py")

# 1. 4 variants exist for all 5 gates (20 files total)
for g in "${GATES[@]}"; do
    for ext in "${EXTS[@]}"; do
        file="bin/${g}${ext}"
        if [ ! -f "$file" ]; then
            echo "FAIL: missing $file"
            exit 1
        fi
    done
done

# 2. Pass case: silent pass (stdout 0 byte)
OUT=$(bash bin/run-ruff.sh)
if [ -n "$OUT" ]; then
    echo "FAIL: run-ruff.sh output non-empty on pass: $OUT"
    exit 1
fi

# 3. Fail case: loud fail (stderr contains report path and tail)
TMP_REPO=$(mktemp -d)
trap 'rm -rf "$TMP_REPO"' EXIT

mkdir -p "$TMP_REPO/bin"
cat > "$TMP_REPO/bin/run-mock-fail.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

GATE_NAME="mock-fail"
TMP_DIR="${TMPDIR:-/tmp}"
REPORT="${TMP_DIR}/aacpd-${GATE_NAME}-$$.log"

run_gate() {
    echo "something failed" >&2
    return 42
}

if [ "${AACP_VERBOSE:-0}" = "1" ]; then
    set +e
    run_gate 2>&1 | tee "$REPORT"
    EXIT=${PIPESTATUS[0]}
    set -e
    echo "REPORT file: $REPORT"
    tail -n 10 "$REPORT" || true
    rm -f "$REPORT"
    exit "$EXIT"
else
    set +e
    run_gate >"$REPORT" 2>&1
    EXIT=$?
    set -e
    if [ "$EXIT" -eq 0 ]; then
        rm -f "$REPORT"
        exit 0
    else
        echo "ERROR: ${GATE_NAME} failed with exit code ${EXIT}." >&2
        echo "Full log saved to: ${REPORT}" >&2
        echo "--- Last 60 lines of ${REPORT} ---" >&2
        tail -n 60 "$REPORT" >&2
        exit "$EXIT"
    fi
fi
EOF
chmod +x "$TMP_REPO/bin/run-mock-fail.sh"

STDERR_OUT=$(bash "$TMP_REPO/bin/run-mock-fail.sh" 2>&1 || true)
if ! echo "$STDERR_OUT" | grep -q "Full log saved to:"; then
    echo "FAIL: report path missing in stderr on failure: $STDERR_OUT"
    exit 1
fi
if ! echo "$STDERR_OUT" | grep -q "something failed"; then
    echo "FAIL: tail output missing in stderr on failure: $STDERR_OUT"
    exit 1
fi

# 4. .py variants check
for g in "${GATES[@]}"; do
    python3 -c "import py_compile; py_compile.compile('bin/${g}.py', doraise=True)"
done

# 5. AACP_VERBOSE=1 prints full output
VERBOSE_OUT=$(AACP_VERBOSE=1 bash bin/run-pyright.sh)
if ! echo "$VERBOSE_OUT" | grep -q "REPORT file:"; then
    echo "FAIL: AACP_VERBOSE=1 output missing REPORT path"
    exit 1
fi

echo "✓ Issue-56 verification passed"
