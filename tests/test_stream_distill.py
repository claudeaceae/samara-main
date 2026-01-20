"""
Test suite for stream distillation helpers.

Run with: pytest tests/test_stream_distill.py -v
"""
from __future__ import annotations

import json
from pathlib import Path

from lib.stream_distill import build_narrative


def test_build_narrative_from_fixture():
    fixture_path = Path(__file__).parent / "fixtures" / "undistilled_events.json"
    events = json.loads(fixture_path.read_text(encoding="utf-8"))

    narrative = build_narrative(events, max_per_surface=3)

    expected = (
        "iMessage activity: E asked about memory; Discussed cache strategy.\n\n"
        "CLI activity: Implemented thread indexer.\n\n"
        "Wake activity: Ran dream cycle cleanup."
    )
    assert narrative == expected


def test_build_narrative_uses_content_fallback():
    events = [
        {
            "timestamp": "2026-01-18T09:00:00Z",
            "surface": "cli",
            "summary": "",
            "content": "Filled in missing summary.",
        }
    ]

    narrative = build_narrative(events)
    assert "Filled in missing summary" in narrative
