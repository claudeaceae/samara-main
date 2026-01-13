import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

TESTS_DIR = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, TESTS_DIR)
LIB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "lib"))
sys.path.insert(0, LIB_DIR)

from service_test_utils import load_service_module

CALENDAR_PATH = os.path.join(LIB_DIR, "calendar_analyzer.py")


class _DummyResult:
    def __init__(self, stdout="", returncode=0):
        self.stdout = stdout
        self.returncode = returncode


class _FakeChroma:
    def search(self, query, n_results=3, **kwargs):
        return [
            {
                "text": "Previous discussion about prep",
                "metadata": {"date": "2025-12-01"},
                "distance": 0.1,
            }
        ]


class CalendarAnalyzerTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = Path(self.temp_dir.name) / ".claude-mind"
        (self.mind_path / "state").mkdir(parents=True, exist_ok=True)
        self.env = {
            "SAMARA_MIND_PATH": str(self.mind_path),
            "MIND_PATH": str(self.mind_path),
        }

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_parse_apple_date(self):
        with load_service_module(CALENDAR_PATH, env=self.env) as module:
            analyzer = module.CalendarAnalyzer()
            parsed = analyzer._parse_apple_date("Sunday, December 22, 2025 at 3:00:00 PM")

        self.assertEqual(parsed, datetime(2025, 12, 22, 15, 0, 0))

    def test_parse_apple_date_invalid_returns_none(self):
        with load_service_module(CALENDAR_PATH, env=self.env) as module:
            analyzer = module.CalendarAnalyzer()
            parsed = analyzer._parse_apple_date("not a date")

        self.assertIsNone(parsed)

    def test_fetch_events_filters_excluded_and_claude(self):
        fixed_now = datetime(2025, 12, 22, 12, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        raw_output = (
            "Team Sync|||Sunday, December 22, 2025 at 3:00:00 PM|||"
            "Sunday, December 22, 2025 at 4:00:00 PM|||Office|||Work|||calendar, "
            "Claude Focus|||Sunday, December 22, 2025 at 5:00:00 PM|||"
            "Sunday, December 22, 2025 at 6:00:00 PM|||Office|||Work|||calendar, "
            "Lunch|||Sunday, December 22, 2025 at 12:00:00 PM|||"
            "Sunday, December 22, 2025 at 12:30:00 PM|||Cafe|||Birthdays"
        )

        with load_service_module(CALENDAR_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            with mock.patch.object(module.subprocess, "run", return_value=_DummyResult(raw_output)):
                analyzer = module.CalendarAnalyzer()
                events = analyzer._fetch_events_in_range(0, 2)

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["summary"], "Team Sync")
        self.assertEqual(events[0]["calendar"], "Work")

    def test_fetch_events_handles_empty_and_failed_runs(self):
        fixed_now = datetime(2025, 12, 22, 12, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(CALENDAR_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.CalendarAnalyzer()
            with mock.patch.object(module.subprocess, "run", return_value=_DummyResult("")):
                self.assertEqual(analyzer._fetch_events_in_range(0, 2), [])
            with mock.patch.object(module.subprocess, "run", return_value=_DummyResult("", returncode=1)):
                self.assertEqual(analyzer._fetch_events_in_range(0, 2), [])

    def test_fetch_events_ended_only_skips_future_end(self):
        fixed_now = datetime(2025, 12, 22, 12, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        raw_output = (
            "Team Sync|||Sunday, December 22, 2025 at 3:00:00 PM|||"
            "Sunday, December 22, 2025 at 4:00:00 PM|||Office|||Work"
        )

        with load_service_module(CALENDAR_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.CalendarAnalyzer()
            with mock.patch.object(module.subprocess, "run", return_value=_DummyResult(raw_output)):
                events = analyzer._fetch_events_in_range(0, 4, ended_only=True)

        self.assertEqual(events, [])

    def test_get_upcoming_events_adds_minutes_and_context(self):
        fixed_now = datetime(2025, 12, 22, 9, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        event = {
            "summary": "Project Review",
            "start": fixed_now + timedelta(minutes=45),
            "end": fixed_now + timedelta(minutes=75),
        }

        with load_service_module(CALENDAR_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.CalendarAnalyzer()
            analyzer._fetch_events_in_range = lambda *args, **kwargs: [event]
            analyzer.chroma = _FakeChroma()
            upcoming = analyzer.get_upcoming_events(hours=1)

        self.assertEqual(upcoming[0]["minutes_until"], 45)
        self.assertIn("2025-12-01", upcoming[0]["relevance_context"])

    def test_get_recently_ended_sets_minutes_since(self):
        fixed_now = datetime(2025, 12, 22, 11, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        event = {
            "summary": "Standup",
            "start": fixed_now - timedelta(minutes=45),
            "end": fixed_now - timedelta(minutes=30),
        }

        with load_service_module(CALENDAR_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.CalendarAnalyzer()
            analyzer._fetch_events_in_range = lambda *args, **kwargs: [event]
            recent = analyzer.get_recently_ended(hours=1)

        self.assertEqual(recent[0]["minutes_since_end"], 30)

    def test_check_for_triggers_uses_confidence_rules(self):
        fixed_now = datetime(2025, 12, 22, 9, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        upcoming = [{"summary": "Prep", "minutes_until": 20, "relevance_context": "ctx"}]
        recent = [{
            "summary": "Retro",
            "minutes_since_end": 20,
            "start": fixed_now - timedelta(minutes=90),
            "end": fixed_now - timedelta(minutes=20),
        }]

        with load_service_module(CALENDAR_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.CalendarAnalyzer()
            analyzer.get_upcoming_events = lambda hours=1: upcoming
            analyzer.get_recently_ended = lambda hours=1: recent
            triggers = analyzer.check_for_triggers()

        upcoming_trigger = next(t for t in triggers if t["type"] == "upcoming_event")
        recent_trigger = next(t for t in triggers if t["type"] == "recently_ended")

        self.assertEqual(upcoming_trigger["confidence"], 0.7)
        self.assertEqual(recent_trigger["confidence"], 0.6)

    def test_get_free_periods_returns_gap(self):
        fixed_now = datetime(2025, 12, 22, 9, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        events = [
            {
                "summary": "Meeting",
                "start": fixed_now + timedelta(hours=2),
                "end": fixed_now + timedelta(hours=3),
            }
        ]

        with load_service_module(CALENDAR_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.CalendarAnalyzer()
            analyzer._fetch_events_in_range = lambda *args, **kwargs: events
            free = analyzer.get_free_periods(hours=4)

        self.assertEqual(free[0]["duration_hours"], 2.0)
        self.assertIn("Free until Meeting", free[0]["description"])

    def test_get_free_periods_returns_full_when_no_events(self):
        fixed_now = datetime(2025, 12, 22, 9, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(CALENDAR_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.CalendarAnalyzer()
            analyzer._fetch_events_in_range = lambda *args, **kwargs: []
            free = analyzer.get_free_periods(hours=3)

        self.assertEqual(free[0]["duration_hours"], 3)

    def test_get_calendar_summary_includes_sections(self):
        fixed_now = datetime(2025, 12, 22, 9, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        upcoming = [{"summary": "Prep", "minutes_until": 30}]
        recent = [{"summary": "Retro", "minutes_since_end": 20}]
        free = [{"duration_hours": 2.0}]

        with load_service_module(CALENDAR_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.CalendarAnalyzer()
            analyzer.get_upcoming_events = lambda hours=4: upcoming
            analyzer.get_recently_ended = lambda hours=2: recent
            analyzer.get_free_periods = lambda hours=4: free
            summary = analyzer.get_calendar_summary()

        self.assertIn("Upcoming", summary)
        self.assertIn("Recently ended", summary)
        self.assertIn("Free time", summary)

if __name__ == "__main__":
    unittest.main()
