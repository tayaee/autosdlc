#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""aacpd/bin/run-pyright.py — pyright 검증 게이트 .py 변종.

src/ 디렉터리가 있으면 그 안에서, 없으면 전체 프로젝트를 검사한다
(`bash run-pyright.sh` 와 동일 분기). aacpd/bin/ 의 4 변종 중 하나.
CWD 가 target repo root 라고 가정.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    src = Path("src")
    if src.is_dir():
        return subprocess.call(["uv", "run", "pyright", "src"])
    return subprocess.call(["uv", "run", "pyright", "."])


if __name__ == "__main__":
    sys.exit(main())
