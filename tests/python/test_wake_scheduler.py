import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

from service_test_utils import load_service_module


SCHEDULER_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "services",
    "wake-scheduler",
    "scheduler.py",
)


class WakeSchedulerTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = os.path.join(self.temp_dir.name, ".claude-mind")
        os.makedirs(self.mind_path, exist_ok=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_queue_status_counts_pending_and_high_priority(self):
        queue_dir = Path(self.mind_path) / "state" / "proactive-queue"
        queue_dir.mkdir(parents=True, exist_ok=True)
        queue_file = queue_dir / "queue.json"
        queue_file.write_text(json.dumps([
            {"content": "A", "priority": "high", "sentAt": None},
            {"content": "B", "priority": "normal", "sentAt": None},
            {"content": "C", "priority": "time_sensitive", "sentAt": None},
            {"content": "D", "priority": "high", "sentAt": "2025-01-01T00:00:00"},
        ]))

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            instance = scheduler.WakeScheduler()
            status = instance._get_queue_status()

        self.assertEqual(status["pending"], 3)
        self.assertEqual(status["high_priority"], 2)

    def test_should_wake_now_respects_min_interval(self):
        fixed_now = datetime(2025, 1, 1, 9, 5, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            scheduler.datetime = FixedDatetime
            instance = scheduler.WakeScheduler()
            instance.state["last_wake"] = (fixed_now - timedelta(minutes=30)).isoformat()

            should_wake, wake_type, reason = instance.should_wake_now()

        self.assertFalse(should_wake)
        self.assertEqual(wake_type, "none")
        self.assertIn("Too soon since last wake", reason)

    def test_should_wake_now_matches_base_schedule(self):
        fixed_now = datetime(2025, 1, 1, 14, 5, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            scheduler.datetime = FixedDatetime
            instance = scheduler.WakeScheduler()
            should_wake, wake_type, reason = instance.should_wake_now()

        self.assertTrue(should_wake)
        self.assertEqual(wake_type, "full")
        self.assertIn("Scheduled 14:00 wake", reason)

    def test_record_wake_updates_state_file(self):
        fixed_now = datetime(2025, 1, 2, 10, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            scheduler.datetime = FixedDatetime
            instance = scheduler.WakeScheduler()
            instance.record_wake("light")

            state_path = Path(self.mind_path) / "state" / "scheduler-state.json"
            state = json.loads(state_path.read_text())

        self.assertEqual(state["last_wake_type"], "light")
        self.assertEqual(state["last_wake"], fixed_now.isoformat())
        self.assertEqual(state["wake_count_today"], 1)

    def test_calculate_wake_confidence_high(self):
        fixed_now = datetime(2025, 1, 3, 11, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        queue_dir = Path(self.mind_path) / "state" / "proactive-queue"
        queue_dir.mkdir(parents=True, exist_ok=True)
        (queue_dir / "queue.json").write_text(
            json.dumps([
                {"content": "A", "priority": "high", "sentAt": None},
                {"content": "B", "priority": "time_sensitive", "sentAt": None},
            ])
        )
        triggers_dir = Path(self.mind_path) / "state" / "triggers"
        triggers_dir.mkdir(parents=True, exist_ok=True)
        (triggers_dir / "triggers.json").write_text(json.dumps([{"id": 1}, {"id": 2}, {"id": 3}]))
        calendar_path = Path(self.mind_path) / "state" / "calendar-cache.json"
        calendar_path.write_text(
            json.dumps(
                {
                    "events": [
                        {"start": (fixed_now + timedelta(minutes=20)).isoformat()}
                    ]
                }
            )
        )

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            scheduler.datetime = FixedDatetime
            instance = scheduler.WakeScheduler()
            instance.state["last_wake"] = (fixed_now - timedelta(hours=4)).isoformat()
            confidence, reason = instance._calculate_wake_confidence()

        self.assertGreaterEqual(confidence, 1.0)
        self.assertIn("high-priority", reason)
        self.assertIn("Event in", reason)
        self.assertIn("Last wake", reason)
        self.assertIn("pending triggers", reason)

    def test_should_wake_now_high_confidence(self):
        fixed_now = datetime(2025, 1, 4, 11, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        queue_dir = Path(self.mind_path) / "state" / "proactive-queue"
        queue_dir.mkdir(parents=True, exist_ok=True)
        (queue_dir / "queue.json").write_text(
            json.dumps([{"content": "A", "priority": "high", "sentAt": None}])
        )
        calendar_path = Path(self.mind_path) / "state" / "calendar-cache.json"
        calendar_path.write_text(
            json.dumps({"events": [{"start": (fixed_now + timedelta(minutes=25)).isoformat()}]})
        )

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            scheduler.datetime = FixedDatetime
            instance = scheduler.WakeScheduler()
            instance.state["last_wake"] = (fixed_now - timedelta(hours=4)).isoformat()
            should_wake, wake_type, reason = instance.should_wake_now()

        self.assertTrue(should_wake)
        self.assertEqual(wake_type, "full")
        self.assertIn("High confidence", reason)

    def test_should_wake_now_moderate_confidence(self):
        fixed_now = datetime(2025, 1, 4, 11, 30, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        queue_dir = Path(self.mind_path) / "state" / "proactive-queue"
        queue_dir.mkdir(parents=True, exist_ok=True)
        (queue_dir / "queue.json").write_text(
            json.dumps([{"content": "A", "priority": "high", "sentAt": None}])
        )

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            scheduler.datetime = FixedDatetime
            instance = scheduler.WakeScheduler()
            should_wake, wake_type, reason = instance.should_wake_now()

        self.assertTrue(should_wake)
        self.assertEqual(wake_type, "light")
        self.assertIn("Moderate confidence", reason)

    def test_get_next_base_wake_rolls_to_tomorrow(self):
        fixed_now = datetime(2025, 1, 5, 21, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            scheduler.datetime = FixedDatetime
            instance = scheduler.WakeScheduler()
            next_wake = instance._get_next_base_wake()

        self.assertEqual(next_wake.hour, 9)
        self.assertEqual(next_wake.date(), (fixed_now + timedelta(days=1)).date())

    def test_get_calendar_events_filters_window(self):
        fixed_now = datetime(2025, 1, 6, 9, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        calendar_path = Path(self.mind_path) / "state" / "calendar-cache.json"
        calendar_path.parent.mkdir(parents=True, exist_ok=True)
        calendar_path.write_text(
            json.dumps(
                {
                    "events": [
                        {"start": (fixed_now + timedelta(hours=1)).isoformat()},
                        {"start": (fixed_now + timedelta(hours=3)).isoformat()},
                    ]
                }
            )
        )

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            scheduler.datetime = FixedDatetime
            instance = scheduler.WakeScheduler()
            events = instance._get_calendar_events()

        self.assertEqual(len(events), 1)

    def test_reset_daily_counts_updates_date(self):
        fixed_now = datetime(2025, 1, 7, 9, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            scheduler.datetime = FixedDatetime
            instance = scheduler.WakeScheduler()
            instance.state["date"] = "2024-12-31"
            instance.state["wake_count_today"] = 5
            instance._reset_daily_counts()

        state = json.loads((Path(self.mind_path) / "state" / "scheduler-state.json").read_text())
        self.assertEqual(state["date"], fixed_now.strftime("%Y-%m-%d"))
        self.assertEqual(state["wake_count_today"], 0)

    def test_resolve_mind_dir_default_and_load_state_bad_json(self):
        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            with mock.patch.dict(os.environ, {"HOME": "/tmp/home"}, clear=True):
                self.assertEqual(scheduler.resolve_mind_dir(), Path("/tmp/home/.claude-mind"))

            state_path = Path(self.mind_path) / "state" / "scheduler-state.json"
            state_path.parent.mkdir(parents=True, exist_ok=True)
            state_path.write_text("{bad json}")
            instance = scheduler.WakeScheduler()
            self.assertIsNone(instance.state.get("last_wake"))

    def test_pending_triggers_and_queue_status_missing_or_invalid(self):
        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            instance = scheduler.WakeScheduler()
            self.assertEqual(instance._get_pending_triggers(), [])
            self.assertEqual(instance._get_queue_status(), {"pending": 0, "high_priority": 0})

        triggers_path = Path(self.mind_path) / "state" / "triggers" / "triggers.json"
        triggers_path.parent.mkdir(parents=True, exist_ok=True)
        triggers_path.write_text("{bad json}")
        queue_path = Path(self.mind_path) / "state" / "proactive-queue" / "queue.json"
        queue_path.parent.mkdir(parents=True, exist_ok=True)
        queue_path.write_text("{bad json}")

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            instance = scheduler.WakeScheduler()
            self.assertEqual(instance._get_pending_triggers(), [])
            self.assertEqual(instance._get_queue_status(), {"pending": 0, "high_priority": 0})

    def test_calendar_events_and_minutes_since_last_wake_invalid(self):
        calendar_path = Path(self.mind_path) / "state" / "calendar-cache.json"
        calendar_path.parent.mkdir(parents=True, exist_ok=True)
        calendar_path.write_text("{bad json}")

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            instance = scheduler.WakeScheduler()
            self.assertEqual(instance._get_calendar_events(), [])
            instance.state["last_wake"] = "not-a-date"
            self.assertIsNone(instance._minutes_since_last_wake())

        calendar_path.write_text(json.dumps({"events": [{"start": "bad-date"}]}))
        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            instance = scheduler.WakeScheduler()
            self.assertEqual(instance._get_calendar_events(), [])

    def test_should_wake_now_low_confidence(self):
        fixed_now = datetime(2025, 1, 8, 11, 30, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            scheduler.datetime = FixedDatetime
            instance = scheduler.WakeScheduler()
            should_wake, wake_type, reason = instance.should_wake_now()

        self.assertFalse(should_wake)
        self.assertEqual(wake_type, "none")
        self.assertIn("Low confidence", reason)

    def test_get_next_wake_and_status(self):
        fixed_now = datetime(2025, 1, 9, 8, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            scheduler.datetime = FixedDatetime
            instance = scheduler.WakeScheduler()
            next_wake = instance.get_next_wake()
            status = instance.get_status()

        self.assertIn("next_scheduled", next_wake)
        self.assertIn("queue_status", status)
        self.assertIn("upcoming_events", status)

    def test_main_commands(self):
        with load_service_module(SCHEDULER_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as scheduler:
            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["scheduler.py"]), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    scheduler.main()
            self.assertIn("Usage: scheduler.py", buf.getvalue())

            with (
                mock.patch.object(sys, "argv", ["scheduler.py", "check"]),
                mock.patch.object(scheduler.WakeScheduler, "should_wake_now", return_value=(False, "none", "No")),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                scheduler.main()

            with (
                mock.patch.object(sys, "argv", ["scheduler.py", "next"]),
                mock.patch.object(scheduler.WakeScheduler, "get_next_wake", return_value={"next": True}),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                scheduler.main()

            with (
                mock.patch.object(sys, "argv", ["scheduler.py", "status"]),
                mock.patch.object(scheduler.WakeScheduler, "get_status", return_value={"status": True}),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                scheduler.main()

            with (
                mock.patch.object(sys, "argv", ["scheduler.py", "record", "light"]),
                mock.patch.object(scheduler.WakeScheduler, "record_wake"),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                scheduler.main()

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["scheduler.py", "unknown"]), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    scheduler.main()
            self.assertIn("Unknown command", buf.getvalue())
