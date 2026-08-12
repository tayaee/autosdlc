#!/usr/bin/env bash
# uv run wrapper -- log-cost-summary.py declares a PEP 723 inline dependency on
# pydantic, so it must be run via `uv run`, not plain `python3`
# (which would fail with ModuleNotFoundError unless pydantic happens to
# already be installed in the ambient interpreter). Resolves its own
# directory so it works regardless of the caller's CWD.
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec uv run "$SCRIPT_DIR/log-cost-summary.py" "$@"
