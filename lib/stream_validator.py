"""Unified Event Stream Validator.

Validates event schema and enumerations for the unified stream.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Any

from lib.stream_writer import Direction, EventType, Surface


REQUIRED_FIELDS: dict[str, type] = {
    "schema_version": str,
    "id": str,
    "timestamp": str,
    "surface": str,
    "type": str,
    "direction": str,
    "summary": str,
    "distilled": bool,
}

OPTIONAL_FIELDS: dict[str, type] = {
    "session_id": str,
    "content": str,
    "metadata": dict,
}


def validate_event(event: dict[str, Any]) -> list[str]:
    """Return a list of schema validation errors for a single event."""
    errors: list[str] = []

    for field, expected_type in REQUIRED_FIELDS.items():
        if field not in event:
            errors.append(f"missing field: {field}")
            continue
        value = event[field]
        if not isinstance(value, expected_type):
            errors.append(
                f"invalid type for {field}: expected {expected_type.__name__}, got {type(value).__name__}"
            )

    # Validate enums
    surface = event.get("surface")
    if isinstance(surface, str) and surface not in {s.value for s in Surface}:
        errors.append(f"invalid surface: {surface}")

    event_type = event.get("type")
    if isinstance(event_type, str) and event_type not in {t.value for t in EventType}:
        errors.append(f"invalid type: {event_type}")

    direction = event.get("direction")
    if isinstance(direction, str) and direction not in {d.value for d in Direction}:
        errors.append(f"invalid direction: {direction}")

    # Validate timestamp format
    timestamp = event.get("timestamp")
    if isinstance(timestamp, str):
        try:
            datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        except ValueError:
            errors.append("invalid timestamp format")

    # Validate optional fields
    for field, expected_type in OPTIONAL_FIELDS.items():
        if field not in event:
            continue
        value = event[field]
        if value is None:
            continue
        if not isinstance(value, expected_type):
            errors.append(
                f"invalid type for {field}: expected {expected_type.__name__}, got {type(value).__name__}"
            )

    return errors


def validate_stream_file(stream_file: Path) -> tuple[list[dict[str, Any]], int]:
    """Validate a JSONL stream file, returning (errors, total_events)."""
    errors: list[dict[str, Any]] = []
    total = 0

    if not stream_file.exists():
        return errors, total

    with stream_file.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            total += 1
            try:
                event = __import__("json").loads(line)
            except ValueError as exc:
                errors.append(
                    {
                        "line": line_number,
                        "error": f"invalid json: {exc}",
                    }
                )
                continue

            issues = validate_event(event)
            if issues:
                errors.append(
                    {
                        "line": line_number,
                        "id": event.get("id"),
                        "errors": issues,
                    }
                )

    return errors, total
