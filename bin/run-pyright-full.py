#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# ///
"""aacpd/bin/run-pyright-full.py — 전체 프로젝트 pyright 검증 .py 변종.

`run-pyright.py` 는 src/ 만 빠르게 보지만 `run-pyright-full.py` 는
전체 프로젝트를 검사. aacpd/bin/ 의 4 변종 중 하나.
"""
from __future__ import annotations

import subprocess
import sys


def main() -> int:
    return subprocess.call(["uv", "run", "pyright", "."])


if __name__ == "__main__":
    sys.exit(main())
