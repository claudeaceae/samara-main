"""Test suite for stream validator."""
from __future__ import annotations

import json
from pathlib import Path

from lib.stream_validator import validate_event, validate_stream_file
from lib.stream_writer import StreamWriter, EventType, Direction, Surface


def test_validate_event_accepts_valid():
    event = {
        "schema_version": "1",
        "id": "evt_123_abc",
        "timestamp": "2026-01-18T12:00:00Z",
        "surface": "cli",
        "type": "interaction",
        "direction": "inbound",
        "summary": "Test",
        "distilled": False,
        "metadata": {},
    }

    errors = validate_event(event)
    assert errors == []


def test_validate_event_detects_errors():
    event = {
        "schema_version": 2,
        "id": 123,
        "timestamp": "not-a-date",
        "surface": "unknown",
        "type": "bad",
        "direction": "sideways",
        "summary": 4,
        "distilled": "no",
    }

    errors = validate_event(event)
    assert errors
    assert any("schema_version" in err for err in errors)
    assert any("invalid surface" in err for err in errors)
    assert any("invalid type" in err for err in errors)
    assert any("invalid direction" in err for err in errors)


def test_validate_stream_file_reports_invalid_lines(tmp_path: Path):
    stream_dir = tmp_path / "stream"
    stream_dir.mkdir()
    stream_file = stream_dir / "events.jsonl"

    writer = StreamWriter(stream_dir=stream_dir)
    event = writer.create_event(
        surface=Surface.CLI,
        event_type=EventType.INTERACTION,
        direction=Direction.INBOUND,
        summary="Valid event",
    )
    writer.write(event)

    with stream_file.open("a", encoding="utf-8") as handle:
        handle.write("{invalid json}\n")
        handle.write(json.dumps({"id": "evt_missing_fields"}) + "\n")

    errors, total = validate_stream_file(stream_file)

    assert total == 3
    assert len(errors) == 2
    assert errors[0]["line"] == 2
