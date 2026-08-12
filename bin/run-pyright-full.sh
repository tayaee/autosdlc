#!/usr/bin/env bash
set -euo pipefail

GATE_NAME="run-pyright-full"
TMP_DIR="${TMPDIR:-/tmp}"
REPORT="${TMP_DIR}/aacpd-${GATE_NAME}-$$.log"

run_gate() {
uv run pyright
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
