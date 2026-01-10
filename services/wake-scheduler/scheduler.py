#!/usr/bin/env python3
"""
Wake Scheduler Service

Calculates optimal next wake time based on:
- Base schedule (9, 14, 20)
- Calendar proximity
- Trigger confidence
- Activity patterns
- Pending events

Usage:
    python scheduler.py check     # Check if should wake now
    python scheduler.py next      # Get next scheduled wake time
    python scheduler.py status    # Show scheduler status
"""

import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, Tuple

MIND_DIR = Path.home() / ".claude-mind"
STATE_DIR = MIND_DIR / "state"
TRIGGERS_FILE = STATE_DIR / "triggers" / "triggers.json"
QUEUE_FILE = STATE_DIR / "proactive-queue" / "queue.json"
CALENDAR_CACHE = STATE_DIR / "calendar-cache.json"
SCHEDULER_STATE = STATE_DIR / "scheduler-state.json"

# Base wake times (hour of day)
BASE_WAKE_HOURS = [9, 14, 20]

# Minimum interval between wakes (minutes)
MIN_WAKE_INTERVAL = 60

# Confidence threshold for early wake
EARLY_WAKE_THRESHOLD = 0.7


class WakeScheduler:
    def __init__(self):
        self.state = self._load_state()

    def _load_state(self) -> dict:
        """Load scheduler state from disk."""
        if SCHEDULER_STATE.exists():
            try:
                return json.loads(SCHEDULER_STATE.read_text())
            except:
                pass
        return {
            "last_wake": None,
            "last_wake_type": None,
            "wake_count_today": 0,
            "date": datetime.now().strftime("%Y-%m-%d")
        }

    def _save_state(self):
        """Save scheduler state to disk."""
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        SCHEDULER_STATE.write_text(json.dumps(self.state, indent=2))

    def _reset_daily_counts(self):
        """Reset daily counters if new day."""
        today = datetime.now().strftime("%Y-%m-%d")
        if self.state.get("date") != today:
            self.state["date"] = today
            self.state["wake_count_today"] = 0
            self._save_state()

    def _get_pending_triggers(self) -> list:
        """Get pending triggers from ContextTriggers."""
        if not TRIGGERS_FILE.exists():
            return []
        try:
            data = json.loads(TRIGGERS_FILE.read_text())
            return data if isinstance(data, list) else []
        except:
            return []

    def _get_queue_status(self) -> dict:
        """Get proactive queue status."""
        if not QUEUE_FILE.exists():
            return {"pending": 0, "high_priority": 0}
        try:
            queue = json.loads(QUEUE_FILE.read_text())
            pending = [m for m in queue if not m.get("sentAt")]
            high_priority = [m for m in pending if m.get("priority") in ["high", "time_sensitive"]]
            return {"pending": len(pending), "high_priority": len(high_priority)}
        except:
            return {"pending": 0, "high_priority": 0}

    def _get_calendar_events(self) -> list:
        """Get upcoming calendar events."""
        if not CALENDAR_CACHE.exists():
            return []
        try:
            data = json.loads(CALENDAR_CACHE.read_text())
            events = data.get("events", [])
            now = datetime.now()
            # Filter to next 2 hours
            upcoming = []
            for event in events:
                try:
                    start = datetime.fromisoformat(event.get("start", "").replace("Z", "+00:00"))
                    if now < start < now + timedelta(hours=2):
                        upcoming.append(event)
                except:
                    pass
            return upcoming
        except:
            return []

    def _minutes_since_last_wake(self) -> Optional[float]:
        """Get minutes since last wake, or None if never woke."""
        last_wake = self.state.get("last_wake")
        if not last_wake:
            return None
        try:
            last = datetime.fromisoformat(last_wake)
            return (datetime.now() - last).total_seconds() / 60
        except:
            return None

    def _get_next_base_wake(self) -> datetime:
        """Get next scheduled wake time from base schedule."""
        now = datetime.now()
        today = now.date()

        for hour in BASE_WAKE_HOURS:
            wake_time = datetime.combine(today, datetime.min.time().replace(hour=hour))
            if wake_time > now:
                return wake_time

        # Next day's first wake
        tomorrow = today + timedelta(days=1)
        return datetime.combine(tomorrow, datetime.min.time().replace(hour=BASE_WAKE_HOURS[0]))

    def _calculate_wake_confidence(self) -> Tuple[float, str]:
        """
        Calculate confidence that we should wake now.
        Returns (confidence 0-1, reason).
        """
        reasons = []
        confidence = 0.0

        # Check pending high-priority items
        queue_status = self._get_queue_status()
        if queue_status["high_priority"] > 0:
            confidence += 0.4
            reasons.append(f"{queue_status['high_priority']} high-priority messages")

        # Check calendar proximity
        events = self._get_calendar_events()
        if events:
            closest = events[0]
            try:
                start = datetime.fromisoformat(closest.get("start", "").replace("Z", "+00:00"))
                minutes_until = (start - datetime.now()).total_seconds() / 60
                if minutes_until < 30:
                    confidence += 0.5
                    reasons.append(f"Event in {int(minutes_until)} minutes")
                elif minutes_until < 60:
                    confidence += 0.3
                    reasons.append(f"Event in {int(minutes_until)} minutes")
            except:
                pass

        # Check time since last wake
        minutes = self._minutes_since_last_wake()
        if minutes is not None and minutes > 180:  # 3 hours
            confidence += 0.2
            reasons.append(f"Last wake {int(minutes)} minutes ago")

        # Check pending triggers count
        triggers = self._get_pending_triggers()
        if len(triggers) >= 3:
            confidence += 0.3
            reasons.append(f"{len(triggers)} pending triggers")

        reason = "; ".join(reasons) if reasons else "No urgent items"
        return min(confidence, 1.0), reason

    def should_wake_now(self) -> Tuple[bool, str, str]:
        """
        Determine if we should wake now.
        Returns (should_wake, wake_type, reason).

        wake_type is one of:
        - "full": Full wake cycle
        - "light": Quick check-in
        - "none": No wake needed
        """
        self._reset_daily_counts()

        # Check minimum interval
        minutes = self._minutes_since_last_wake()
        if minutes is not None and minutes < MIN_WAKE_INTERVAL:
            return False, "none", f"Too soon since last wake ({int(minutes)} min ago)"

        # Check if we're at a base wake time (±15 min)
        now = datetime.now()
        for hour in BASE_WAKE_HOURS:
            wake_time = datetime.combine(now.date(), datetime.min.time().replace(hour=hour))
            diff = abs((now - wake_time).total_seconds() / 60)
            if diff < 15:
                return True, "full", f"Scheduled {hour}:00 wake"

        # Check confidence for early/light wake
        confidence, reason = self._calculate_wake_confidence()

        if confidence >= EARLY_WAKE_THRESHOLD:
            return True, "full", f"High confidence ({confidence:.0%}): {reason}"
        elif confidence >= 0.4:
            return True, "light", f"Moderate confidence ({confidence:.0%}): {reason}"

        return False, "none", f"Low confidence ({confidence:.0%}): {reason}"

    def get_next_wake(self) -> dict:
        """Get information about next scheduled wake."""
        next_base = self._get_next_base_wake()
        confidence, reason = self._calculate_wake_confidence()

        return {
            "next_scheduled": next_base.isoformat(),
            "minutes_until": int((next_base - datetime.now()).total_seconds() / 60),
            "current_confidence": confidence,
            "confidence_reason": reason,
            "may_wake_early": confidence >= 0.4
        }

    def record_wake(self, wake_type: str):
        """Record that a wake occurred."""
        self._reset_daily_counts()
        self.state["last_wake"] = datetime.now().isoformat()
        self.state["last_wake_type"] = wake_type
        self.state["wake_count_today"] = self.state.get("wake_count_today", 0) + 1
        self._save_state()

    def get_status(self) -> dict:
        """Get full scheduler status."""
        self._reset_daily_counts()
        should_wake, wake_type, reason = self.should_wake_now()
        next_info = self.get_next_wake()

        return {
            "should_wake": should_wake,
            "wake_type": wake_type,
            "reason": reason,
            "last_wake": self.state.get("last_wake"),
            "last_wake_type": self.state.get("last_wake_type"),
            "wake_count_today": self.state.get("wake_count_today", 0),
            "next_scheduled": next_info["next_scheduled"],
            "minutes_until_next": next_info["minutes_until"],
            "queue_status": self._get_queue_status(),
            "upcoming_events": len(self._get_calendar_events())
        }


def main():
    if len(sys.argv) < 2:
        print("Usage: scheduler.py [check|next|status|record]")
        sys.exit(1)

    scheduler = WakeScheduler()
    command = sys.argv[1]

    if command == "check":
        should_wake, wake_type, reason = scheduler.should_wake_now()
        result = {
            "should_wake": should_wake,
            "type": wake_type,
            "reason": reason
        }
        print(json.dumps(result))

    elif command == "next":
        result = scheduler.get_next_wake()
        print(json.dumps(result))

    elif command == "status":
        result = scheduler.get_status()
        print(json.dumps(result, indent=2))

    elif command == "record":
        wake_type = sys.argv[2] if len(sys.argv) > 2 else "full"
        scheduler.record_wake(wake_type)
        print(json.dumps({"recorded": True, "type": wake_type}))

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
