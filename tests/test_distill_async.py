"""
Test suite for async distillation behavior.

Run with: pytest tests/test_distill_async.py -v
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from pathlib import Path

import pytest

SCRIPT_PATH = Path(__file__).parent.parent / "scripts" / "distill-claude-session"


def wait_for_log_entry(log_path: Path, needle: str, timeout_seconds: float = 3.0) -> bool:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if log_path.exists():
            content = log_path.read_text()
            if needle in content:
                return True
        time.sleep(0.05)
    return False


@pytest.mark.skipif(shutil.which("jq") is None, reason="jq is required for distill script")
def test_distill_returns_immediately_and_forks(tmp_path: Path):
    mind_path = tmp_path / ".claude-mind"
    logs_dir = mind_path / "logs"
    episodes_dir = mind_path / "memory" / "episodes"
    logs_dir.mkdir(parents=True)
    episodes_dir.mkdir(parents=True)

    env = os.environ.copy()
    env["SAMARA_MIND_PATH"] = str(mind_path)
    env["MIND_PATH"] = str(mind_path)

    true_path = shutil.which("true") or "/usr/bin/true"
    env["CLAUDE_PATH"] = true_path

    transcript_path = tmp_path / "transcript.jsonl"
    lines = []
    for _ in range(6):
        lines.append(json.dumps({"type": "user", "message": {"content": "Hello " + "x" * 120}}))
        lines.append(json.dumps({"type": "assistant", "message": {"content": "Hi " + "y" * 120}}))
    transcript_path.write_text("\n".join(lines))

    hook_input = json.dumps(
        {
            "session_id": "test-session-123",
            "transcript_path": str(transcript_path),
            "reason": "exit",
            "cwd": str(tmp_path),
        }
    )

    start = time.monotonic()
    proc = subprocess.run(
        [str(SCRIPT_PATH)],
        input=hook_input,
        text=True,
        capture_output=True,
        env=env,
    )
    elapsed = time.monotonic() - start

    assert proc.returncode == 0
    assert "\"ok\": true" in proc.stdout
    assert elapsed < 2.0

    log_path = logs_dir / "claude-sessions.log"
    assert wait_for_log_entry(log_path, "Forking distillation to background")
    assert wait_for_log_entry(log_path, "Background distillation started")
