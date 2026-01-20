"""Stream metrics helpers for adaptive digest windowing."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Optional


def parse_timestamp(value: str) -> Optional[datetime]:
    """Parse an ISO8601 timestamp with optional Z suffix."""
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, TypeError, AttributeError):
        return None


def filter_events_by_hours(
    events: list[dict[str, Any]],
    now: datetime,
    hours: float,
) -> list[dict[str, Any]]:
    """Filter events that fall within the trailing window."""
    if hours <= 0:
        return []
    cutoff = now - timedelta(hours=hours)
    filtered: list[dict[str, Any]] = []
    for event in events:
        ts = parse_timestamp(str(event.get("timestamp", "")))
        if ts and ts >= cutoff:
            filtered.append(event)
    return filtered


def count_events_in_window(
    events: list[dict[str, Any]],
    now: datetime,
    hours: float,
) -> int:
    """Count events within the trailing window."""
    return len(filter_events_by_hours(events, now, hours))


def rate_per_hour(
    events: list[dict[str, Any]],
    now: datetime,
    hours: float,
) -> float:
    """Compute events per hour over a trailing window."""
    if hours <= 0:
        return 0.0
    return count_events_in_window(events, now, hours) / hours


def compute_velocity(short_rate: float, long_rate: float, floor: float = 0.5) -> float:
    """Compute velocity as short-term rate over long-term rate."""
    return short_rate / max(long_rate, floor)


def compute_event_metrics(
    events: list[dict[str, Any]],
    now: Optional[datetime] = None,
    short_window_hours: float = 0.5,
    mid_window_hours: float = 2.0,
    long_window_hours: float = 12.0,
    rate_floor: float = 0.5,
) -> dict[str, float]:
    """Return rates, counts, and velocity for adaptive windowing."""
    now = now or datetime.now(timezone.utc)

    short_count = count_events_in_window(events, now, short_window_hours)
    mid_count = count_events_in_window(events, now, mid_window_hours)
    long_count = count_events_in_window(events, now, long_window_hours)

    short_rate = short_count / short_window_hours if short_window_hours > 0 else 0.0
    mid_rate = mid_count / mid_window_hours if mid_window_hours > 0 else 0.0
    long_rate = long_count / long_window_hours if long_window_hours > 0 else 0.0

    velocity = compute_velocity(short_rate, long_rate, floor=rate_floor)

    return {
        "short_count": short_count,
        "mid_count": mid_count,
        "long_count": long_count,
        "short_rate": short_rate,
        "mid_rate": mid_rate,
        "long_rate": long_rate,
        "velocity": velocity,
    }
