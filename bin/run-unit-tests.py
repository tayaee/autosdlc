#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# ///
"""aacpd/bin/run-unit-tests.py — `uv run pytest tests/ -v` 의 .py 변종.

aacpd/bin/ 의 4 변종 중 하나. 호출자가 `python3 run-unit-tests.py` 형태로
부른다. exit code 는 그대로 보존.
"""
from __future__ import annotations

import subprocess
import sys


def main() -> int:
    return subprocess.call(["uv", "run", "pytest", "tests/", "-v"])


if __name__ == "__main__":
    sys.exit(main())
