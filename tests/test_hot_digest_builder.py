"""
Test suite for the hot digest builder.

Run with: pytest tests/test_hot_digest_builder.py -v
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from lib.hot_digest_builder import build_digest, select_window_hours, summarize_with_ollama
from lib.stream_writer import StreamWriter, EventType, Direction, Surface


@pytest.fixture
def mind_env(tmp_path: Path):
    mind_path = tmp_path / ".claude-mind"
    mind_path.mkdir()

    env = os.environ.copy()
    env["SAMARA_MIND_PATH"] = str(mind_path)
    env["MIND_PATH"] = str(mind_path)
    return mind_path, env


def write_event(writer: StreamWriter, timestamp: str, surface: Surface, summary: str, content: str = ""):
    event = writer.create_event(
        surface=surface,
        event_type=EventType.INTERACTION if surface in (Surface.CLI, Surface.IMESSAGE) else EventType.SENSE,
        direction=Direction.INBOUND,
        summary=summary,
        content=content,
    )
    event.timestamp = timestamp
    writer.write(event)


def test_build_digest_includes_sections(mind_env, monkeypatch):
    mind_path, env = mind_env
    monkeypatch.setenv("SAMARA_MIND_PATH", env["SAMARA_MIND_PATH"])
    monkeypatch.setenv("MIND_PATH", env["MIND_PATH"])

    base = datetime.now(timezone.utc)
    monkeypatch.setenv("HOT_DIGEST_NOW", base.isoformat().replace("+00:00", "Z"))

    writer = StreamWriter(stream_dir=mind_path / "stream")

    write_event(
        writer,
        (base - timedelta(minutes=5)).isoformat().replace("+00:00", "Z"),
        Surface.IMESSAGE,
        "E asked about memory",
        "**E:** Hello\n\n**Claude:** Hi",
    )

    write_event(
        writer,
        (base - timedelta(minutes=70)).isoformat().replace("+00:00", "Z"),
        Surface.CLI,
        "CLI session work",
        "- Implemented digest tests",
    )

    write_event(
        writer,
        (base - timedelta(minutes=120)).isoformat().replace("+00:00", "Z"),
        Surface.WEBHOOK,
        "Webhook ping",
        "github push",
    )

    digest = build_digest(hours=12, max_tokens=1200, use_ollama=False)

    assert "### Conversations" in digest
    assert "**5m ago [Imessage]**" in digest
    assert "E: Hello" in digest

    assert "### Sessions" in digest
    assert "Implemented digest tests" in digest

    assert "### System Events" in digest
    assert "Webhook" in digest


def test_sense_section_caps_at_ten_events(mind_env, monkeypatch):
    mind_path, env = mind_env
    monkeypatch.setenv("SAMARA_MIND_PATH", env["SAMARA_MIND_PATH"])
    monkeypatch.setenv("MIND_PATH", env["MIND_PATH"])

    base = datetime.now(timezone.utc)
    monkeypatch.setenv("HOT_DIGEST_NOW", base.isoformat().replace("+00:00", "Z"))

    writer = StreamWriter(stream_dir=mind_path / "stream")
    for i in range(12):
        write_event(
            writer,
            (base - timedelta(minutes=i)).isoformat().replace("+00:00", "Z"),
            Surface.WEBHOOK,
            f"Webhook event {i}",
            "payload",
        )

    digest = build_digest(hours=12, max_tokens=1200, use_ollama=False)

    lines = digest.splitlines()
    assert "### System Events" in lines
    start_idx = lines.index("### System Events")
    bullets = [line for line in lines[start_idx + 1 :] if line.startswith("- ")]
    assert len(bullets) == 10


def test_open_threads_section_precedes_conversations(mind_env, monkeypatch):
    mind_path, env = mind_env
    monkeypatch.setenv("SAMARA_MIND_PATH", env["SAMARA_MIND_PATH"])
    monkeypatch.setenv("MIND_PATH", env["MIND_PATH"])

    state_dir = mind_path / "state"
    state_dir.mkdir(parents=True, exist_ok=True)
    threads_file = state_dir / "threads.json"
    threads_file.write_text(
        """{\n"""
        """  "threads": [\n"""
        """    {"title": "Follow up on memory plan", "status": "open"},\n"""
        """    {"title": "Closed item", "status": "closed"}\n"""
        """  ]\n"""
        """}\n"""
    )

    base = datetime.now(timezone.utc)
    monkeypatch.setenv("HOT_DIGEST_NOW", base.isoformat().replace("+00:00", "Z"))

    writer = StreamWriter(stream_dir=mind_path / "stream")
    write_event(
        writer,
        (base - timedelta(minutes=5)).isoformat().replace("+00:00", "Z"),
        Surface.IMESSAGE,
        "E asked about memory",
        "**E:** Hello\n\n**Claude:** Hi",
    )

    digest = build_digest(hours=12, max_tokens=1200, use_ollama=False)

    open_idx = digest.find("### Open Threads")
    conv_idx = digest.find("### Conversations")
    assert open_idx != -1
    assert conv_idx != -1
    assert open_idx < conv_idx
    assert "Follow up on memory plan" in digest
    assert "Closed item" not in digest


def test_builder_cache_uses_existing_output(mind_env, monkeypatch):
    mind_path, env = mind_env

    script = Path(__file__).parent.parent / "lib" / "hot_digest_builder.py"
    output_path = mind_path / "state" / "hot-digest.md"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    monkeypatch.setenv("SAMARA_MIND_PATH", env["SAMARA_MIND_PATH"])
    monkeypatch.setenv("MIND_PATH", env["MIND_PATH"])

    writer = StreamWriter(stream_dir=mind_path / "stream")
    write_event(
        writer,
        datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        Surface.CLI,
        "CLI event",
        "Did a thing",
    )

    result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--output",
            str(output_path),
            "--cache-ttl",
            "3600",
            "--no-ollama",
        ],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert output_path.exists()

    output_path.write_text("cached digest")

    result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--output",
            str(output_path),
            "--cache-ttl",
            "3600",
            "--no-ollama",
        ],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "cached digest"


def test_build_hot_digest_script_writes_output(mind_env, monkeypatch):
    mind_path, env = mind_env

    monkeypatch.setenv("SAMARA_MIND_PATH", env["SAMARA_MIND_PATH"])
    monkeypatch.setenv("MIND_PATH", env["MIND_PATH"])

    base = datetime.now(timezone.utc)
    monkeypatch.setenv("HOT_DIGEST_NOW", base.isoformat().replace("+00:00", "Z"))

    writer = StreamWriter(stream_dir=mind_path / "stream")
    write_event(
        writer,
        (base - timedelta(minutes=10)).isoformat().replace("+00:00", "Z"),
        Surface.CLI,
        "CLI event",
        "- Added output cache",
    )

    script = Path(__file__).parent.parent / "scripts" / "build-hot-digest"
    output_path = mind_path / "state" / "hot-digest.md"

    venv_bin = str(Path(sys.executable).parent)
    env["PATH"] = f"{venv_bin}:/usr/bin:/bin"

    result = subprocess.run(
        [
            "/bin/bash",
            str(script),
            "--output",
            str(output_path),
            "--cache-ttl",
            "900",
            "--no-ollama",
        ],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert output_path.exists()
    assert "## Recent Activity" in output_path.read_text(encoding="utf-8")


def test_summarize_with_ollama_fallback_uses_stream_distill(monkeypatch):
    def raise_file_not_found(*_args, **_kwargs):
        raise FileNotFoundError()

    monkeypatch.setattr(subprocess, "run", raise_file_not_found)

    events = [
        {
            "surface": "cli",
            "summary": "Did one thing",
            "timestamp": "2026-01-17T10:00:00Z",
            "id": "evt_1",
        },
        {
            "surface": "cli",
            "summary": "Did another thing",
            "timestamp": "2026-01-17T10:05:00Z",
            "id": "evt_2",
        },
    ]

    result = summarize_with_ollama(events, model="qwen3:8b")
    assert "CLI activity:" in result
    assert "Did one thing" in result


def test_select_window_hours_shrinks_for_dense_activity():
    metrics = {"long_rate": 20.0, "velocity": 3.0}
    window = select_window_hours(metrics, base_hours=12.0, min_hours=2.0, max_hours=24.0, target_rate=10.0)
    assert window == pytest.approx(4.24, rel=0.05)


def test_select_window_hours_expands_for_quiet_activity():
    metrics = {"long_rate": 1.0, "velocity": 0.5}
    window = select_window_hours(metrics, base_hours=12.0, min_hours=2.0, max_hours=24.0, target_rate=10.0)
    assert window == 24.0


def test_select_window_hours_defaults_to_base():
    metrics = {"long_rate": 10.0, "velocity": 1.0}
    window = select_window_hours(metrics, base_hours=12.0, min_hours=2.0, max_hours=24.0, target_rate=10.0)
    assert window == pytest.approx(12.0)


def test_build_digest_uses_config_auto_bounds(mind_env, monkeypatch):
    mind_path, env = mind_env
    monkeypatch.setenv("SAMARA_MIND_PATH", env["SAMARA_MIND_PATH"])
    monkeypatch.setenv("MIND_PATH", env["MIND_PATH"])

    config_path = mind_path / "config.json"
    config_path.write_text(
        json.dumps(
            {
                "stream": {
                    "hot_digest": {
                        "min_hours": 1,
                        "max_hours": 1,
                        "base_hours": 1,
                        "target_rate": 10.0,
                    }
                }
            }
        ),
        encoding="utf-8",
    )

    base = datetime.now(timezone.utc)
    monkeypatch.setenv("HOT_DIGEST_NOW", base.isoformat().replace("+00:00", "Z"))

    writer = StreamWriter(stream_dir=mind_path / "stream")
    write_event(
        writer,
        (base - timedelta(minutes=5)).isoformat().replace("+00:00", "Z"),
        Surface.CLI,
        "CLI event",
        "Did a thing",
    )

    _, metadata = build_digest(hours="auto", max_tokens=1200, use_ollama=False, return_metadata=True)
    assert metadata["window_hours"] == pytest.approx(1.0)
