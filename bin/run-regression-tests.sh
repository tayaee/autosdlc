#!/usr/bin/env bash
set -euo pipefail

GATE_NAME="run-regression-tests"
TMP_DIR="${TMPDIR:-/tmp}"
REPORT="${TMP_DIR}/aacpd-${GATE_NAME}-$$.log"

run_gate() {
PASS=0
FAIL=0
FAILED_SCRIPTS=()
shopt -s nullglob
for script in regression-tests/verify-issue-*.sh; do
    echo ""
    if bash "$script"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED_SCRIPTS+=("$script")
    fi
done
echo ""
echo "============================="
echo "Regression results: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed scripts:"
    for s in "${FAILED_SCRIPTS[@]}"; do
        echo "  - $s"
    done
    exit 1
fi
}

if [ "${AACP_VERBOSE:-0}" = "1" ]; then
    set +e
    run_gate 2>&1 | tee "$REPORT"
    EXIT=${PIPESTATUS[0]}
    set -e
    echo "REPORT file: $REPORT"
    echo "--- Last 10 lines ---"
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
