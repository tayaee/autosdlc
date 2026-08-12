"""cost_entry — cost_details 항목 스키마(Pydantic)와 agent-stats.json append 공통 로직.

issue-57: 단계별 5h/7d 쿼터 계측 + reason 필드 + 단일 log-cost.py 통합
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import urllib.request
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
    script_id: str
    model: str
    reasoning_effort: str | None = "medium"
    bucket: str | None = None
    reason: str | None = None
    five_hour_used_pct: float | None = None
    seven_day_used_pct: float | None = None
    ts_description: str


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
    script_id: str,
    model: str,
    ts_description: str,
    reasoning_effort: str | None = "medium",
    bucket: str | None = None,
    reason: str | None = None,
    five_hour_used_pct: float | None = None,
    seven_day_used_pct: float | None = None,
    dryrun: bool = False,
) -> tuple[Path, CostDetailEntry]:
    entry = CostDetailEntry(
        ts=now_iso8601(),
        script_id=script_id,
        model=model,
        reasoning_effort=reasoning_effort or "medium",
        bucket=bucket,
        reason=reason,
        five_hour_used_pct=five_hour_used_pct,
        seven_day_used_pct=seven_day_used_pct,
        ts_description=ts_description,
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


def _query_antigravity_data() -> dict | None:
    """Fetch raw JSON data from agy service / cache."""
    now = time.time()
    cache_path = Path.home() / ".cache/antigravity/usage.json"
    cache_exists = cache_path.is_file()

    if not cache_exists or (now - cache_path.stat().st_mtime) > 60:
        fetched = False
        ports = []
        try:
            for name in os.listdir("/proc"):
                if name.isdigit():
                    try:
                        with open(f"/proc/{name}/comm") as f:
                            comm = f.read().strip()
                        if comm == "agy":
                            fd_dir = f"/proc/{name}/fd"
                            for fd in os.listdir(fd_dir):
                                try:
                                    link = os.readlink(f"{fd_dir}/{fd}")
                                    m = re.match(r"socket:\[(\d+)\]", link)
                                    if m:
                                        with open("/proc/net/tcp") as tcp_f:
                                            next(tcp_f)
                                            for line in tcp_f:
                                                parts = line.strip().split()
                                                if len(parts) >= 10 and parts[9] == m.group(1) and parts[3] == "0A":
                                                    ports.append(int(parts[1].split(":")[1], 16))
                                except Exception:  # noqa: BLE001, S110
                                    pass
                    except Exception:  # noqa: BLE001, S110
                        pass
        except Exception:  # noqa: BLE001, S110
            pass

        for port in sorted(list(set(ports))):
            url = f"http://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
            req = urllib.request.Request(
                url, data=b"{}", headers={"Content-Type": "application/json"}, method="POST"
            )
            try:
                with urllib.request.urlopen(req, timeout=2) as r:
                    if r.status == 200:
                        data = json.loads(r.read())
                        groups = data.get("response", {}).get("groups", [])
                        if any(any(b.get("window") == "5h" for b in g.get("buckets", [])) for g in groups):
                            cache_path.parent.mkdir(parents=True, exist_ok=True)
                            cache_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                            fetched = True
                            break
            except Exception:  # noqa: BLE001, S110
                pass

        if not fetched and cache_exists and (now - cache_path.stat().st_mtime) > 3600:
            return None

    if cache_path.is_file():
        try:
            return json.loads(cache_path.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001, S110
            pass
    return None


def query_antigravity_group(group_type: str) -> tuple[float | None, float | None]:
    data = _query_antigravity_data()
    if not data or not isinstance(data, dict):
        return None, None
    groups = data.get("response", {}).get("groups", [])
    group = None
    if group_type == "claude":
        group = next((g for g in groups if "Claude" in g.get("displayName", "") or "3p" in g.get("displayName", "").lower()), None)
    elif group_type == "gemini":
        group = next((g for g in groups if "Gemini" in g.get("displayName", "")), None)

    if not group and groups:
        group = groups[0]
    if not group:
        return None, None

    five_h_pct = None
    weekly_pct = None
    for bucket in group.get("buckets", []):
        window = bucket.get("window", "")
        rem_frac = bucket.get("remainingFraction", 1.0)
        pct = round((1.0 - rem_frac) * 100.0, 1)
        if window == "5h":
            five_h_pct = pct
        elif window == "weekly":
            weekly_pct = pct
    return five_h_pct, weekly_pct


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
    script_id: str,
    model: str,
) -> tuple[float | None, float | None, str | None, str | None]:
    """check-usage.js, agy language server, mmx, usage-*.py를 통한 used_pct 조회.

    Returns:
        (five_hour_pct, seven_day_pct, bucket, reason)
    """
    script_lower = script_id.lower()
    model_lower = model.lower()

    # 1. Antigravity Gemini / Claude bucket lookup
    if "claude-via-gemini" in script_lower or "claude-via-gemini" in model_lower:
        five_h, seven_d = query_antigravity_group("claude")
        if five_h is not None:
            return five_h, seven_d, "claude", None
        five_h, seven_d = query_antigravity_group("gemini")
        if five_h is not None:
            return five_h, seven_d, "gemini", None

    if "gemini" in script_lower or "gemini" in model_lower:
        five_h, seven_d = query_antigravity_group("gemini")
        if five_h is not None:
            return five_h, seven_d, "gemini", None

    if "antigravity-claude" in script_lower or "antigravity" in script_lower:
        five_h, seven_d = query_antigravity_group("claude")
        if five_h is not None:
            return five_h, seven_d, "claude", None

    # 2. MiniMax direct quota lookup
    if "minimax" in script_lower or "minimax" in model_lower:
        five_h, seven_d = _query_minimax_usage()
        if five_h is not None:
            return five_h, seven_d, "minimax", None

    # 3. Claude Code direct lookup (Antigravity -> claude_usage -> check-usage.js)
    if script_lower in ("sonnet", "haiku", "opus", "claude") or "claude" in model_lower:
        five_h, seven_d = query_antigravity_group("claude")
        if five_h is not None:
            return five_h, seven_d, "claude", None
        five_h, seven_d = _query_claude_usage()
        if five_h is not None:
            return five_h, seven_d, "claude", None

    # 4. Check claude-dashboard check-usage.js fallback
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
        if script_lower in ("sonnet", "haiku", "opus", "claude") or "claude" in model_lower:
            claude_entry = payload.get("claude")
            if claude_entry and isinstance(claude_entry, dict) and claude_entry.get("available") and not claude_entry.get("error"):
                five_h = claude_entry.get("fiveHourPercent")
                if five_h is not None:
                    return five_h, claude_entry.get("sevenDayPercent"), "claude", None

        if script_lower in payload:
            entry = payload[script_lower]
            if isinstance(entry, dict) and entry.get("available") and not entry.get("error"):
                return entry.get("fiveHourPercent"), entry.get("sevenDayPercent"), script_lower, None

    if "minimax" in script_lower or "minimax" in model_lower:
        return None, None, "minimax", "lookup_failed"

    return None, None, None, "unsupported_provider"
