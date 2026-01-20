"""
Test suite for the unified event stream CLI.

Run with: pytest tests/test_stream_cli.py -v
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from lib.stream_writer import StreamWriter, EventType, Direction, Surface

REPO_ROOT = Path(__file__).parent.parent
CLI_PATH = REPO_ROOT / "lib" / "stream_cli.py"


def run_cli(args: list[str], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    cmd = [sys.executable, str(CLI_PATH)] + args
    return subprocess.run(cmd, capture_output=True, text=True, env=env)


@pytest.fixture
def mind_env(tmp_path: Path):
    mind_path = tmp_path / ".claude-mind"
    mind_path.mkdir()

    env = os.environ.copy()
    env["SAMARA_MIND_PATH"] = str(mind_path)
    env["MIND_PATH"] = str(mind_path)
    return mind_path, env


def test_write_and_query_json(mind_env):
    _, env = mind_env

    result = run_cli(
        [
            "--format",
            "json",
            "write",
            "--surface",
            "cli",
            "--type",
            "interaction",
            "--direction",
            "inbound",
            "--summary",
            "Test event",
        ],
        env,
    )
    assert result.returncode == 0, result.stderr

    payload = json.loads(result.stdout)
    assert "id" in payload

    result = run_cli(["--format", "json", "query"], env)
    assert result.returncode == 0, result.stderr

    events = json.loads(result.stdout)
    assert len(events) == 1
    assert events[0]["summary"] == "Test event"


def test_mark_distilled_filters_results(mind_env):
    _, env = mind_env

    result = run_cli(
        [
            "--format",
            "json",
            "write",
            "--surface",
            "cli",
            "--type",
            "interaction",
            "--direction",
            "inbound",
            "--summary",
            "Distill me",
        ],
        env,
    )
    event_id = json.loads(result.stdout)["id"]

    result = run_cli(["mark-distilled", event_id], env)
    assert result.returncode == 0, result.stderr

    result = run_cli(["--format", "json", "query"], env)
    events = json.loads(result.stdout)
    assert events == []

    result = run_cli(["--format", "json", "query", "--include-distilled"], env)
    events = json.loads(result.stdout)
    assert len(events) == 1


def test_handoff_event_links_thread_ids(mind_env):
    _, env = mind_env
    thread_ids = ["thread_abc123"]

    result = run_cli(
        [
            "--format",
            "json",
            "write",
            "--surface",
            "cli",
            "--type",
            "handoff",
            "--direction",
            "internal",
            "--summary",
            "Handoff created",
            "--metadata",
            json.dumps({"thread_ids": thread_ids}),
        ],
        env,
    )
    assert result.returncode == 0, result.stderr

    event_id = json.loads(result.stdout)["id"]
    result = run_cli(["--format", "json", "query"], env)
    assert result.returncode == 0, result.stderr

    events = json.loads(result.stdout)
    event = next(event for event in events if event["id"] == event_id)
    assert event["type"] == "handoff"
    assert event["metadata"]["thread_ids"] == thread_ids


def test_undistilled_json_output(mind_env):
    _, env = mind_env

    result = run_cli(
        [
            "--format",
            "json",
            "write",
            "--surface",
            "cli",
            "--type",
            "interaction",
            "--direction",
            "inbound",
            "--summary",
            "Undistilled",
            "--content",
            "Full content",
            "--metadata",
            json.dumps({"source": "test"}),
        ],
        env,
    )
    assert result.returncode == 0, result.stderr

    result = run_cli(["--format", "json", "undistilled"], env)
    assert result.returncode == 0, result.stderr

    events = json.loads(result.stdout)
    assert len(events) == 1
    assert events[0]["summary"] == "Undistilled"
    assert "metadata" in events[0]
    assert events[0]["metadata"]["source"] == "test"
    assert events[0]["content"] == "Full content"


def test_archive_moves_old_events(mind_env):
    mind_path, env = mind_env

    writer = StreamWriter(stream_dir=mind_path / "stream")
    old_event = writer.create_event(
        surface=Surface.CLI,
        event_type=EventType.INTERACTION,
        direction=Direction.INBOUND,
        summary="Old event",
    )
    old_event.timestamp = (datetime.now(timezone.utc) - timedelta(days=2)).isoformat().replace(
        "+00:00", "Z"
    )
    writer.write(old_event)

    result = run_cli(["archive", "--days", "1"], env)
    assert result.returncode == 0, result.stderr

    archive_dir = mind_path / "stream" / "archive"
    assert any(archive_dir.glob("events-*.jsonl"))


def test_query_sorts_by_timestamp(mind_env):
    mind_path, env = mind_env

    writer = StreamWriter(stream_dir=mind_path / "stream")
    base = datetime.now(timezone.utc)

    newer = writer.create_event(
        surface=Surface.CLI,
        event_type=EventType.INTERACTION,
        direction=Direction.INBOUND,
        summary="Newer",
    )
    newer.timestamp = (base + timedelta(minutes=5)).isoformat().replace("+00:00", "Z")

    older = writer.create_event(
        surface=Surface.CLI,
        event_type=EventType.INTERACTION,
        direction=Direction.INBOUND,
        summary="Older",
    )
    older.timestamp = (base - timedelta(minutes=5)).isoformat().replace("+00:00", "Z")

    writer.write(newer)
    writer.write(older)

    result = run_cli(["--format", "json", "query"], env)
    assert result.returncode == 0, result.stderr

    events = json.loads(result.stdout)
    summaries = [event["summary"] for event in events]
    assert summaries == ["Older", "Newer"]


def test_validate_reports_invalid_lines(mind_env):
    mind_path, env = mind_env

    result = run_cli(
        [
            "--format",
            "json",
            "write",
            "--surface",
            "cli",
            "--type",
            "interaction",
            "--direction",
            "inbound",
            "--summary",
            "Valid event",
        ],
        env,
    )
    assert result.returncode == 0, result.stderr

    stream_file = mind_path / "stream" / "events.jsonl"
    with stream_file.open("a", encoding="utf-8") as handle:
        handle.write("{not json}\n")

    result = run_cli(["--format", "json", "validate"], env)
    assert result.returncode == 0, result.stderr

    payload = json.loads(result.stdout)
    assert payload["valid"] is False
    assert payload["error_count"] == 1
