"""cost_entry — cost_details 항목 스키마(Pydantic)와 agent-stats.json append 공통 로직.

issue-57: 단계별 5h/7d 쿼터 계측 + reason 필드 + 단일 log-cost.py 통합
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Literal

from pydantic import BaseModel

STREAM_RE = re.compile(r"^(issue|autofix)-([0-9]+)$")

ReasonType = Literal[
    "unsupported_provider",
    "lookup_unavailable",
    "lookup_failed",
    "api_error",
] | None


class CostDetailEntry(BaseModel):
    ts: str
    coder: str
    model: str
    reasoning_effort: str | None = None
    bucket: str | None = None
    reason: str | None = None
    five_hour_used_pct: float | None = None
    seven_day_used_pct: float | None = None
    description: str


def parse_stream_id(value: str) -> tuple[str, str]:
    m = STREAM_RE.match(value)
    if not m:
        raise ValueError(f"스트림 ID 형식이 아님: {value!r} (issue-N 또는 autofix-N)")
    return m.group(1), m.group(2)


def now_iso8601() -> str:
    """로컬 타임존 오프셋 포함 ISO 8601 — UTC `Z` 금지(agent-stats.json 전체 규약)."""
    return datetime.now().astimezone().isoformat(timespec="seconds")


def append_cost_detail(
    repo: Path,
    target: str,
    *,
    coder: str,
    model: str,
    description: str,
    reasoning_effort: str | None = None,
    bucket: str | None = None,
    reason: str | None = None,
    five_hour_used_pct: float | None = None,
    seven_day_used_pct: float | None = None,
    dryrun: bool = False,
) -> tuple[Path, CostDetailEntry]:
    entry = CostDetailEntry(
        ts=now_iso8601(),
        coder=coder,
        model=model,
        reasoning_effort=reasoning_effort,
        bucket=bucket,
        reason=reason,
        five_hour_used_pct=five_hour_used_pct,
        seven_day_used_pct=seven_day_used_pct,
        description=description,
    )

    stream, n = parse_stream_id(target)
    path = repo / "issues" / f"{stream}-{n}__agent-stats.json"

    if dryrun:
        return path, entry

    if not path.is_file():
        raise FileNotFoundError(f"{path} 없음")

    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path} 객체 아님")  # noqa: TRY004

    cost_details = data.setdefault("cost_details", [])
    cost_details.append(entry.model_dump())

    # 50개 초과 시 FIFO drop
    if len(cost_details) > 50:
        data["cost_details"] = cost_details[-50:]

    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path, entry


def _find_check_usage_js() -> Path | None:
    cache_root = Path.home() / ".claude/plugins/cache/claude-dashboard/claude-dashboard"
    if not cache_root.is_dir():
        return None
    versions = sorted(cache_root.glob("*/dist/check-usage.js"))
    return versions[-1] if versions else None


def query_check_usage_pct(
    coder: str,
    model: str,
) -> tuple[float | None, float | None, str | None, str | None]:
    """claude-dashboard의 check-usage.js --json을 호출해 provider/bucket의 used_pct를 얻는다.

    Returns:
        (five_hour_pct, seven_day_pct, bucket, reason)
    """
    script = _find_check_usage_js()
    if script is None:
        if os.environ.get("AACP_VERBOSE", "0") == "1":
            print("WARN: claude-dashboard check-usage.js 없음 — used_pct 조회 불가", file=sys.stderr)
        return None, None, None, "lookup_unavailable"

    try:
        result = subprocess.run(
            ["node", str(script), "--json"],
            capture_output=True, text=True, timeout=15, check=False,
        )
        if result.returncode != 0:
            if os.environ.get("AACP_VERBOSE", "0") == "1":
                print(f"WARN: check-usage node 실행 실패 (rc={result.returncode})", file=sys.stderr)
            return None, None, None, "lookup_failed"
        payload = json.loads(result.stdout)
    except Exception as exc:  # noqa: BLE001
        if os.environ.get("AACP_VERBOSE", "0") == "1":
            print(f"WARN: check-usage 조회 실패 ({exc}) — used_pct 조회 불가", file=sys.stderr)
        return None, None, None, "lookup_failed"

    # Match provider key from coder/model
    coder_lower = coder.lower()

    if coder_lower in ("sonnet", "haiku", "opus", "claude"):
        claude_entry = payload.get("claude")
        if claude_entry and isinstance(claude_entry, dict) and claude_entry.get("available") and not claude_entry.get("error"):
            return claude_entry.get("fiveHourPercent"), claude_entry.get("sevenDayPercent"), "claude", None
        return None, None, "claude", "api_error"

    if coder_lower == "gemini":
        gemini_entry = payload.get("gemini")
        if not gemini_entry or not isinstance(gemini_entry, dict) or not gemini_entry.get("available") or gemini_entry.get("error"):
            return None, None, "gemini", "api_error"
        if gemini_entry.get("buckets"):
            for b in gemini_entry["buckets"]:
                if isinstance(b, dict) and "gemini" in str(b.get("modelId", "")).lower():
                    return b.get("usedPercent"), None, "gemini", None
        return gemini_entry.get("fiveHourPercent"), gemini_entry.get("sevenDayPercent"), "gemini", None

    if coder_lower == "claude-via-gemini":
        gemini_entry = payload.get("gemini")
        if gemini_entry and isinstance(gemini_entry, dict) and gemini_entry.get("buckets"):
            for b in gemini_entry["buckets"]:
                if isinstance(b, dict) and "claude" in str(b.get("modelId", "")).lower():
                    return b.get("usedPercent"), None, "claude-via-gemini", None
        claude_entry = payload.get("claude")
        if claude_entry and isinstance(claude_entry, dict) and claude_entry.get("available") and not claude_entry.get("error"):
            return claude_entry.get("fiveHourPercent"), claude_entry.get("sevenDayPercent"), "claude-via-gemini", None
        return None, None, "claude-via-gemini", "api_error"

    if coder_lower in payload:
        entry = payload[coder_lower]
        if isinstance(entry, dict) and entry.get("available") and not entry.get("error"):
            return entry.get("fiveHourPercent"), entry.get("sevenDayPercent"), coder_lower, None
        return None, None, coder_lower, "api_error"

    # Provider not supported by check-usage
    return None, None, None, "unsupported_provider"
