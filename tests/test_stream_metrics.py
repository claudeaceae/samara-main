"""
Tests for stream metrics helpers.

Run with: pytest tests/test_stream_metrics.py -v
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

from lib.stream_metrics import (
    compute_event_metrics,
    compute_velocity,
    count_events_in_window,
    parse_timestamp,
    rate_per_hour,
)


FIXTURE_PATH = Path(__file__).parent / "fixtures" / "stream_metrics_events.json"


def load_fixture_events():
    return json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))


def test_parse_timestamp_handles_invalid():
    assert parse_timestamp("not-a-timestamp") is None
    assert parse_timestamp("") is None


def test_rate_and_counts_from_fixture():
    events = load_fixture_events()
    now = datetime(2026, 1, 19, 12, 0, 0, tzinfo=timezone.utc)

    short_count = count_events_in_window(events, now, 0.5)
    mid_count = count_events_in_window(events, now, 2.0)
    long_count = count_events_in_window(events, now, 12.0)

    assert short_count == 6
    assert mid_count == 12
    assert long_count == 24

    assert rate_per_hour(events, now, 0.5) == pytest.approx(12.0)
    assert rate_per_hour(events, now, 2.0) == pytest.approx(6.0)
    assert rate_per_hour(events, now, 12.0) == pytest.approx(2.0)


def test_compute_event_metrics_reports_velocity():
    events = load_fixture_events()
    now = datetime(2026, 1, 19, 12, 0, 0, tzinfo=timezone.utc)

    metrics = compute_event_metrics(events, now=now)
    assert metrics["short_rate"] == pytest.approx(12.0)
    assert metrics["long_rate"] == pytest.approx(2.0)
    assert metrics["velocity"] == pytest.approx(6.0)


def test_compute_velocity_uses_floor():
    assert compute_velocity(1.0, 0.1, floor=0.5) == pytest.approx(2.0)
