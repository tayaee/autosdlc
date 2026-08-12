#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# ///
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> int:
    gate_name = "run-pyright-full"
    verbose = os.environ.get("AACP_VERBOSE", "0") == "1"
    report = Path(tempfile.gettempdir()) / f"aacpd-{gate_name}-{os.getpid()}.log"
    
    cmd = ['uv', 'run', 'pyright']
    if len(sys.argv) > 1:
        cmd.extend(sys.argv[1:])
        
    if verbose:
        res = subprocess.run(cmd, check=False)
        return res.returncode
    else:
        with open(report, "w", encoding="utf-8") as fp:
            res = subprocess.run(cmd, stdout=fp, stderr=subprocess.STDOUT, check=False)
        if res.returncode == 0:
            if report.exists():
                report.unlink()
            return 0
        else:
            sys.stderr.write(f"ERROR: {gate_name} failed with exit code {res.returncode}.\n")
            sys.stderr.write(f"Full log saved to: {report}\n")
            sys.stderr.write(f"--- Last 60 lines of {report} ---\n")
            if report.exists():
                lines = report.read_text(encoding="utf-8", errors="replace").splitlines()
                for line in lines[-60:]:
                    sys.stderr.write(line + "\n")
            return res.returncode

if __name__ == "__main__":
    sys.exit(main())
