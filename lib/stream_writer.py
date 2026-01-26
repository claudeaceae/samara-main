"""
Unified Event Stream Writer

Captures ALL interactions across surfaces into a single append-only event log.
This is the foundation for contiguous memory - enabling cross-surface context.

Usage:
    from lib.stream_writer import StreamWriter, Surface, EventType, Direction

    writer = StreamWriter()
    event = writer.create_event(
        surface=Surface.CLI,
        event_type=EventType.INTERACTION,
        direction=Direction.INBOUND,
        summary="User asked about memory architecture",
        content="Full conversation content...",
        session_id="optional-session-uuid",
        metadata={"emotional_texture": "curious, engaged"}
    )
    writer.write(event)

    # Query recent events
    recent = writer.query(hours=12)

    # Mark as distilled (processed by dream cycle)
    writer.mark_distilled(event.id)
"""
from __future__ import annotations

import fcntl
import json
import os
import secrets
import tempfile
from dataclasses import dataclass, field, asdict
from datetime import datetime, timedelta, timezone
from enum import Enum
from pathlib import Path
from typing import Any, Optional, Union

from .mind_paths import get_mind_path


class Surface(Enum):
    """Input surface types - where interactions originate."""

    CLI = "cli"
    IMESSAGE = "imessage"
    WAKE = "wake"
    DREAM = "dream"
    WEBHOOK = "webhook"
    X = "x"
    BLUESKY = "bluesky"
    EMAIL = "email"
    CALENDAR = "calendar"
    LOCATION = "location"
    SENSE = "sense"  # Generic sense event
    SYSTEM = "system"  # Internal system events


class EventType(Enum):
    """Type of event."""

    INTERACTION = "interaction"  # User-Claude exchange
    SENSE = "sense"  # External input detected
    SYSTEM = "system"  # Internal system event
    HANDOFF = "handoff"  # Session boundary marker


class Direction(Enum):
    """Direction of the event."""

    INBOUND = "inbound"  # Coming in (user message, sense event)
    OUTBOUND = "outbound"  # Going out (Claude response, sent message)
    INTERNAL = "internal"  # Internal processing


@dataclass
class Event:
    """A single event in the unified stream."""

    schema_version: str
    id: str
    timestamp: str
    surface: Surface
    type: EventType
    direction: Direction
    summary: str
    distilled: bool = False
    session_id: Optional[str] = None
    content: Optional[str] = None
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "schema_version": self.schema_version,
            "id": self.id,
            "timestamp": self.timestamp,
            "surface": self.surface.value,
            "type": self.type.value,
            "direction": self.direction.value,
            "summary": self.summary,
            "distilled": self.distilled,
            "session_id": self.session_id,
            "content": self.content,
            "metadata": self.metadata,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Event:
        """Create Event from dictionary."""
        return cls(
            schema_version=data.get("schema_version", "1"),
            id=data["id"],
            timestamp=data["timestamp"],
            surface=Surface(data["surface"]),
            type=EventType(data["type"]),
            direction=Direction(data["direction"]),
            summary=data["summary"],
            distilled=data.get("distilled", False),
            session_id=data.get("session_id"),
            content=data.get("content"),
            metadata=data.get("metadata", {}),
        )


class StreamWriter:
    """
    Manages the unified event stream.

    Thread-safe through file locking. Append-only for data integrity.
    """

    def __init__(self, stream_dir: Optional[Path] = None):
        """
        Initialize StreamWriter.

        Args:
            stream_dir: Override stream directory (default: ~/.claude-mind/memory/stream)
        """
        if stream_dir:
            self.stream_dir = Path(stream_dir)
        else:
            self.stream_dir = get_mind_path() / "memory" / "stream"

        # Ensure directories exist
        self.stream_dir.mkdir(parents=True, exist_ok=True)
        self.archive_dir = self.stream_dir / "archive"
        self.archive_dir.mkdir(exist_ok=True)

        self.stream_file = self.stream_dir / "events.jsonl"
        self.legacy_stream_file = self.stream_dir / "events.legacy.jsonl"
        self.daily_dir = self.stream_dir / "daily"
        self.daily_dir.mkdir(exist_ok=True)

        self.distilled_index_file = self.stream_dir / "distilled-index.jsonl"
        self.use_daily_shards = True

    def _generate_event_id(self) -> str:
        """Generate unique event ID: evt_{timestamp}_{random}."""
        timestamp = int(datetime.now(timezone.utc).timestamp())
        random_suffix = secrets.token_hex(4)
        return f"evt_{timestamp}_{random_suffix}"

    def create_event(
        self,
        surface: Surface,
        event_type: EventType,
        direction: Direction,
        summary: str,
        session_id: Optional[str] = None,
        content: Optional[str] = None,
        metadata: Optional[dict[str, Any]] = None,
    ) -> Event:
        """
        Create a new Event with auto-generated ID and timestamp.

        Args:
            surface: Where the interaction originated
            event_type: Type of event
            direction: Direction of the event
            summary: Brief one-line summary (for digest)
            session_id: Optional Claude Code session ID
            content: Optional full content
            metadata: Optional additional metadata

        Returns:
            Event instance ready to be written

        Raises:
            ValueError: If surface is not a valid Surface enum
        """
        # Validate surface type
        if not isinstance(surface, Surface):
            raise ValueError(f"surface must be a Surface enum, got {type(surface)}")

        return Event(
            schema_version="1",
            id=self._generate_event_id(),
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            surface=surface,
            type=event_type,
            direction=direction,
            summary=summary,
            session_id=session_id,
            content=content,
            metadata=metadata or {},
        )

    def write(self, event: Event) -> None:
        """
        Write event to the stream (append-only, thread-safe).

        Uses file locking to ensure concurrent writes don't corrupt data.
        """
        line = json.dumps(event.to_dict(), ensure_ascii=False) + "\n"

        target_file = self.stream_file
        if self.use_daily_shards:
            target_file = self._daily_file_for_timestamp(event.timestamp)

        # Atomic append with file locking
        with open(target_file, "a", encoding="utf-8") as f:
            # Acquire exclusive lock
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                f.write(line)
                f.flush()
                os.fsync(f.fileno())
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)

    def _daily_file_for_timestamp(self, timestamp: str) -> Path:
        """Return the daily shard file path for a timestamp."""
        date_str = timestamp[:10] if isinstance(timestamp, str) and len(timestamp) >= 10 else ""
        if not date_str:
            date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        return self.daily_dir / f"events-{date_str}.jsonl"

    def _iter_stream_files(self, hours: Optional[float], now: datetime) -> list[Path]:
        """List stream files to read for a given window."""
        files: list[Path] = []

        daily_files: list[Path] = []
        if self.daily_dir.exists():
            if hours is None:
                daily_files = sorted(self.daily_dir.glob("events-*.jsonl"))
            else:
                start_date = (now - timedelta(hours=hours)).date()
                end_date = now.date()
                total_days = (end_date - start_date).days
                for offset in range(total_days + 1):
                    date = start_date + timedelta(days=offset)
                    path = self.daily_dir / f"events-{date.strftime('%Y-%m-%d')}.jsonl"
                    if path.exists():
                        daily_files.append(path)

        files.extend(daily_files)

        legacy_file = None
        if daily_files:
            if self.stream_file.exists():
                legacy_file = self.stream_file
        else:
            if self.legacy_stream_file.exists():
                legacy_file = self.legacy_stream_file
            elif self.stream_file.exists():
                legacy_file = self.stream_file

        if legacy_file is not None:
            files.append(legacy_file)

        return files

    def list_stream_files(
        self,
        hours: Optional[float] = None,
        now: Optional[datetime] = None,
    ) -> list[Path]:
        """Expose stream files for validation or migration."""
        now = now or datetime.now(timezone.utc)
        return self._iter_stream_files(hours, now)

    def _load_distilled_index(self) -> set[str]:
        """Load distilled event IDs from the sidecar index."""
        if not self.distilled_index_file.exists():
            return set()

        ids: set[str] = set()
        with open(self.distilled_index_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                except json.JSONDecodeError:
                    continue
                event_id = data.get("id")
                if isinstance(event_id, str) and event_id:
                    ids.add(event_id)
        return ids

    def _append_distilled_index(self, entries: list[dict[str, Any]]) -> None:
        """Append entries to the sidecar distilled index with locking."""
        if not entries:
            return
        lines = "\n".join(json.dumps(entry, ensure_ascii=False) for entry in entries) + "\n"
        with open(self.distilled_index_file, "a", encoding="utf-8") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                f.write(lines)
                f.flush()
                os.fsync(f.fileno())
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)

    def _write_distilled_index(self, entries: list[dict[str, Any]]) -> None:
        """Write the distilled index atomically."""
        with tempfile.NamedTemporaryFile(
            mode="w",
            dir=self.stream_dir,
            delete=False,
            suffix=".jsonl",
            encoding="utf-8",
        ) as tmp:
            if entries:
                tmp.write("\n".join(json.dumps(entry, ensure_ascii=False) for entry in entries))
                tmp.write("\n")
            tmp_path = tmp.name

        os.replace(tmp_path, self.distilled_index_file)

    def _lookup_event_timestamps(self, event_ids: set[str]) -> dict[str, str]:
        """Return timestamps for event IDs by scanning the stream file."""
        timestamps: dict[str, str] = {}
        if not event_ids:
            return timestamps

        now = datetime.now(timezone.utc)
        for stream_file in self._iter_stream_files(None, now):
            if not stream_file.exists():
                continue
            with open(stream_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        data = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    event_id = data.get("id")
                    if event_id in event_ids and isinstance(data.get("timestamp"), str):
                        timestamps[event_id] = data["timestamp"]
                        if len(timestamps) >= len(event_ids):
                            return timestamps
        return timestamps

    def query(
        self,
        hours: Optional[int] = None,
        surface: Optional[Surface] = None,
        include_distilled: bool = False,
        event_type: Optional[EventType] = None,
    ) -> list[dict[str, Any]]:
        """
        Query events from the stream.

        Args:
            hours: Only include events from the last N hours
            surface: Filter by surface type
            include_distilled: Include events marked as distilled
            event_type: Filter by event type

        Returns:
            List of event dictionaries matching criteria
        """
        now = datetime.now(timezone.utc)
        stream_files = self._iter_stream_files(hours, now)
        if not stream_files:
            return []

        results = []
        distilled_ids = self._load_distilled_index()
        cutoff_time = None
        if hours:
            cutoff_time = now - timedelta(hours=hours)

        for stream_file in stream_files:
            if not stream_file.exists():
                continue
            with open(stream_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue

                    try:
                        data = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    # Filter by distilled status (stream flag or sidecar index)
                    is_distilled = bool(data.get("distilled", False)) or data.get("id") in distilled_ids
                    if not include_distilled and is_distilled:
                        continue
                    if is_distilled and not data.get("distilled", False):
                        data["distilled"] = True

                    # Filter by time
                    if cutoff_time:
                        event_time = datetime.fromisoformat(
                            data["timestamp"].replace("Z", "+00:00")
                        )
                        if event_time < cutoff_time:
                            continue

                    # Filter by surface
                    if surface and data.get("surface") != surface.value:
                        continue

                    # Filter by type
                    if event_type and data.get("type") != event_type.value:
                        continue

                    results.append(data)

        return results

    def mark_distilled(self, event_ids: Union[str, list[str]]) -> int:
        """
        Mark events as distilled (processed into warm memory).

        Uses a sidecar index for append-only distillation tracking.

        Args:
            event_ids: Single ID or list of IDs to mark

        Returns:
            Number of events marked
        """
        if isinstance(event_ids, str):
            event_ids = [event_ids]

        id_set = set(event_ids)

        now = datetime.now(timezone.utc)
        if not id_set or not self._iter_stream_files(None, now):
            return 0

        distilled_ids = self._load_distilled_index()
        pending_ids = id_set - distilled_ids
        if not pending_ids:
            return 0

        timestamps = self._lookup_event_timestamps(pending_ids)
        if not timestamps:
            return 0

        now_iso = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        entries = [
            {"id": event_id, "timestamp": ts, "distilled_at": now_iso}
            for event_id, ts in timestamps.items()
        ]

        self._append_distilled_index(entries)

        return len(entries)

    def archive(self, days_old: int = 30) -> int:
        """
        Move events older than threshold to archive.

        Args:
            days_old: Move events older than this many days

        Returns:
            Number of events archived
        """
        cutoff = datetime.now(timezone.utc) - timedelta(days=days_old)
        archived_count = 0

        daily_files = sorted(self.daily_dir.glob("events-*.jsonl"))
        if daily_files:
            cutoff_date = cutoff.date()
            for stream_file in daily_files:
                date_str = stream_file.stem.replace("events-", "")
                try:
                    file_date = datetime.strptime(date_str, "%Y-%m-%d").date()
                except ValueError:
                    continue
                if file_date >= cutoff_date:
                    continue

                with open(stream_file, "r", encoding="utf-8") as f:
                    archived_count += sum(1 for _ in f if _.strip())

                archive_file = self.archive_dir / stream_file.name
                os.replace(stream_file, archive_file)

            return archived_count

        legacy_file = self.legacy_stream_file if self.legacy_stream_file.exists() else self.stream_file
        if not legacy_file.exists():
            return 0

        keep_lines = []
        archive_by_date: dict[str, list[str]] = {}

        with open(legacy_file, "r", encoding="utf-8") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                lines = f.readlines()
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)

        for line in lines:
            line = line.strip()
            if not line:
                continue

            try:
                data = json.loads(line)
                event_time = datetime.fromisoformat(
                    data["timestamp"].replace("Z", "+00:00")
                )

                if event_time < cutoff:
                    date_str = event_time.strftime("%Y-%m-%d")
                    if date_str not in archive_by_date:
                        archive_by_date[date_str] = []
                    archive_by_date[date_str].append(json.dumps(data, ensure_ascii=False))
                    archived_count += 1
                else:
                    keep_lines.append(json.dumps(data, ensure_ascii=False))
            except (json.JSONDecodeError, KeyError):
                keep_lines.append(line)

        for date_str, event_lines in archive_by_date.items():
            archive_file = self.archive_dir / f"events-{date_str}.jsonl"
            with open(archive_file, "a", encoding="utf-8") as f:
                f.write("\n".join(event_lines) + "\n")

        with tempfile.NamedTemporaryFile(
            mode="w",
            dir=self.stream_dir,
            delete=False,
            suffix=".jsonl",
            encoding="utf-8",
        ) as tmp:
            if keep_lines:
                tmp.write("\n".join(keep_lines) + "\n")
            tmp_path = tmp.name

        os.replace(tmp_path, legacy_file)

        return archived_count

    def query_undistilled(
        self,
        date: Optional[str] = None,
        before_date: Optional[str] = None,
    ) -> list[dict[str, Any]]:
        """
        Query events that haven't been distilled yet.

        Args:
            date: Optional exact date filter (YYYY-MM-DD format)
            before_date: Optional upper bound date (events before this date)

        Returns:
            List of undistilled event dictionaries
        """
        results = self.query(include_distilled=False)

        if date:
            results = [
                e for e in results
                if e["timestamp"].startswith(date)
            ]

        if before_date:
            # Include events from before this date (exclusive)
            results = [
                e for e in results
                if e["timestamp"][:10] < before_date
            ]

        return results

    def mark_distilled_before_date(self, before_date: str) -> int:
        """
        Mark all undistilled events before a given date as distilled.

        Args:
            before_date: Mark events before this date (YYYY-MM-DD format)

        Returns:
            Number of events marked
        """
        now = datetime.now(timezone.utc)
        if not self._iter_stream_files(None, now):
            return 0

        undistilled_events = self.query_undistilled(before_date=before_date)
        event_ids = [event.get("id") for event in undistilled_events if event.get("id")]
        return self.mark_distilled(event_ids)

    def rebuild_distilled_index(self) -> int:
        """Rebuild sidecar index from stream file distilled flags."""
        now = datetime.now(timezone.utc)
        stream_files = self._iter_stream_files(None, now)
        if not stream_files:
            self._write_distilled_index([])
            return 0

        entries: list[dict[str, Any]] = []
        seen: set[str] = set()
        now_iso = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

        for stream_file in stream_files:
            if not stream_file.exists():
                continue
            with open(stream_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        data = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if not data.get("distilled", False):
                        continue
                    event_id = data.get("id")
                    timestamp = data.get("timestamp")
                    if not isinstance(event_id, str) or not event_id:
                        continue
                    if event_id in seen:
                        continue
                    entry: dict[str, Any] = {"id": event_id, "distilled_at": now_iso}
                    if isinstance(timestamp, str) and timestamp:
                        entry["timestamp"] = timestamp
                    entries.append(entry)
                    seen.add(event_id)

        self._write_distilled_index(entries)
        return len(entries)

    def migrate_legacy_to_daily(self, archive_legacy: bool = True) -> int:
        """Split legacy events.jsonl into daily shard files."""
        legacy_file = self.stream_file
        if not legacy_file.exists():
            return 0

        events_by_date: dict[str, list[str]] = {}
        migrated_count = 0

        with open(legacy_file, "r", encoding="utf-8") as f:
            for line in f:
                raw = line.strip()
                if not raw:
                    continue
                try:
                    data = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                timestamp = data.get("timestamp")
                if not isinstance(timestamp, str) or len(timestamp) < 10:
                    continue
                date_str = timestamp[:10]
                events_by_date.setdefault(date_str, []).append(json.dumps(data, ensure_ascii=False))
                migrated_count += 1

        for date_str, lines in events_by_date.items():
            daily_file = self.daily_dir / f"events-{date_str}.jsonl"
            with open(daily_file, "a", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")

        if archive_legacy:
            target = self.legacy_stream_file
            if target.exists():
                suffix = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
                target = self.stream_dir / f"events.legacy.{suffix}.jsonl"
            os.replace(legacy_file, target)

        return migrated_count


# Convenience function for quick event writing
def write_event(
    surface: Surface,
    event_type: EventType,
    direction: Direction,
    summary: str,
    **kwargs: Any,
) -> str:
    """
    Convenience function to write an event and return its ID.

    Example:
        event_id = write_event(
            Surface.CLI,
            EventType.INTERACTION,
            Direction.INBOUND,
            "User asked about memory",
            content="Full content...",
        )
    """
    writer = StreamWriter()
    event = writer.create_event(
        surface=surface,
        event_type=event_type,
        direction=direction,
        summary=summary,
        **kwargs,
    )
    writer.write(event)
    return event.id
