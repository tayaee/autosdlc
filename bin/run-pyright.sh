#!/usr/bin/env bash
set -euo pipefail

ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        return 0
    fi
    if [ -x "$HOME/.local/bin/uv" ]; then
        export PATH="$HOME/.local/bin:$PATH"
        return 0
    fi
    if command -v mise >/dev/null 2>&1; then
        echo "uv를 찾을 수 없습니다. mise를 사용하여 uv를 설치합니다..." >&2
        mise use -g uv@latest >/dev/null 2>&1 || mise install uv >/dev/null 2>&1 || true
        if command -v mise >/dev/null 2>&1; then
            eval "$(mise env 2>/dev/null)" || true
        fi
        if command -v uv >/dev/null 2>&1; then
            uv python install >/dev/null 2>&1 || true
            return 0
        fi
    fi
    echo "[원인] uv 또는 mise를 찾을 수 없습니다." >&2
    echo "[조치] curl -LsSf https://astral.sh/uv/install.sh | sh 또는 mise install uv를 실행하세요." >&2
    exit 127
}
ensure_uv


GATE_NAME="run-pyright"
TMP_DIR="${TMPDIR:-/tmp}"
REPORT="${TMP_DIR}/aacpd-${GATE_NAME}-$$.log"

run_gate() {
if [ -d src ]; then uv run pyright src; else uv run pyright .; fi
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
