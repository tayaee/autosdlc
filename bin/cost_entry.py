"""cost_entry — cost_details 항목 스키마(Pydantic)와 agent-stats.json append 공통 로직.

issue-57: 단계별 5h/7d 쿼터 계측 + reason 필드 + 단일 log-cost.py 통합
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Literal

from pydantic import BaseModel

STREAM_RE = re.compile(r"^(issue|autofix)-([0-9]+)$")
SCRIPT_DIR = Path(__file__).resolve().parent

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
    reasoning_effort: str | None = "medium"
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
    reasoning_effort: str | None = "medium",
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
        reasoning_effort=reasoning_effort or "medium",
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


def _query_minimax_usage() -> tuple[float | None, float | None]:
    try:
        cache_path = Path.home() / ".cache/mmx/usage.json"
        now = time.time()
        if not cache_path.is_file() or (now - cache_path.stat().st_mtime) > 300:
            res = subprocess.run(
                ["mmx", "quota", "show", "--output", "json"],
                capture_output=True, text=True, timeout=10, check=False,
            )
            if res.returncode == 0 and res.stdout.strip():
                cache_path.parent.mkdir(parents=True, exist_ok=True)
                cache_path.write_text(res.stdout, encoding="utf-8")
        if cache_path.is_file():
            data = json.loads(cache_path.read_text(encoding="utf-8"))
            for m in data.get("model_remains", []):
                if m.get("model_name") == "general":
                    rem_5h = m.get("current_interval_remaining_percent", 100)
                    rem_7d = m.get("current_weekly_remaining_percent", 100)
                    return float(100 - rem_5h), float(100 - rem_7d)
    except Exception:  # noqa: BLE001, S110
        pass
    return None, None


def _query_claude_usage() -> tuple[float | None, float | None]:
    try:
        script = SCRIPT_DIR / "usage-claudecli.py"
        if script.is_file():
            res = subprocess.run(
                [sys.executable, str(script)],
                capture_output=True, text=True, timeout=10, check=False,
            )
            if res.returncode == 0 and res.stdout.strip():
                data = json.loads(res.stdout)
                if data.get("available"):
                    rem_5h = data.get("five_hour_remaining_pct")
                    rem_7d = data.get("weekly_remaining_pct")
                    if rem_5h is not None and rem_7d is not None:
                        return float(100 - rem_5h), float(100 - rem_7d)
    except Exception:  # noqa: BLE001, S110
        pass
    return None, None


def query_check_usage_pct(
    coder: str,
    model: str,
) -> tuple[float | None, float | None, str | None, str | None]:
    """check-usage.js 및 프로바이더별 직접 쿼리(mmx, usage-*.py)를 통한 used_pct 조회.

    Returns:
        (five_hour_pct, seven_day_pct, bucket, reason)
    """
    coder_lower = coder.lower()
    model_lower = model.lower()

    # 1. MiniMax direct quota lookup
    if "minimax" in coder_lower or "minimax" in model_lower:
        five_h, seven_d = _query_minimax_usage()
        if five_h is not None:
            return five_h, seven_d, "minimax", None

    # 2. Check claude-dashboard check-usage.js
    script = _find_check_usage_js()
    payload = None
    if script is not None:
        try:
            result = subprocess.run(
                ["node", str(script), "--json"],
                capture_output=True, text=True, timeout=15, check=False,
            )
            if result.returncode == 0 and result.stdout.strip():
                payload = json.loads(result.stdout)
        except Exception:  # noqa: BLE001, S110
            pass

    if payload and isinstance(payload, dict):
        if coder_lower in ("sonnet", "haiku", "opus", "claude") or "claude" in model_lower:
            claude_entry = payload.get("claude")
            if claude_entry and isinstance(claude_entry, dict) and claude_entry.get("available") and not claude_entry.get("error"):
                five_h = claude_entry.get("fiveHourPercent")
                if five_h is not None:
                    return five_h, claude_entry.get("sevenDayPercent"), "claude", None

        if coder_lower == "gemini":
            gemini_entry = payload.get("gemini")
            if gemini_entry and isinstance(gemini_entry, dict) and gemini_entry.get("available") and not gemini_entry.get("error"):
                if gemini_entry.get("buckets"):
                    for b in gemini_entry["buckets"]:
                        if isinstance(b, dict) and "gemini" in str(b.get("modelId", "")).lower():
                            return b.get("usedPercent"), None, "gemini", None
                return gemini_entry.get("fiveHourPercent"), gemini_entry.get("sevenDayPercent"), "gemini", None

        if coder_lower in payload:
            entry = payload[coder_lower]
            if isinstance(entry, dict) and entry.get("available") and not entry.get("error"):
                return entry.get("fiveHourPercent"), entry.get("sevenDayPercent"), coder_lower, None

    # 3. Fallback to usage-claudecli.py for Claude models
    if coder_lower in ("sonnet", "haiku", "opus", "claude") or "claude" in model_lower or "sonnet" in model_lower:
        five_h, seven_d = _query_claude_usage()
        if five_h is not None:
            return five_h, seven_d, "claude", None
        return None, None, "claude", "api_error"

    if "minimax" in coder_lower or "minimax" in model_lower:
        return None, None, "minimax", "lookup_failed"

    return None, None, None, "unsupported_provider"
