#!/usr/bin/env python3
"""
Stream Distill

Convert undistilled stream events into a compact narrative summary.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SURFACE_LABELS = {
    "imessage": "iMessage",
    "cli": "CLI",
    "wake": "Wake",
    "dream": "Dream",
    "webhook": "Webhook",
    "x": "X",
    "bluesky": "Bluesky",
    "email": "Email",
    "calendar": "Calendar",
    "location": "Location",
    "sense": "Sense",
    "system": "System",
}


def clean_text(text: str) -> str:
    """Normalize whitespace and trim trailing punctuation."""
    cleaned = " ".join(text.strip().split())
    return cleaned.rstrip(".")


def event_summary(event: dict[str, Any]) -> str:
    """Select the best available summary text for an event."""
    summary = event.get("summary") or ""
    summary = clean_text(str(summary)) if summary else ""
    if summary:
        return summary

    content = event.get("content") or ""
    content = clean_text(str(content)) if content else ""
    return content


def sort_events(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Sort by timestamp (ascending), then ID for stability."""
    return sorted(
        events,
        key=lambda e: (e.get("timestamp", ""), e.get("id", "")),
    )


def build_narrative(events: list[dict[str, Any]], max_per_surface: int = 3) -> str:
    """Build a compact narrative from undistilled events."""
    if not events:
        return ""

    ordered_events = sort_events(events)
    surface_order: list[str] = []
    grouped: dict[str, list[str]] = {}

    for event in ordered_events:
        surface = str(event.get("surface") or "unknown").strip().lower()
        summary = event_summary(event)
        if not summary:
            continue

        if surface not in grouped:
            grouped[surface] = []
            surface_order.append(surface)

        if len(grouped[surface]) < max_per_surface:
            grouped[surface].append(summary)

    paragraphs: list[str] = []
    for surface in surface_order:
        summaries = grouped.get(surface, [])
        if not summaries:
            continue
        label = SURFACE_LABELS.get(surface, surface.capitalize())
        paragraphs.append(f"{label} activity: " + "; ".join(summaries) + ".")

    return "\n\n".join(paragraphs)


def load_events_from_json(raw: str) -> list[dict[str, Any]]:
    """Parse events from JSON text, returning a list."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []

    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]

    return []


def main() -> int:
    parser = argparse.ArgumentParser(description="Build narrative summary from stream events")
    parser.add_argument(
        "--input",
        type=Path,
        help="Path to JSON events (defaults to stdin)",
    )
    parser.add_argument("--max-per-surface", type=int, default=3)
    parser.add_argument("--format", choices=["text", "json"], default="text")

    args = parser.parse_args()

    if args.input:
        try:
            raw = args.input.read_text(encoding="utf-8")
        except OSError:
            raw = ""
    else:
        raw = sys.stdin.read()

    events = load_events_from_json(raw)
    narrative = build_narrative(events, max_per_surface=args.max_per_surface)

    if args.format == "json":
        print(json.dumps({"narrative": narrative, "event_count": len(events)}))
    else:
        print(narrative)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
