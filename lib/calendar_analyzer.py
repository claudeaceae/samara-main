#!/usr/bin/env python3
"""
Calendar Analyzer for Claude's temporal awareness system.

Provides calendar awareness for proactive engagement:
- Upcoming events (prep context)
- Recently ended events (follow-up)
- Recurring event detection
- Relevance scoring

Uses AppleScript to access macOS Calendar.

Usage:
    from calendar_analyzer import CalendarAnalyzer

    analyzer = CalendarAnalyzer()
    upcoming = analyzer.get_upcoming_events(hours=2)
    recent = analyzer.get_recently_ended(hours=1)
"""

import os
import re
import json
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional
from mind_paths import get_mind_path

# Try to import Chroma for semantic context
try:
    from chroma_helper import MemoryIndex
    CHROMA_AVAILABLE = True
except ImportError:
    CHROMA_AVAILABLE = False

MIND_PATH = get_mind_path()
STATE_PATH = MIND_PATH / "state"


class CalendarAnalyzer:
    """Analyzes calendar events for proactive engagement."""

    def __init__(self):
        self.chroma = MemoryIndex() if CHROMA_AVAILABLE else None
        STATE_PATH.mkdir(parents=True, exist_ok=True)

        # Calendars to exclude (Claude's own events, system calendars)
        self.excluded_calendars = {
            "Claude",
            "Siri Suggestions",
            "Birthdays",
            "US Holidays",
            "Scheduled Reminders"
        }

    def get_upcoming_events(self, hours: int = 2, include_attendees: bool = False) -> list:
        """
        Get events starting in the next N hours.

        Returns list of event dicts with:
            - summary: Event title
            - start: Start datetime
            - end: End datetime
            - location: Location if any
            - calendar: Which calendar
            - minutes_until: Minutes until start
            - relevance_context: Related past conversations (if Chroma available)
            - attendees: List of attendees (only if include_attendees=True)
        """
        events = self._fetch_events_in_range(
            start_offset_hours=0,
            end_offset_hours=hours,
            include_attendees=include_attendees
        )

        # Add minutes_until and relevance context
        now = datetime.now()
        for event in events:
            if event.get("start"):
                delta = event["start"] - now
                event["minutes_until"] = int(delta.total_seconds() / 60)

            # Get related context from Chroma
            if self.chroma and event.get("summary"):
                event["relevance_context"] = self._get_event_context(event)

        return events

    def get_recently_ended(self, hours: int = 1, include_attendees: bool = False) -> list:
        """
        Get events that ended in the last N hours.

        For follow-up prompts like "How did the meeting go?"
        """
        events = self._fetch_events_in_range(
            start_offset_hours=-hours * 2,  # Look back further for long events
            end_offset_hours=0,
            ended_only=True,
            include_attendees=include_attendees
        )

        now = datetime.now()
        for event in events:
            if event.get("end"):
                delta = now - event["end"]
                event["minutes_since_end"] = int(delta.total_seconds() / 60)

        return events

    def get_free_periods(self, hours: int = 8) -> list:
        """
        Find free periods in the next N hours.

        Useful for knowing when the collaborator has unscheduled time.
        """
        events = self._fetch_events_in_range(
            start_offset_hours=0,
            end_offset_hours=hours
        )

        if not events:
            return [{
                "start": datetime.now(),
                "end": datetime.now() + timedelta(hours=hours),
                "duration_hours": hours,
                "description": f"Free for next {hours} hours"
            }]

        # Sort by start time
        events.sort(key=lambda e: e.get("start", datetime.max))

        free_periods = []
        current_time = datetime.now()

        for event in events:
            event_start = event.get("start")
            if event_start and event_start > current_time:
                gap = (event_start - current_time).total_seconds() / 3600
                if gap >= 0.5:  # At least 30 min gap
                    free_periods.append({
                        "start": current_time,
                        "end": event_start,
                        "duration_hours": round(gap, 1),
                        "description": f"Free until {event.get('summary', 'next event')}"
                    })

            # Move current time past this event
            event_end = event.get("end")
            if event_end and event_end > current_time:
                current_time = event_end

        return free_periods

    def get_calendar_summary(self) -> str:
        """
        Generate a human-readable calendar summary.

        Suitable for inclusion in wake cycle context.
        """
        lines = ["## Calendar Context\n"]

        # Upcoming events (next 4 hours)
        upcoming = self.get_upcoming_events(hours=4)
        if upcoming:
            lines.append("**Upcoming:**")
            for event in upcoming[:5]:
                mins = event.get("minutes_until", 0)
                if mins < 60:
                    time_str = f"in {mins} min"
                else:
                    time_str = f"in {mins // 60}h {mins % 60}m"
                lines.append(f"- {event.get('summary', 'Event')} ({time_str})")

                # Add context if available
                context = event.get("relevance_context")
                if context:
                    lines.append(f"  Context: {context[:100]}...")
        else:
            lines.append("**Upcoming:** No events in next 4 hours")

        # Recently ended (last 2 hours)
        recent = self.get_recently_ended(hours=2)
        if recent:
            lines.append("\n**Recently ended:**")
            for event in recent[:3]:
                mins = event.get("minutes_since_end", 0)
                lines.append(f"- {event.get('summary', 'Event')} (ended {mins} min ago)")

        # Free time
        free = self.get_free_periods(hours=4)
        if free and free[0].get("duration_hours", 0) >= 1:
            period = free[0]
            lines.append(f"\n**Free time:** {period['duration_hours']}h available")

        return "\n".join(lines)

    def check_for_triggers(self) -> list:
        """
        Check for calendar-based triggers for proactive engagement.

        Returns list of trigger events with confidence scores.
        """
        triggers = []
        now = datetime.now()

        # Check for upcoming events (15-60 min away)
        upcoming = self.get_upcoming_events(hours=1)
        for event in upcoming:
            mins = event.get("minutes_until", 0)
            if 15 <= mins <= 60:
                confidence = 0.7 if event.get("relevance_context") else 0.5
                triggers.append({
                    "type": "upcoming_event",
                    "event": event.get("summary"),
                    "minutes_until": mins,
                    "confidence": confidence,
                    "suggested_action": f"Offer context for '{event.get('summary')}'"
                })

        # Check for recently ended events (15-45 min ago)
        recent = self.get_recently_ended(hours=1)
        for event in recent:
            mins = event.get("minutes_since_end", 0)
            if 15 <= mins <= 45:
                # Higher confidence for longer events
                event_duration = 60  # Default assumption
                if event.get("start") and event.get("end"):
                    event_duration = (event["end"] - event["start"]).total_seconds() / 60

                confidence = 0.6 if event_duration >= 30 else 0.4
                triggers.append({
                    "type": "recently_ended",
                    "event": event.get("summary"),
                    "minutes_since": mins,
                    "confidence": confidence,
                    "suggested_action": f"Ask how '{event.get('summary')}' went"
                })

        return triggers

    def _fetch_events_in_range(self, start_offset_hours: int, end_offset_hours: int,
                                ended_only: bool = False,
                                include_attendees: bool = False) -> list:
        """
        Fetch calendar events in a time range via AppleScript.

        Args:
            start_offset_hours: Hours from now for range start (negative = past)
            end_offset_hours: Hours from now for range end
            ended_only: Only return events that have already ended
            include_attendees: Fetch attendee data (slower, requires 30s timeout)
        """
        now = datetime.now()
        start_time = now + timedelta(hours=start_offset_hours)
        end_time = now + timedelta(hours=end_offset_hours)

        # Build excluded calendars as AppleScript set
        excluded_list = ", ".join(f'"{cal}"' for cal in self.excluded_calendars)

        # Conditionally include attendee block
        if include_attendees:
            attendee_block = '''
                        -- Build attendee list (email:name;email:name;...)
                        set attendeeList to ""
                        try
                            set evtAttendees to attendees of evt
                            repeat with att in evtAttendees
                                try
                                    set attEmail to email of att
                                    set attName to ""
                                    try
                                        set attName to display name of att
                                    end try
                                    set attendeeList to attendeeList & attEmail & ":" & attName & ";"
                                end try
                            end repeat
                        end try'''
        else:
            attendee_block = '''
                        set attendeeList to ""'''

        # AppleScript to get events
        script = f'''
        tell application "Calendar"
            set startDate to current date
            set hours of startDate to {start_time.hour}
            set minutes of startDate to {start_time.minute}
            set seconds of startDate to 0

            set endDate to current date
            set hours of endDate to {end_time.hour}
            set minutes of endDate to {end_time.minute}
            set seconds of endDate to 0

            -- Handle day offset
            set startDate to startDate + ({start_offset_hours * 3600})
            set endDate to endDate + ({end_offset_hours * 3600})

            -- Excluded calendars (filtered in AppleScript for performance)
            set excludedCals to {{{excluded_list}}}

            set eventList to {{}}
            repeat with cal in calendars
                try
                    set calName to name of cal

                    -- Skip excluded calendars
                    if excludedCals contains calName then
                        -- skip this calendar
                    else
                        set calEvents to (every event of cal whose start date >= startDate and start date < endDate)
                        repeat with evt in calEvents
{attendee_block}

                            set evtInfo to summary of evt & "|||" & (start date of evt as string) & "|||" & (end date of evt as string) & "|||" & (location of evt as string) & "|||" & calName & "|||" & attendeeList
                            set end of eventList to evtInfo
                        end repeat
                    end if
                end try
            end repeat
            return eventList
        end tell
        '''

        # Longer timeout when fetching attendees (30s vs 10s)
        timeout_seconds = 30 if include_attendees else 10

        try:
            result = subprocess.run(
                ["osascript", "-e", script],
                capture_output=True,
                text=True,
                timeout=timeout_seconds
            )

            if result.returncode != 0:
                return []

            # Parse the output
            events = []
            raw_output = result.stdout.strip()

            if not raw_output:
                return []

            # Split events - AppleScript list items are separated by ", " but
            # date strings include commas, so we stitch tokens until we have
            # enough field separators for a full event.
            tokens = raw_output.split(", ")
            event_strings = []
            current_parts = []
            for token in tokens:
                current_parts.append(token)
                joined = ", ".join(current_parts)
                # An event has at least 4 separators: summary/start/end/location/calendar.
                if joined.count("|||") >= 4:
                    event_strings.append(joined)
                    current_parts = []
            if current_parts:
                joined = ", ".join(current_parts)
                if joined.count("|||") >= 4:
                    event_strings.append(joined)

            for event_str in event_strings:
                if not event_str.strip():
                    continue

                if "|||" not in event_str:
                    continue

                parts = event_str.split("|||")
                if len(parts) < 5:
                    continue

                summary = parts[0].strip()
                calendar = parts[4].strip() if len(parts) > 4 else "Unknown"
                attendees_raw = parts[5].strip() if len(parts) > 5 else ""

                # Skip excluded calendars
                if calendar in self.excluded_calendars:
                    continue

                # Skip Claude's own events
                if summary.startswith("Claude "):
                    continue

                # Parse dates
                start_date = self._parse_apple_date(parts[1])
                end_date = self._parse_apple_date(parts[2])

                if ended_only and end_date:
                    if end_date > now:
                        continue  # Skip events that haven't ended

                # Parse attendees (format: email:name;email:name;)
                attendees = []
                if attendees_raw:
                    for att_str in attendees_raw.split(";"):
                        if ":" in att_str:
                            email, name = att_str.split(":", 1)
                            if email.strip():
                                attendees.append({
                                    "email": email.strip(),
                                    "name": name.strip() if name.strip() else None
                                })

                events.append({
                    "summary": summary,
                    "start": start_date,
                    "end": end_date,
                    "location": parts[3] if len(parts) > 3 else None,
                    "calendar": calendar,
                    "attendees": attendees
                })

            return events

        except subprocess.TimeoutExpired:
            return []
        except Exception as e:
            return []

    def _parse_apple_date(self, date_str: str) -> Optional[datetime]:
        """Parse AppleScript date format."""
        # Format: "Sunday, December 22, 2025 at 3:00:00 PM"
        try:
            # Remove "at" and clean up
            date_str = date_str.replace(" at ", " ").strip()

            # Try common formats
            for fmt in [
                "%A, %B %d, %Y %I:%M:%S %p",
                "%A, %B %d, %Y %H:%M:%S",
                "%B %d, %Y %I:%M:%S %p",
                "%B %d, %Y %H:%M:%S"
            ]:
                try:
                    return datetime.strptime(date_str, fmt)
                except ValueError:
                    continue

            return None
        except:
            return None

    def _get_event_context(self, event: dict) -> Optional[str]:
        """Get relevant past context for an event from Chroma."""
        if not self.chroma:
            return None

        summary = event.get("summary", "")
        if not summary:
            return None

        # Search for related past conversations
        results = self.chroma.search(summary, n_results=3)

        if not results:
            return None

        # Return the most relevant snippet
        best = results[0]
        text = best.get("text", "")[:200]
        date = best.get("metadata", {}).get("date", "unknown")

        return f"[{date}] {text}"

    def resolve_attendees(self, attendees: list) -> list:
        """
        Resolve attendee emails/names to person profiles.

        Args:
            attendees: List of dicts with 'email' and optional 'name' keys

        Returns:
            List of enriched attendee dicts with:
                - email: Original email
                - name: Display name (from calendar or profile)
                - has_profile: Whether a profile exists
                - profile_path: Path to profile.md if exists
                - profile_name: Directory name in memory/people/
        """
        people_dir = MIND_PATH / "memory" / "people"

        if not people_dir.exists():
            return attendees

        # Build lookup of existing profiles
        profile_lookup = {}
        for person_dir in people_dir.iterdir():
            if not person_dir.is_dir() or person_dir.name.startswith("_"):
                continue

            profile_path = person_dir / "profile.md"
            if not profile_path.exists():
                continue

            # Read profile to look for email/contact info
            try:
                content = profile_path.read_text()
                profile_lookup[person_dir.name.lower()] = {
                    "path": str(profile_path),
                    "name": person_dir.name,
                    "content": content.lower()
                }
            except:
                continue

        # Resolve each attendee
        resolved = []
        for att in attendees:
            email = att.get("email", "").lower()
            name = att.get("name", "")

            # Try to find matching profile
            matched_profile = None

            # 1. Check if email appears in any profile
            for profile_name, profile_info in profile_lookup.items():
                if email and email in profile_info["content"]:
                    matched_profile = profile_info
                    break

            # 2. Check if name matches a profile directory
            if not matched_profile and name:
                name_lower = name.lower().replace(" ", "")
                for profile_name, profile_info in profile_lookup.items():
                    if profile_name.replace(" ", "") == name_lower:
                        matched_profile = profile_info
                        break
                    # Also check first name
                    first_name = name.split()[0].lower() if name else ""
                    if first_name and profile_name == first_name:
                        matched_profile = profile_info
                        break

            resolved.append({
                "email": att.get("email"),
                "name": name or (matched_profile["name"].title() if matched_profile else None),
                "has_profile": matched_profile is not None,
                "profile_path": matched_profile["path"] if matched_profile else None,
                "profile_name": matched_profile["name"] if matched_profile else None
            })

        return resolved

    def get_meetings_needing_prep(self, minutes_before: int = 15, window: int = 10) -> list:
        """
        Get meetings that need prep context (starting in minutes_before ± window).

        Returns events with enriched attendee data for meeting prep sense events.
        """
        # Get events starting soon (with attendees for meeting prep)
        upcoming = self.get_upcoming_events(hours=1, include_attendees=True)

        meetings = []
        for event in upcoming:
            mins = event.get("minutes_until", 0)
            # Check if within the prep window (e.g., 10-20 min before for 15 min lead time)
            lower = minutes_before - window
            upper = minutes_before + window
            if lower <= mins <= upper:
                # Resolve attendees to profiles
                attendees = event.get("attendees", [])
                resolved_attendees = self.resolve_attendees(attendees)

                meetings.append({
                    "event_title": event.get("summary"),
                    "start_time": event.get("start"),
                    "minutes_until": mins,
                    "location": event.get("location"),
                    "calendar": event.get("calendar"),
                    "attendees": resolved_attendees
                })

        return meetings

    def get_meetings_needing_debrief(self, minutes_after: int = 15, window: int = 15) -> list:
        """
        Get meetings that need debrief (ended minutes_after ± window ago).

        Returns events with attendee data for debrief sense events.
        """
        # Get recently ended events (with attendees for meeting debrief)
        recent = self.get_recently_ended(hours=1, include_attendees=True)

        meetings = []
        for event in recent:
            mins = event.get("minutes_since_end", 0)
            lower = minutes_after - window
            upper = minutes_after + window
            if lower <= mins <= upper:
                # Resolve attendees
                attendees = event.get("attendees", [])
                resolved_attendees = self.resolve_attendees(attendees)

                # Calculate duration
                duration_min = None
                if event.get("start") and event.get("end"):
                    duration_min = int((event["end"] - event["start"]).total_seconds() / 60)

                meetings.append({
                    "event_title": event.get("summary"),
                    "ended_at": event.get("end"),
                    "minutes_since_end": mins,
                    "duration_min": duration_min,
                    "location": event.get("location"),
                    "calendar": event.get("calendar"),
                    "attendees": resolved_attendees
                })

        return meetings


def main():
    """CLI interface for calendar analyzer."""
    import sys

    if len(sys.argv) < 2:
        print("Usage: calendar_analyzer.py <command>")
        print("Commands:")
        print("  upcoming [hours]  - Get upcoming events (with attendees)")
        print("  recent [hours]    - Get recently ended events (with attendees)")
        print("  free [hours]      - Find free periods")
        print("  summary           - Get calendar summary")
        print("  triggers          - Check for engagement triggers")
        print("  prep              - Get meetings needing prep (10-20 min out)")
        print("  debrief           - Get meetings needing debrief (ended 0-30 min ago)")
        sys.exit(1)

    command = sys.argv[1]
    analyzer = CalendarAnalyzer()

    if command == "upcoming":
        hours = int(sys.argv[2]) if len(sys.argv) > 2 else 2
        events = analyzer.get_upcoming_events(hours)
        print(json.dumps(events, indent=2, default=str))

    elif command == "recent":
        hours = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        events = analyzer.get_recently_ended(hours)
        print(json.dumps(events, indent=2, default=str))

    elif command == "free":
        hours = int(sys.argv[2]) if len(sys.argv) > 2 else 8
        periods = analyzer.get_free_periods(hours)
        print(json.dumps(periods, indent=2, default=str))

    elif command == "summary":
        print(analyzer.get_calendar_summary())

    elif command == "triggers":
        triggers = analyzer.check_for_triggers()
        print(json.dumps(triggers, indent=2, default=str))

    elif command == "prep":
        meetings = analyzer.get_meetings_needing_prep()
        print(json.dumps(meetings, indent=2, default=str))

    elif command == "debrief":
        meetings = analyzer.get_meetings_needing_debrief()
        print(json.dumps(meetings, indent=2, default=str))

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
