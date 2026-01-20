"""
Test suite for stream audit metrics.

Run with: pytest tests/test_stream_audit.py -v
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from lib.stream_audit import audit_stream


def test_stream_audit_metrics_and_gaps():
    fixture_path = Path(__file__).parent / "fixtures" / "stream_audit_events.json"
    events = json.loads(fixture_path.read_text(encoding="utf-8"))

    digest_text = "iMessage activity: Asked about memory."
    now = datetime(2026, 1, 18, 12, 0, 0, tzinfo=timezone.utc)

    report = audit_stream(
        events=events,
        digest_text=digest_text,
        now=now,
        window_hours=168,
        digest_hours=12,
    )

    counts = report["counts"]
    assert counts["total_events"] == 3
    assert counts["by_surface"] == {"cli": 1, "imessage": 1, "system": 1}
    assert counts["by_type"] == {"interaction": 2, "system": 1}
    assert counts["by_direction"] == {"internal": 2, "inbound": 1}
    assert counts["undistilled_total"] == 3

    digest = report["digest_inclusion"]
    assert digest["total"]["eligible"] == 2
    assert digest["total"]["included"] == 1
    assert digest["by_surface"]["imessage"]["included"] == 1
    assert digest["by_surface"]["cli"]["included"] == 0

    gaps = report["gaps"]
    assert gaps["handoff_stale"] is True
    assert gaps["handoff_last_seen"] == "2026-01-10T08:00:00Z"
    assert gaps["missing_surfaces"] == [
        "bluesky",
        "calendar",
        "dream",
        "email",
        "location",
        "sense",
        "wake",
        "webhook",
        "x",
    ]
