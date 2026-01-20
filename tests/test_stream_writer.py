"""
Test suite for the unified event stream system.

Run with: pytest tests/test_stream_writer.py -v
"""
from __future__ import annotations

import json
import os
import tempfile
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import pytest

# Module under test (will be created)
from lib.stream_writer import (
    StreamWriter,
    Event,
    EventType,
    Direction,
    Surface,
)


def daily_file_for_event(stream_dir: Path, timestamp: str) -> Path:
    date_str = timestamp[:10]
    return stream_dir / "daily" / f"events-{date_str}.jsonl"


@pytest.fixture
def temp_stream_dir():
    """Create a temporary stream directory for testing."""
    with tempfile.TemporaryDirectory() as tmpdir:
        stream_dir = Path(tmpdir) / "stream"
        stream_dir.mkdir()
        (stream_dir / "archive").mkdir()
        yield stream_dir


@pytest.fixture
def writer(temp_stream_dir):
    """Create a StreamWriter instance with temp directory."""
    return StreamWriter(stream_dir=temp_stream_dir)


class TestEventCreation:
    """Tests for Event dataclass and validation."""

    def test_event_has_required_fields(self, writer):
        """Event must have id, timestamp, surface, type, direction, summary."""
        event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Test summary",
        )

        assert event.id is not None
        assert event.timestamp is not None
        assert event.schema_version == "1"
        assert event.surface == Surface.CLI
        assert event.type == EventType.INTERACTION
        assert event.direction == Direction.INBOUND
        assert event.summary == "Test summary"

    def test_event_id_is_unique(self, writer):
        """Each event gets a unique ID."""
        events = [
            writer.create_event(
                surface=Surface.CLI,
                event_type=EventType.INTERACTION,
                direction=Direction.INBOUND,
                summary=f"Event {i}",
            )
            for i in range(100)
        ]

        ids = [e.id for e in events]
        assert len(ids) == len(set(ids)), "Event IDs must be unique"

    def test_event_id_format(self, writer):
        """Event ID follows format: evt_{timestamp}_{random}."""
        event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Test",
        )

        assert event.id.startswith("evt_")
        parts = event.id.split("_")
        assert len(parts) == 3

    def test_event_timestamp_is_iso8601(self, writer):
        """Event timestamp is valid ISO 8601."""
        event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Test",
        )

        # Should parse without error
        datetime.fromisoformat(event.timestamp.replace("Z", "+00:00"))

    def test_event_optional_fields(self, writer):
        """Event can have optional session_id, content, metadata."""
        event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Test",
            session_id="test-session-123",
            content="Full content here",
            metadata={"key": "value"},
        )

        assert event.session_id == "test-session-123"
        assert event.content == "Full content here"
        assert event.metadata == {"key": "value"}


class TestStreamWriting:
    """Tests for writing events to the stream."""

    def test_write_event_creates_valid_jsonl(self, writer, temp_stream_dir):
        """Event written to stream is valid JSONL with required fields."""
        event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Test event",
        )

        writer.write(event)

        # Read and parse
        stream_file = daily_file_for_event(temp_stream_dir, event.timestamp)
        assert stream_file.exists()

        with open(stream_file) as f:
            line = f.readline()
            data = json.loads(line)

        assert data["id"] == event.id
        assert data["schema_version"] == "1"
        assert data["surface"] == "cli"
        assert data["type"] == "interaction"
        assert data["summary"] == "Test event"
        assert data["distilled"] is False

    def test_events_are_append_only(self, writer, temp_stream_dir):
        """Multiple writes append, never overwrite."""
        for i in range(5):
            event = writer.create_event(
                surface=Surface.CLI,
                event_type=EventType.INTERACTION,
                direction=Direction.INBOUND,
                summary=f"Event {i}",
            )
            writer.write(event)

        daily_files = list((temp_stream_dir / "daily").glob("events-*.jsonl"))
        assert len(daily_files) == 1
        with open(daily_files[0]) as f:
            lines = f.readlines()

        assert len(lines) == 5
        for i, line in enumerate(lines):
            data = json.loads(line)
            assert data["summary"] == f"Event {i}"

    def test_write_creates_file_if_not_exists(self, temp_stream_dir):
        """First write creates daily shard file if it doesn't exist."""
        daily_dir = temp_stream_dir / "daily"
        assert not daily_dir.exists()

        writer = StreamWriter(stream_dir=temp_stream_dir)
        event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="First event",
        )
        writer.write(event)

        stream_file = daily_file_for_event(temp_stream_dir, event.timestamp)
        assert stream_file.exists()

    def test_handles_special_characters(self, writer, temp_stream_dir):
        """Can write events with special characters, newlines, unicode."""
        event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary='Test with "quotes" and\nnewlines',
            content="Unicode: \u2603 \U0001F600",
        )
        writer.write(event)

        stream_file = daily_file_for_event(temp_stream_dir, event.timestamp)
        with open(stream_file) as f:
            data = json.loads(f.readline())

        assert "quotes" in data["summary"]
        assert "\u2603" in data["content"]


class TestStreamQuerying:
    """Tests for querying events from the stream."""

    def test_list_stream_files_across_day_boundary(self, writer, temp_stream_dir):
        """Daily shards are selected across day boundaries."""
        event1 = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Late event",
        )
        event1.timestamp = "2026-01-18T23:30:00Z"
        writer.write(event1)

        event2 = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Early event",
        )
        event2.timestamp = "2026-01-19T00:30:00Z"
        writer.write(event2)

        now = datetime(2026, 1, 19, 1, 0, 0, tzinfo=timezone.utc)
        files = writer.list_stream_files(hours=2, now=now)
        expected_files = {
            temp_stream_dir / "daily" / "events-2026-01-18.jsonl",
            temp_stream_dir / "daily" / "events-2026-01-19.jsonl",
        }
        assert expected_files.issubset(set(files))

    def test_query_by_time_range(self, writer, temp_stream_dir):
        """Can query events within a time window."""
        # Write events with different timestamps
        now = datetime.now(timezone.utc)

        # Old event (25 hours ago)
        old_event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Old event",
        )
        old_time = (now - timedelta(hours=25)).isoformat().replace("+00:00", "Z")
        old_event.timestamp = old_time
        writer.write(old_event)

        # Recent event (1 hour ago)
        recent_event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Recent event",
        )
        recent_time = (now - timedelta(hours=1)).isoformat().replace("+00:00", "Z")
        recent_event.timestamp = recent_time
        writer.write(recent_event)

        # Query last 12 hours
        results = writer.query(hours=12)

        assert len(results) == 1
        assert results[0]["summary"] == "Recent event"

    def test_query_by_surface(self, writer, temp_stream_dir):
        """Can filter events by surface type."""
        for surface in [Surface.CLI, Surface.IMESSAGE, Surface.CLI]:
            event = writer.create_event(
                surface=surface,
                event_type=EventType.INTERACTION,
                direction=Direction.INBOUND,
                summary=f"Event from {surface.value}",
            )
            writer.write(event)

        cli_events = writer.query(surface=Surface.CLI)
        assert len(cli_events) == 2

        imessage_events = writer.query(surface=Surface.IMESSAGE)
        assert len(imessage_events) == 1

    def test_query_excludes_distilled_by_default(self, writer, temp_stream_dir):
        """Query excludes distilled events unless explicitly included."""
        event1 = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Not distilled",
        )
        writer.write(event1)

        event2 = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Will be distilled",
        )
        writer.write(event2)
        writer.mark_distilled(event2.id)

        results = writer.query()
        assert len(results) == 1
        assert results[0]["summary"] == "Not distilled"

        all_results = writer.query(include_distilled=True)
        assert len(all_results) == 2
        assert any(event["distilled"] is True for event in all_results)

    def test_query_empty_stream(self, writer):
        """Query on empty stream returns empty list, not error."""
        results = writer.query()
        assert results == []


class TestDistillationMarking:
    """Tests for marking events as distilled."""

    def test_mark_distilled(self, writer, temp_stream_dir):
        """Marks events as distilled via sidecar index."""
        event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Original summary",
        )
        writer.write(event)

        writer.mark_distilled(event.id)

        # Sidecar index should include the event
        index_file = temp_stream_dir / "distilled-index.jsonl"
        assert index_file.exists()
        with open(index_file) as f:
            index_entry = json.loads(f.readline())
        assert index_entry["id"] == event.id

        # Re-read to verify stream content is unchanged
        stream_file = daily_file_for_event(temp_stream_dir, event.timestamp)
        with open(stream_file) as f:
            data = json.loads(f.readline())

        assert data["distilled"] is False
        assert data["summary"] == "Original summary"  # Content unchanged

    def test_mark_multiple_distilled(self, writer, temp_stream_dir):
        """Can mark multiple events as distilled by ID list."""
        events = []
        for i in range(5):
            event = writer.create_event(
                surface=Surface.CLI,
                event_type=EventType.INTERACTION,
                direction=Direction.INBOUND,
                summary=f"Event {i}",
            )
            writer.write(event)
            events.append(event)

        # Mark first 3 as distilled
        writer.mark_distilled([e.id for e in events[:3]])

        results = writer.query(include_distilled=False)
        assert len(results) == 2

        index_file = temp_stream_dir / "distilled-index.jsonl"
        with open(index_file) as f:
            index_lines = [json.loads(line) for line in f if line.strip()]
        assert len(index_lines) == 3


class TestArchiving:
    """Tests for archiving old events."""

    def test_archive_moves_old_events(self, writer, temp_stream_dir):
        """Events older than threshold get moved to archive/."""
        now = datetime.now(timezone.utc)

        # Old event (35 days ago)
        old_event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Old event",
        )
        old_time = (now - timedelta(days=35)).isoformat().replace("+00:00", "Z")
        old_event.timestamp = old_time
        writer.write(old_event)

        # Recent event
        recent_event = writer.create_event(
            surface=Surface.CLI,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary="Recent event",
        )
        writer.write(recent_event)

        # Archive events older than 30 days
        archived_count = writer.archive(days_old=30)

        assert archived_count == 1

        # Check main stream only has recent event
        results = writer.query(include_distilled=True)
        assert len(results) == 1
        assert results[0]["summary"] == "Recent event"

        # Check archive has old event
        archive_files = list((temp_stream_dir / "archive").glob("*.jsonl"))
        assert len(archive_files) >= 1


class TestConcurrency:
    """Tests for concurrent write safety."""

    def test_concurrent_writes_are_safe(self, temp_stream_dir):
        """Multiple processes can write simultaneously without corruption."""
        writer = StreamWriter(stream_dir=temp_stream_dir)
        errors = []

        def write_events(thread_id: int, count: int):
            try:
                for i in range(count):
                    event = writer.create_event(
                        surface=Surface.CLI,
                        event_type=EventType.INTERACTION,
                        direction=Direction.INBOUND,
                        summary=f"Thread {thread_id} Event {i}",
                    )
                    writer.write(event)
            except Exception as e:
                errors.append(e)

        threads = [
            threading.Thread(target=write_events, args=(i, 20))
            for i in range(5)
        ]

        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert not errors, f"Errors during concurrent write: {errors}"

        # Verify all events were written
        daily_files = list((temp_stream_dir / "daily").glob("events-*.jsonl"))
        assert len(daily_files) == 1
        with open(daily_files[0]) as f:
            lines = f.readlines()

        assert len(lines) == 100  # 5 threads * 20 events

        # Verify each line is valid JSON
        for line in lines:
            json.loads(line)  # Should not raise


class TestErrorHandling:
    """Tests for graceful error handling."""

    def test_handles_malformed_input_gracefully(self, writer):
        """Invalid input doesn't crash, raises appropriate error."""
        with pytest.raises(ValueError):
            writer.create_event(
                surface="invalid_surface",  # type: ignore
                event_type=EventType.INTERACTION,
                direction=Direction.INBOUND,
                summary="Test",
            )

    def test_handles_missing_stream_dir_gracefully(self):
        """Writer creates stream directory if it doesn't exist."""
        with tempfile.TemporaryDirectory() as tmpdir:
            non_existent = Path(tmpdir) / "new_stream"
            writer = StreamWriter(stream_dir=non_existent)

            event = writer.create_event(
                surface=Surface.CLI,
                event_type=EventType.INTERACTION,
                direction=Direction.INBOUND,
                summary="Test",
            )
            writer.write(event)

            assert non_existent.exists()
            daily_files = list((non_existent / "daily").glob("events-*.jsonl"))
            assert daily_files


class TestSurfaceTypes:
    """Tests for all surface types."""

    @pytest.mark.parametrize("surface", list(Surface))
    def test_all_surfaces_writable(self, writer, surface):
        """All defined surface types can be written."""
        event = writer.create_event(
            surface=surface,
            event_type=EventType.INTERACTION,
            direction=Direction.INBOUND,
            summary=f"Test {surface.value}",
        )
        writer.write(event)

        results = writer.query()
        assert len(results) == 1
        assert results[0]["surface"] == surface.value
