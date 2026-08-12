#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# ///
"""aacpd/bin/run-regression-tests.py — 모든 verify-issue-*.sh / verify-autofix-*.sh
를 순차 실행하는 .py 변종. `bash run-regression-tests.sh` 와 같은 동작.

기본 동작:
- regression-tests/*.sh 를 glob 해서 정렬 순으로 실행
- PASS/FAIL 카운트하고 마지막 줄에 요약 출력
- FAIL 이 있으면 exit 1

CWD 는 target repo root 라고 가정한다.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    rg_dir = Path("regression-tests")
    if not rg_dir.is_dir():
        print("ERROR: regression-tests/ 부재", file=sys.stderr)
        return 1

    scripts = sorted(rg_dir.glob("*.sh"))
    if not scripts:
        print("NOTE: 실행할 verify-issue-*.sh 가 없음", file=sys.stderr)
        return 0

    pass_count = 0
    fail_count = 0
    for script in scripts:
        print(f"=== {script}")
        result = subprocess.run(["bash", str(script)])
        if result.returncode == 0:
            pass_count += 1
        else:
            fail_count += 1

    print(f"\nregression: {pass_count} passed, {fail_count} failed")
    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
