#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["pydantic"]
# ///
"""log-cost — 단일 log-cost 계측 진입점 (issue-57).

사용법:
    log-cost.py [--coder CODER] [--model MODEL] [--reasoning-effort EFFORT]
                [--quiet|--verbose] [--auto] [--dryrun]
                <repo-path> <issue-N|autofix-N> "<description>"
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Add bin/ directory to sys.path so cost_entry can be imported
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from cost_entry import append_cost_detail, query_check_usage_pct


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Log cost snapshot for issue")
    parser.add_argument("--coder", default="sonnet", help="Coder/provider identifier")
    parser.add_argument("--model", default="Claude Sonnet 3.6", help="Full model name")
    parser.add_argument("--reasoning-effort", default=None, help="Reasoning effort")
    parser.add_argument("--quiet", action="store_true", help="Quiet mode (default)")
    parser.add_argument("--verbose", action="store_true", help="Verbose mode")
    parser.add_argument("--auto", action="store_true", help="Auto detect model")
    parser.add_argument("--dryrun", action="store_true", help="Dry run mode")
    parser.add_argument("repo_path", help="Target repository path")
    parser.add_argument("target", help="Issue or autofix ID (e.g. issue-57)")
    parser.add_argument("description", help="Snapshot description")

    args = parser.parse_args(argv)

    verbose = args.verbose or os.environ.get("AACP_VERBOSE", "0") == "1"

    reasoning_effort = (
        args.reasoning_effort
        or os.environ.get("CLAUDE_CODE_REASONING_EFFORT")
        or os.environ.get("CLAUDE_CODE_EFFORT")
        or os.environ.get("CLAUDE_REASONING_EFFORT")
        or os.environ.get("CLAUDE_EFFORT")
        or os.environ.get("REASONING_EFFORT")
        or os.environ.get("EFFORT")
        or "medium"
    )

    try:
        repo = Path(args.repo_path).resolve()
        five_h, seven_d, bucket, reason = query_check_usage_pct(args.coder, args.model)

        path, entry = append_cost_detail(
            repo,
            args.target,
            coder=args.coder,
            model=args.model,
            reasoning_effort=reasoning_effort,
            bucket=bucket,
            reason=reason,
            five_hour_used_pct=five_h,
            seven_day_used_pct=seven_d,
            description=args.description,
            dryrun=args.dryrun,
        )

        if verbose:
            prefix = "[dryrun] " if args.dryrun else ""
            print(f"{prefix}{path}: {entry.model_dump_json()}", file=sys.stderr)

    except Exception as exc:  # noqa: BLE001
        if verbose:
            print(f"WARN: log-cost failed: {exc}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
