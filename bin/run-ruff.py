#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# ///
"""aacpd/bin/run-ruff.py — aacpd 의 ruff 검증 게이트 .py 변종.

`bash run-ruff.sh` 와 동일 동작을 한다 — `uv run ruff check --fix .`
를 subprocess 로 실행. aacpd/bin/ 의 4 변종 중 하나로, Windows 사용자가
PowerShell 이 아닌 cmd 가 없는 환경(예: git-bash 만 있는 경우)에서
대체 진입점으로 사용 가능.

CWD 가 이미 target project root 라고 가정한다 — aacp.sh 의 step 0 가
이를 보장한다. 호출 형태는 skill 매개변수 없이 단순히 `python3
run-ruff.py` 또는 `bash run-ruff.py` 모두 가능.
"""
from __future__ import annotations

import subprocess
import sys


def main() -> int:
    return subprocess.call(["uv", "run", "ruff", "check", "--fix", "."])


if __name__ == "__main__":
    sys.exit(main())
