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
from lib.stream_writer import StreamWriter, Surface


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
    hours: int,
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
    window_hours: int,
) -> dict[str, Any]:
    seen_surfaces = {str(event.get("surface")) for event in window_events if event.get("surface")}
    all_surfaces = [surface.value for surface in Surface]
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
    window_hours: int = 168,
    digest_hours: int = 12,
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

    return {
        "generated_at": now.isoformat().replace("+00:00", "Z"),
        "digest_window_hours": digest_hours,
        "counts": counts,
        "digest_inclusion": compute_digest_inclusion(digest_events, digest_text),
        "gaps": compute_gaps(window_events, events, now, window_hours),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit stream coverage and digest inclusion")
    parser.add_argument("--hours", type=int, default=168, help="Coverage window in hours")
    parser.add_argument("--digest-hours", type=int, default=12, help="Digest window in hours")
    parser.add_argument("--format", choices=["json", "text"], default="json")
    parser.add_argument("--output", type=Path, help="Write audit report to a file")

    args = parser.parse_args()

    events = StreamWriter().query(hours=args.hours, include_distilled=True)
    if os.environ.get("STREAM_AUDIT_NOW") and not os.environ.get("HOT_DIGEST_NOW"):
        os.environ["HOT_DIGEST_NOW"] = os.environ["STREAM_AUDIT_NOW"]
    digest_text = build_digest(hours=args.digest_hours, max_tokens=3000, use_ollama=False)

    report = audit_stream(
        events=events,
        digest_text=digest_text,
        window_hours=args.hours,
        digest_hours=args.digest_hours,
    )

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
        if digest["rate"] is not None:
            rate_pct = round(digest["rate"] * 100, 1)
            print(f"Digest inclusion rate: {rate_pct}% ({digest['included']}/{digest['eligible']})")
        else:
            print("Digest inclusion rate: n/a")

        gaps = report["gaps"]
        if gaps["missing_surfaces"]:
            print(f"Missing surfaces: {', '.join(gaps['missing_surfaces'])}")
        if gaps["handoff_stale"]:
            print("Handoff events are stale or missing")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
