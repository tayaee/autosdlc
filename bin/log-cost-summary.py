#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""log-cost-summary — cost_details를 스캔해 단계별 cost_summary(pct diff)를 계산.

사용법:
    log-cost-summary.py [--dryrun] <repo-path> <issue-N|autofix-N>
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

STREAM_RE = re.compile(r"^(issue|autofix)-([0-9]+)$")


def parse_stream_id(value: str) -> tuple[str, str]:
    m = STREAM_RE.match(value)
    if not m:
        raise ValueError(f"스트림 ID 형식이 아님: {value!r} (issue-N 또는 autofix-N)")
    return m.group(1), m.group(2)


def find_stats_file(repo: Path, target: str) -> Path:
    stream, n = parse_stream_id(target)
    path = repo / "issues" / f"{stream}-{n}__agent-stats.json"
    if not path.is_file():
        raise FileNotFoundError(f"{path} 없음")
    return path


def compute_cost_summary(cost_details: list[dict]) -> tuple[dict, str]:
    parts = []
    by_model: dict[str, dict[str, list]] = {}

    for entry in cost_details:
        model = entry.get("model", "unknown")
        bucket = by_model.setdefault(model, {"five_hour": [], "seven_day": []})
        bucket["five_hour"].append(entry.get("five_hour_used_pct"))
        bucket["seven_day"].append(entry.get("seven_day_used_pct"))

    for i in range(1, len(cost_details)):
        prev = cost_details[i - 1]
        curr = cost_details[i]
        p_pct = prev.get("five_hour_used_pct")
        c_pct = curr.get("five_hour_used_pct")
        desc = curr.get("ts_description") or curr.get("description", f"step{i}")
        if p_pct is not None and c_pct is not None:
            diff = round(c_pct - p_pct, 1)
            p_str = f"{p_pct:.1f}".rstrip("0").rstrip(".")
            c_str = f"{c_pct:.1f}".rstrip("0").rstrip(".")
            diff_str = f"{diff:+.1f}".rstrip("0").rstrip(".")
            parts.append(f"{desc} {diff_str}%p ({p_str}→{c_str})")

    summary_str = "cost_summary: " + (", ".join(parts) if parts else "(no diffs)")

    by_model_summary = {}
    for model, data in by_model.items():
        five_h = [v for v in data["five_hour"] if v is not None]
        seven_d = [v for v in data["seven_day"] if v is not None]
        five_h_net = round(five_h[-1] - five_h[0], 1) if len(five_h) >= 1 else None
        seven_d_net = round(seven_d[-1] - seven_d[0], 1) if len(seven_d) >= 1 else None
        by_model_summary[model] = {
            "five_hour_sum": five_h_net,
            "seven_day_sum": seven_d_net,
        }

    summary_data = {
        "summary_text": summary_str,
        "by_model": by_model_summary,
    }

    return summary_data, summary_str


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else list(argv)
    dryrun = "--dryrun" in args
    if dryrun:
        args = [a for a in args if a != "--dryrun"]

    if len(args) != 2:
        print("Usage: log-cost-summary.py [--dryrun] <repo-path> <issue-N|autofix-N>", file=sys.stderr)
        return 1

    repo = Path(args[0]).resolve()
    try:
        path = find_stats_file(repo, args[1])
    except (ValueError, FileNotFoundError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        print(f"ERROR: {path} 객체 아님", file=sys.stderr)
        return 1

    cost_summary_data, summary_str = compute_cost_summary(data.get("cost_details", []))

    prefix = "[dryrun] " if dryrun else ""
    if not dryrun:
        data["cost_summary"] = cost_summary_data
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"{prefix}{summary_str}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
