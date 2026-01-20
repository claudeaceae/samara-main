"""
Test suite for the thread indexer.

Run with: pytest tests/test_thread_indexer.py -v
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from lib.thread_indexer import thread_id_for_title

REPO_ROOT = Path(__file__).parent.parent
INDEXER_PATH = REPO_ROOT / "lib" / "thread_indexer.py"


@pytest.fixture
def mind_env(tmp_path: Path):
    mind_path = tmp_path / ".claude-mind"
    mind_path.mkdir()

    env = os.environ.copy()
    env["SAMARA_MIND_PATH"] = str(mind_path)
    env["MIND_PATH"] = str(mind_path)
    return mind_path, env


def write_handoff(path: Path, open_threads: list[str]) -> None:
    lines = [
        "# Session Handoff: 2026-01-18 10:00",
        "",
        "**Session ID:** test-session",
        "**Working Directory:** /tmp",
        "",
        "## Open Threads",
    ]

    if open_threads:
        for thread in open_threads:
            lines.append(f"- {thread}")
    else:
        lines.append("None identified.")

    lines += ["", "## Emotional Texture", "None identified."]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run_indexer(handoff_path: Path, env: dict[str, str]) -> dict[str, object]:
    result = subprocess.run(
        [sys.executable, str(INDEXER_PATH), "--handoff", str(handoff_path), "--format", "json"],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_indexer_creates_threads_json_from_handoff(mind_env):
    mind_path, env = mind_env
    handoff_path = mind_path / "state" / "handoffs" / "handoff.md"
    handoff_path.parent.mkdir(parents=True, exist_ok=True)

    open_threads = ["Follow up on memory plan", "Fix digest cache"]
    write_handoff(handoff_path, open_threads)

    payload = run_indexer(handoff_path, env)

    threads_path = mind_path / "state" / "threads.json"
    data = json.loads(threads_path.read_text(encoding="utf-8"))
    threads = data["threads"]

    expected_ids = [thread_id_for_title(title) for title in open_threads]
    assert payload["thread_ids"] == expected_ids
    assert [thread["title"] for thread in threads[:2]] == open_threads
    assert threads[0]["status"] == "open"
    assert threads[0]["id"] == expected_ids[0]


def test_indexer_reopens_existing_thread(mind_env):
    mind_path, env = mind_env
    state_dir = mind_path / "state"
    state_dir.mkdir(parents=True, exist_ok=True)
    threads_path = state_dir / "threads.json"

    closed_title = "Follow up on memory plan"
    closed_id = thread_id_for_title(closed_title)
    threads_path.write_text(
        json.dumps(
            {
                "threads": [
                    {
                        "id": closed_id,
                        "title": closed_title,
                        "status": "closed",
                    }
                ]
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    handoff_path = state_dir / "handoffs" / "handoff.md"
    handoff_path.parent.mkdir(parents=True, exist_ok=True)
    write_handoff(handoff_path, [closed_title])

    run_indexer(handoff_path, env)

    data = json.loads(threads_path.read_text(encoding="utf-8"))
    thread = data["threads"][0]
    assert thread["id"] == closed_id
    assert thread["status"] == "open"
