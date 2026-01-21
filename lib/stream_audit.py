#!/usr/bin/env python3
"""
Stream Audit

Compute coverage and digest inclusion metrics for the unified event stream.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

# Add parent dir to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.hot_digest_builder import build_digest
from lib.mind_paths import get_mind_path
from lib.stream_writer import StreamWriter, Surface

SERVICE_SURFACE_MAP = {
    "x": ["x"],
    "bluesky": ["bluesky"],
    "webhook": ["webhook"],
    "location": ["location"],
    "meeting": ["calendar"],
}


def load_config() -> dict[str, Any]:
    """Load config.json from the mind path."""
    config_path = get_mind_path() / "config.json"
    if not config_path.exists():
        return {}
    try:
        data = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def load_stream_config(config: dict[str, Any]) -> dict[str, Any]:
    """Load stream config section."""
    stream_config = config.get("stream")
    if not isinstance(stream_config, dict):
        return {}
    return stream_config


def coerce_float(value: Any) -> Optional[float]:
    """Coerce a value to float if possible."""
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def normalize_surface_list(value: Any) -> list[str]:
    """Normalize a surface list to strings."""
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str) and item]


def resolve_expected_surfaces(
    stream_config: dict[str, Any],
    allowed_surfaces: Optional[set[str]] = None,
) -> tuple[set[str], str]:
    """Return (expected_surfaces, source)."""
    audit_config = stream_config.get("audit") if isinstance(stream_config, dict) else None
    raw_expected = None
    if isinstance(audit_config, dict):
        raw_expected = normalize_surface_list(audit_config.get("expected_surfaces"))

    source = "defaults"
    expected = set(raw_expected) if raw_expected else {surface.value for surface in Surface}
    if raw_expected:
        source = "config"

    if allowed_surfaces is not None:
        expected = {surface for surface in expected if surface in allowed_surfaces}
    return expected, source


def parse_timestamp(value: str) -> Optional[datetime]:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def get_now() -> datetime:
    override = os.environ.get("STREAM_AUDIT_NOW")
    if override:
        try:
            return datetime.fromisoformat(override.replace("Z", "+00:00"))
        except ValueError:
            return datetime.now(timezone.utc)
    return datetime.now(timezone.utc)


def filter_events_by_hours(
    events: list[dict[str, Any]],
    hours: float,
    now: datetime,
) -> list[dict[str, Any]]:
    cutoff = now - timedelta(hours=hours)
    filtered: list[dict[str, Any]] = []
    for event in events:
        ts = parse_timestamp(str(event.get("timestamp", "")))
        if ts and ts >= cutoff:
            filtered.append(event)
    return filtered


def count_by_field(events: list[dict[str, Any]], field: str) -> dict[str, int]:
    counts: dict[str, int] = defaultdict(int)
    for event in events:
        value = event.get(field)
        if value is None:
            continue
        counts[str(value)] += 1
    return dict(counts)


def summary_in_digest(summary: str, digest: str) -> bool:
    if not summary or not digest:
        return False
    return summary.lower() in digest.lower()


def compute_digest_inclusion(
    events: list[dict[str, Any]],
    digest: str,
) -> dict[str, Any]:
    eligible = [event for event in events if event.get("summary")]
    included = [event for event in eligible if summary_in_digest(str(event["summary"]), digest)]

    total_eligible = len(eligible)
    total_included = len(included)
    total_rate = (total_included / total_eligible) if total_eligible else None

    by_surface: dict[str, dict[str, Any]] = {}
    for surface in {str(event.get("surface")) for event in eligible if event.get("surface")}:
        surface_events = [e for e in eligible if str(e.get("surface")) == surface]
        surface_included = [e for e in included if str(e.get("surface")) == surface]
        eligible_count = len(surface_events)
        included_count = len(surface_included)
        by_surface[surface] = {
            "eligible": eligible_count,
            "included": included_count,
            "rate": (included_count / eligible_count) if eligible_count else None,
        }

    return {
        "total": {
            "eligible": total_eligible,
            "included": total_included,
            "rate": total_rate,
        },
        "by_surface": by_surface,
    }


def compute_gaps(
    window_events: list[dict[str, Any]],
    all_events: list[dict[str, Any]],
    now: datetime,
    window_hours: float,
    expected_surfaces: Optional[set[str]] = None,
) -> dict[str, Any]:
    seen_surfaces = {str(event.get("surface")) for event in window_events if event.get("surface")}
    all_surfaces = expected_surfaces or {surface.value for surface in Surface}
    missing_surfaces = sorted([surface for surface in all_surfaces if surface not in seen_surfaces])

    handoff_events = [
        event for event in all_events
        if str(event.get("type")) == "handoff" and event.get("timestamp")
    ]
    handoff_times = [parse_timestamp(str(event["timestamp"])) for event in handoff_events]
    handoff_times = [ts for ts in handoff_times if ts is not None]
    last_handoff = max(handoff_times) if handoff_times else None
    handoff_age_hours = None
    if last_handoff:
        handoff_age_hours = (now - last_handoff).total_seconds() / 3600
    handoff_stale = last_handoff is None or (
        handoff_age_hours is not None and handoff_age_hours > window_hours
    )

    return {
        "missing_surfaces": missing_surfaces,
        "handoff_stale": handoff_stale,
        "handoff_last_seen": last_handoff.isoformat().replace("+00:00", "Z")
        if last_handoff
        else None,
    }


def audit_stream(
    events: list[dict[str, Any]],
    digest_text: str,
    now: Optional[datetime] = None,
    window_hours: float = 168,
    digest_hours: float = 12,
    expected_surfaces: Optional[set[str]] = None,
    expected_source: Optional[str] = None,
) -> dict[str, Any]:
    now = now or get_now()
    window_events = filter_events_by_hours(events, window_hours, now)
    digest_events = filter_events_by_hours(events, digest_hours, now)

    counts = {
        "window_hours": window_hours,
        "total_events": len(window_events),
        "by_surface": count_by_field(window_events, "surface"),
        "by_type": count_by_field(window_events, "type"),
        "by_direction": count_by_field(window_events, "direction"),
        "undistilled_total": len([e for e in events if not e.get("distilled", False)]),
    }

    report = {
        "generated_at": now.isoformat().replace("+00:00", "Z"),
        "digest_window_hours": digest_hours,
        "counts": counts,
        "digest_inclusion": compute_digest_inclusion(digest_events, digest_text),
        "gaps": compute_gaps(window_events, events, now, window_hours, expected_surfaces),
    }

    if expected_surfaces is not None:
        report["surface_expectations"] = {
            "expected_surfaces": sorted(expected_surfaces),
            "source": expected_source or "defaults",
        }

    return report


def load_service_config(config: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    """Load services config from config.json."""
    if config is None:
        config = load_config()
    services = config.get("services") if isinstance(config, dict) else None
    if not isinstance(services, dict):
        return {}
    return services


def resolve_allowed_surfaces(config: Optional[dict[str, Any]] = None) -> tuple[Optional[set[str]], list[str]]:
    """Return (allowed_surfaces, disabled_services)."""
    services = load_service_config(config)
    if not services:
        return None, []

    disabled_services = [
        name for name, value in services.items()
        if value is False
    ]
    if not disabled_services:
        return None, []

    disabled_surfaces: set[str] = set()
    for service in disabled_services:
        for surface in SERVICE_SURFACE_MAP.get(service, []):
            disabled_surfaces.add(surface)

    all_surfaces = {surface.value for surface in Surface}
    allowed_surfaces = {surface for surface in all_surfaces if surface not in disabled_surfaces}

    return allowed_surfaces, disabled_services


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit stream coverage and digest inclusion")
    parser.add_argument("--hours", type=float, default=None, help="Coverage window in hours")
    parser.add_argument(
        "--digest-hours",
        default=None,
        help="Digest window in hours or 'auto' for adaptive windowing",
    )
    parser.add_argument("--format", choices=["json", "text"], default="json")
    parser.add_argument("--output", type=Path, help="Write audit report to a file")

    args = parser.parse_args()

    config = load_config()
    stream_config = load_stream_config(config)
    audit_config = stream_config.get("audit") if isinstance(stream_config, dict) else {}
    hot_digest_config = stream_config.get("hot_digest") if isinstance(stream_config, dict) else {}

    window_hours = coerce_float(args.hours)
    if window_hours is None:
        window_hours = coerce_float(audit_config.get("window_hours")) or 168.0

    digest_hours_setting: Any = args.digest_hours if args.digest_hours is not None else audit_config.get("digest_hours")
    if digest_hours_setting is None:
        digest_hours_setting = "12"

    digest_hours_arg: int | float | str
    if isinstance(digest_hours_setting, str) and digest_hours_setting.lower() == "auto":
        digest_hours_arg = "auto"
    else:
        digest_hours_arg = coerce_float(digest_hours_setting) or 12.0

    auto_min_hours = coerce_float(hot_digest_config.get("min_hours")) or 2.0
    auto_max_hours = coerce_float(hot_digest_config.get("max_hours")) or 24.0
    auto_base_hours = coerce_float(hot_digest_config.get("base_hours")) or 12.0
    auto_target_rate = coerce_float(hot_digest_config.get("target_rate")) or 10.0

    events = StreamWriter().query(hours=window_hours, include_distilled=True)
    if os.environ.get("STREAM_AUDIT_NOW") and not os.environ.get("HOT_DIGEST_NOW"):
        os.environ["HOT_DIGEST_NOW"] = os.environ["STREAM_AUDIT_NOW"]

    digest_text, digest_metadata = build_digest(
        hours=digest_hours_arg,
        max_tokens=3000,
        use_ollama=False,
        auto_min_hours=auto_min_hours,
        auto_max_hours=auto_max_hours,
        auto_base_hours=auto_base_hours,
        auto_target_rate=auto_target_rate,
        return_metadata=True,
    )

    digest_window_hours = coerce_float(digest_metadata.get("window_hours")) or (
        coerce_float(digest_hours_arg) or 12.0
    )

    allowed_surfaces, disabled_services = resolve_allowed_surfaces(config)
    expected_surfaces, expected_source = resolve_expected_surfaces(stream_config, allowed_surfaces)

    report = audit_stream(
        events=events,
        digest_text=digest_text,
        window_hours=window_hours,
        digest_hours=digest_window_hours,
        expected_surfaces=expected_surfaces,
        expected_source=expected_source,
    )
    report["hot_digest"] = {
        "requested_hours": digest_hours_setting,
        "resolved_hours": digest_window_hours,
        "metrics": digest_metadata.get("metrics"),
        "auto_config": {
            "min_hours": auto_min_hours,
            "max_hours": auto_max_hours,
            "base_hours": auto_base_hours,
            "target_rate": auto_target_rate,
        },
    }
    if allowed_surfaces is not None:
        report["enabled_surfaces"] = sorted(allowed_surfaces)
    if disabled_services:
        report["disabled_services"] = disabled_services

    if args.output:
        try:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        except OSError:
            pass

    if args.format == "json":
        print(json.dumps(report, indent=2))
    else:
        counts = report["counts"]
        digest = report["digest_inclusion"]["total"]
        print(f"Stream audit ({counts['window_hours']}h window)")
        print(f"Total events: {counts['total_events']}")
        print(f"Undistilled total: {counts['undistilled_total']}")
        digest_info = report.get("hot_digest", {})
        resolved_hours = digest_info.get("resolved_hours")
        if resolved_hours is not None:
            print(f"Hot digest window: {resolved_hours}h")
        if digest["rate"] is not None:
            rate_pct = round(digest["rate"] * 100, 1)
            print(f"Digest inclusion rate: {rate_pct}% ({digest['included']}/{digest['eligible']})")
        else:
            print("Digest inclusion rate: n/a")

        gaps = report["gaps"]
        surface_expectations = report.get("surface_expectations", {})
        expected = surface_expectations.get("expected_surfaces")
        if expected:
            print(f"Expected surfaces: {', '.join(expected)}")
        if gaps["missing_surfaces"]:
            print(f"Missing surfaces: {', '.join(gaps['missing_surfaces'])}")
        if gaps["handoff_stale"]:
            print("Handoff events are stale or missing")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
