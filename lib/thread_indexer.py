#!/usr/bin/env python3
"""
Thread Indexer

Parse session handoffs and update the runtime threads index.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any, Optional

# Add parent dir to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.mind_paths import get_mind_path

CLOSED_THREAD_STATUSES = {
    "closed",
    "done",
    "resolved",
    "complete",
    "completed",
    "archived",
}


def normalize_title(title: str) -> str:
    """Normalize a thread title for stable ID generation."""
    return re.sub(r"\s+", " ", title.strip()).lower()


def thread_id_for_title(title: str) -> str:
    """Create a stable thread ID from a title."""
    normalized = normalize_title(title)
    digest = hashlib.sha1(normalized.encode("utf-8")).hexdigest()[:10]
    return f"thread_{digest}"


def extract_section_lines(text: str, header: str) -> list[str]:
    """Extract lines between a markdown header and the next header."""
    lines = text.splitlines()
    in_section = False
    collected: list[str] = []
    target = f"## {header}".lower()

    for line in lines:
        stripped = line.strip()
        if stripped.lower() == target:
            in_section = True
            continue
        if in_section:
            if stripped.startswith("## "):
                break
            collected.append(line)

    return collected


def parse_open_threads(text: str) -> list[str]:
    """Parse Open Threads section entries from handoff markdown."""
    lines = extract_section_lines(text, "Open Threads")
    threads: list[str] = []

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.lower() == "none identified.":
            return []

        cleaned = re.sub(r"^[-*]\s+", "", stripped)
        cleaned = re.sub(r"^[0-9]+[.)]\s+", "", cleaned)
        cleaned = re.sub(r"^\[[ xX]\]\s+", "", cleaned)
        cleaned = cleaned.strip()

        if cleaned:
            threads.append(cleaned)

    return threads


def parse_session_id(text: str) -> Optional[str]:
    """Extract session ID from a handoff file if present."""
    match = re.search(r"^\*\*Session ID:\*\*\s*(\S+)", text, re.MULTILINE)
    return match.group(1) if match else None


def load_threads(path: Path) -> dict[str, Any]:
    """Load threads.json, tolerating missing or malformed files."""
    if not path.exists():
        return {"threads": []}

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"threads": []}

    if isinstance(data, list):
        return {"threads": data}

    if isinstance(data, dict) and isinstance(data.get("threads"), list):
        return data

    return {"threads": []}


def update_threads(
    data: dict[str, Any],
    open_titles: list[str],
    handoff_path: Path,
    session_id: Optional[str],
) -> tuple[list[dict[str, Any]], list[str]]:
    """Update threads list with new open threads."""
    threads = data.get("threads", [])
    if not isinstance(threads, list):
        threads = []

    existing_by_id: dict[str, dict[str, Any]] = {}
    normalized_existing: list[dict[str, Any]] = []

    for thread in threads:
        if not isinstance(thread, dict):
            continue

        title = str(thread.get("title") or thread.get("summary") or thread.get("name") or "").strip()
        thread_id = str(thread.get("id") or "").strip()
        if not thread_id and title:
            thread_id = thread_id_for_title(title)
            thread["id"] = thread_id

        if thread_id:
            existing_by_id[thread_id] = thread

        normalized_existing.append(thread)

    updated_threads: list[dict[str, Any]] = []
    updated_ids: list[str] = []

    for title in open_titles:
        thread_id = thread_id_for_title(title)
        thread = existing_by_id.get(thread_id)
        if thread is None:
            thread = {"id": thread_id}
            normalized_existing.append(thread)
            existing_by_id[thread_id] = thread

        thread["title"] = title
        thread["status"] = "open"
        thread["source"] = {
            "handoff_path": str(handoff_path),
            "session_id": session_id,
        }

        updated_threads.append(thread)
        updated_ids.append(thread_id)

    remaining = [
        thread
        for thread in normalized_existing
        if isinstance(thread, dict)
        and str(thread.get("id") or "").strip()
        and str(thread.get("id")).strip() not in updated_ids
    ]

    return updated_threads + remaining, updated_ids


def index_handoff(handoff_path: Path, threads_path: Path) -> tuple[dict[str, Any], list[str]]:
    """Index a single handoff file into threads.json."""
    try:
        text = handoff_path.read_text(encoding="utf-8")
    except OSError:
        return {"threads": []}, []

    open_titles = parse_open_threads(text)
    if not open_titles:
        return load_threads(threads_path), []

    session_id = parse_session_id(text)
    data = load_threads(threads_path)
    updated_threads, thread_ids = update_threads(data, open_titles, handoff_path, session_id)
    data["threads"] = updated_threads

    try:
        threads_path.parent.mkdir(parents=True, exist_ok=True)
        threads_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    except OSError:
        pass

    return data, thread_ids


def main() -> int:
    parser = argparse.ArgumentParser(description="Index handoff open threads into threads.json")
    parser.add_argument("--handoff", required=True, type=Path, help="Path to handoff markdown")
    parser.add_argument(
        "--threads-path",
        type=Path,
        help="Override threads.json path (defaults to mind state path)",
    )
    parser.add_argument("--format", choices=["text", "json"], default="text")

    args = parser.parse_args()

    threads_path = args.threads_path or (get_mind_path() / "state" / "threads.json")
    data, thread_ids = index_handoff(args.handoff, threads_path)

    if args.format == "json":
        print(
            json.dumps(
                {
                    "threads_path": str(threads_path),
                    "thread_ids": thread_ids,
                    "thread_count": len(data.get("threads", [])),
                }
            )
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
