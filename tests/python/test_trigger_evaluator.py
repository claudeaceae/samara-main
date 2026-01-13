import contextlib
import io
import json
import os
import sys
import tempfile
import types
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock

TESTS_DIR = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, TESTS_DIR)
LIB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "lib"))
sys.path.insert(0, LIB_DIR)

from service_test_utils import load_service_module

TRIGGER_EVALUATOR_PATH = os.path.join(LIB_DIR, "trigger_evaluator.py")


def make_trigger_stubs(
    calendar_triggers=None,
    upcoming_events=None,
    recent_events=None,
    chroma_results=None,
    location_triggers=None,
    battery_triggers=None,
    current_place=None,
    weather_triggers=None,
    question_result=None,
):
    calendar_triggers = calendar_triggers or []
    upcoming_events = upcoming_events or []
    recent_events = recent_events or []
    chroma_results = chroma_results or []
    location_triggers = location_triggers or []
    battery_triggers = battery_triggers or []
    weather_triggers = weather_triggers or []

    pattern_module = types.ModuleType("pattern_analyzer")

    class PatternAnalyzer:
        def __init__(self):
            pass

    pattern_module.PatternAnalyzer = PatternAnalyzer

    calendar_module = types.ModuleType("calendar_analyzer")

    class CalendarAnalyzer:
        def __init__(self):
            pass

        def check_for_triggers(self):
            return calendar_triggers

        def get_upcoming_events(self, hours=0):
            return upcoming_events

        def get_recently_ended(self, hours=1):
            return recent_events

    calendar_module.CalendarAnalyzer = CalendarAnalyzer

    chroma_module = types.ModuleType("chroma_helper")

    class MemoryIndex:
        def __init__(self):
            pass

        def search(self, query, n_results=5):
            return chroma_results

    chroma_module.MemoryIndex = MemoryIndex

    location_module = types.ModuleType("location_analyzer")

    class LocationAnalyzer:
        def __init__(self):
            pass

        def get_location_triggers(self):
            return location_triggers

        def get_battery_triggers(self):
            return battery_triggers

        def get_current_place(self):
            return current_place

    location_module.LocationAnalyzer = LocationAnalyzer

    weather_module = types.ModuleType("weather_helper")

    class WeatherHelper:
        def __init__(self):
            pass

        def get_weather_triggers(self):
            return weather_triggers

    weather_module.WeatherHelper = WeatherHelper

    question_module = types.ModuleType("question_synthesizer")

    class QuestionSynthesizer:
        def __init__(self):
            pass

        def synthesize(self, context):
            return question_result

    question_module.QuestionSynthesizer = QuestionSynthesizer

    return {
        "pattern_analyzer": pattern_module,
        "calendar_analyzer": calendar_module,
        "chroma_helper": chroma_module,
        "location_analyzer": location_module,
        "weather_helper": weather_module,
        "question_synthesizer": question_module,
    }


class TriggerEvaluatorTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = Path(self.temp_dir.name) / ".claude-mind"
        (self.mind_path / "state").mkdir(parents=True, exist_ok=True)
        (self.mind_path / "memory" / "episodes").mkdir(parents=True, exist_ok=True)
        self.env = {
            "SAMARA_MIND_PATH": str(self.mind_path),
            "MIND_PATH": str(self.mind_path),
        }

    def tearDown(self):
        self.temp_dir.cleanup()

    def _disable_dependencies(self, module):
        module.PATTERNS_AVAILABLE = False
        module.CALENDAR_AVAILABLE = False
        module.CHROMA_AVAILABLE = False
        module.LOCATION_AVAILABLE = False
        module.WEATHER_AVAILABLE = False
        module.QUESTIONS_AVAILABLE = False

    def test_quiet_hours_block(self):
        fixed_now = datetime(2025, 1, 10, 23, 30, 0)

        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            self._disable_dependencies(module)

            class FixedDatetime(datetime):
                @classmethod
                def now(cls, tz=None):
                    return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            safeguards = evaluator._check_safeguards()

        self.assertFalse(safeguards.get("all_passed"))
        self.assertIn("Quiet hours", safeguards.get("blocking_reason", ""))

    def test_cooldown_block(self):
        fixed_now = datetime(2025, 1, 10, 10, 0, 0)
        cooldown_file = self.mind_path / "state" / "last-proactive-trigger.txt"
        cooldown_file.write_text(str(int(fixed_now.timestamp() - 30 * 60)))

        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            self._disable_dependencies(module)

            class FixedDatetime(datetime):
                @classmethod
                def now(cls, tz=None):
                    return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            safeguards = evaluator._check_safeguards()

        self.assertFalse(safeguards.get("all_passed"))
        self.assertIn("Cooldown", safeguards.get("blocking_reason", ""))

    def test_recent_interaction_block(self):
        fixed_now = datetime(2025, 1, 10, 10, 0, 0)
        episode_path = self.mind_path / "memory" / "episodes" / "2025-01-10.md"
        episode_path.write_text("## 10:15\n**E:** Hi\n")

        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            self._disable_dependencies(module)

            class FixedDatetime(datetime):
                @classmethod
                def now(cls, tz=None):
                    return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            safeguards = evaluator._check_safeguards()

        self.assertFalse(safeguards.get("all_passed"))
        self.assertIn("Recent conversation", safeguards.get("blocking_reason", ""))

    def test_pattern_and_anomaly_triggers(self):
        patterns = {
            "temporal": {"active_hours": [10], "avg_messages_per_day": 10},
            "anomalies": {
                "today_status": {"messages": 2},
                "anomalies": [{"severity": "high", "description": "Silent day"}],
            },
            "topics": {"recurring_themes": [{"topic": "Focus", "days_present": 5}]},
        }
        patterns_file = self.mind_path / "state" / "patterns.json"
        patterns_file.write_text(json.dumps(patterns))
        fixed_now = datetime(2025, 1, 10, 10, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        stubs = make_trigger_stubs()
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            pattern_triggers = evaluator._get_pattern_triggers()
            anomaly_triggers = evaluator._get_anomaly_triggers()

        self.assertEqual(len(pattern_triggers), 2)
        self.assertEqual(anomaly_triggers[0].get("confidence"), 0.7)

    def test_evaluate_selects_best_trigger_and_logs(self):
        fixed_now = datetime(2025, 1, 10, 10, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        calendar_triggers = [
            {
                "confidence": 0.9,
                "suggested_action": "Prep for demo",
                "event": "Demo",
                "type": "upcoming_event",
                "minutes_until": 20,
            }
        ]
        stubs = make_trigger_stubs(calendar_triggers=calendar_triggers)
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            result = evaluator.evaluate()

        self.assertTrue(result["should_engage"])
        self.assertEqual(result["trigger_type"], "calendar")
        self.assertEqual(result["reason"], "Prep for demo")
        log_path = self.mind_path / "state" / "trigger-evaluations.jsonl"
        entry = json.loads(log_path.read_text().strip())
        self.assertEqual(entry["best_trigger"]["type"], "calendar")

    def test_location_suppression_short_circuits(self):
        fixed_now = datetime(2025, 1, 10, 12, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        location_triggers = [{"suppress_engagement": True, "reason": "In motion"}]
        stubs = make_trigger_stubs(location_triggers=location_triggers)
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            result = evaluator.evaluate()

        self.assertEqual(result["escalation_level"], "suppressed")
        self.assertEqual(result["reason"], "In motion")

    def test_check_in_meeting_blocks(self):
        fixed_now = datetime(2025, 1, 10, 12, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        upcoming_events = [{"minutes_until": 0}]
        stubs = make_trigger_stubs(upcoming_events=upcoming_events)
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            safeguards = evaluator._check_safeguards()

        self.assertFalse(safeguards["all_passed"])
        self.assertIn("meeting", safeguards["blocking_reason"].lower())

    def test_question_triggers_set_low_battery_flag(self):
        fixed_now = datetime(2025, 1, 10, 13, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        question_result = {"confidence": 0.7, "category": "checkin", "question": "All good?"}
        battery_triggers = [{"suppress_non_urgent": True}]
        stubs = make_trigger_stubs(
            question_result=question_result,
            battery_triggers=battery_triggers,
        )
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            result = evaluator.evaluate()

        self.assertEqual(result["trigger_type"], "question")
        self.assertEqual(result["escalation_level"], "wake")
        self.assertTrue(result["safeguard_status"].get("low_battery"))

    def test_record_engagement_writes_timestamp(self):
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            evaluator = module.TriggerEvaluator()
            evaluator.record_engagement()

        timestamp_file = self.mind_path / "state" / "last-proactive-trigger.txt"
        self.assertTrue(timestamp_file.exists())
        self.assertTrue(timestamp_file.read_text().strip())

    def test_get_escalation_summary_counts_recent(self):
        log_file = self.mind_path / "state" / "trigger-evaluations.jsonl"
        entries = [
            {"timestamp": "2025-01-10T10:00:00", "best_trigger": {"confidence": 0.7}, "escalation": "engage"},
            {"timestamp": "2025-01-10T11:00:00", "best_trigger": {"confidence": 0.5}, "escalation": "wake"},
        ]
        log_file.parent.mkdir(parents=True, exist_ok=True)
        log_file.write_text("\n".join(json.dumps(e) for e in entries) + "\n")

        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            evaluator = module.TriggerEvaluator()
            summary = evaluator.get_escalation_summary()

        self.assertIn("2 evaluations", summary)
        self.assertIn("1 engagements", summary)

    def test_evaluate_blocks_when_safeguards_fail(self):
        fixed_now = datetime(2025, 1, 10, 23, 30, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        stubs = make_trigger_stubs()
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            result = evaluator.evaluate()

        self.assertEqual(result["escalation_level"], "blocked")
        self.assertIn("Quiet hours", result["reason"])

    def test_evaluate_no_triggers_returns_log(self):
        fixed_now = datetime(2025, 1, 10, 10, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        stubs = make_trigger_stubs()
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            result = evaluator.evaluate()

        self.assertEqual(result["reason"], "No triggers detected")
        self.assertEqual(result["escalation_level"], "log")

    def test_escalation_levels_log_and_dream(self):
        fixed_now = datetime(2025, 1, 10, 10, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        stubs = make_trigger_stubs()
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            with mock.patch.object(
                evaluator, "_get_anomaly_triggers", return_value=[{"type": "anomaly", "confidence": 0.2}]
            ):
                result = evaluator.evaluate()
                self.assertEqual(result["escalation_level"], "log")

            with mock.patch.object(
                evaluator, "_get_anomaly_triggers", return_value=[{"type": "anomaly", "confidence": 0.5}]
            ):
                result = evaluator.evaluate()
                self.assertEqual(result["escalation_level"], "dream")

    def test_check_safeguards_bad_cooldown_file(self):
        fixed_now = datetime(2025, 1, 10, 10, 0, 0)
        cooldown_file = self.mind_path / "state" / "last-proactive-trigger.txt"
        cooldown_file.write_text("not-a-number")

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            self._disable_dependencies(module)
            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            safeguards = evaluator._check_safeguards()

        self.assertTrue(safeguards["all_passed"])
        self.assertTrue(safeguards["checks"]["cooldown"])

    def test_check_recent_interaction_no_match(self):
        fixed_now = datetime(2025, 1, 10, 10, 0, 0)
        episode_path = self.mind_path / "memory" / "episodes" / "2025-01-10.md"
        episode_path.write_text("## 02:00\n**E:** Hi\n")

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            self.assertFalse(evaluator._check_recent_interaction())

    def test_check_in_meeting_no_calendar_or_exception(self):
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            self._disable_dependencies(module)
            evaluator = module.TriggerEvaluator()
            self.assertFalse(evaluator._check_in_meeting())

        stubs = make_trigger_stubs()
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            evaluator = module.TriggerEvaluator()
            with mock.patch.object(evaluator.calendar_analyzer, "get_upcoming_events", side_effect=RuntimeError("boom")):
                self.assertFalse(evaluator._check_in_meeting())

    def test_pattern_triggers_bad_json(self):
        patterns_file = self.mind_path / "state" / "patterns.json"
        patterns_file.write_text("{bad json}")

        stubs = make_trigger_stubs()
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            evaluator = module.TriggerEvaluator()
            self.assertEqual(evaluator._get_pattern_triggers(), [])

    def test_calendar_triggers_exception(self):
        stubs = make_trigger_stubs()
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            evaluator = module.TriggerEvaluator()
            with mock.patch.object(evaluator.calendar_analyzer, "check_for_triggers", side_effect=RuntimeError("boom")):
                self.assertEqual(evaluator._get_calendar_triggers(), [])

    def test_anomaly_triggers_medium_low_and_bad_json(self):
        patterns = {
            "anomalies": {
                "anomalies": [
                    {"severity": "medium", "description": "Drift"},
                    {"severity": "low", "description": "Minor"},
                ]
            }
        }
        patterns_file = self.mind_path / "state" / "patterns.json"
        patterns_file.write_text(json.dumps(patterns))

        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            evaluator = module.TriggerEvaluator()
            triggers = evaluator._get_anomaly_triggers()

        confidences = sorted(t["confidence"] for t in triggers)
        self.assertEqual(confidences, [0.3, 0.5])

        patterns_file.write_text("{bad json}")
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            evaluator = module.TriggerEvaluator()
            self.assertEqual(evaluator._get_anomaly_triggers(), [])

    def test_cross_temporal_triggers_filters_today(self):
        fixed_now = datetime(2025, 1, 10, 10, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        episode_path = self.mind_path / "memory" / "episodes" / "2025-01-10.md"
        episode_path.write_text("Today's conversation")
        chroma_results = [
            {"metadata": {"date": "2025-01-10"}, "distance": 0.1, "text": "today"},
            {"metadata": {"date": "2025-01-08"}, "distance": 0.2, "text": "related"},
            {"metadata": {"date": "2025-01-07"}, "distance": 0.8, "text": "far"},
        ]
        stubs = make_trigger_stubs(chroma_results=chroma_results)

        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            module.datetime = FixedDatetime
            evaluator = module.TriggerEvaluator()
            triggers = evaluator._get_cross_temporal_triggers()

        self.assertEqual(len(triggers), 1)
        self.assertIn("2025-01-08", triggers[0]["reason"])

    def test_question_triggers_build_context(self):
        class Recorder:
            def __init__(self):
                self.context = None

            def synthesize(self, context):
                self.context = context
                return {"confidence": 0.7, "category": "reflective", "question": "How was it?"}

        stubs = make_trigger_stubs()
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            evaluator = module.TriggerEvaluator()
            evaluator.question_synthesizer = Recorder()

            class LocationStub:
                def get_current_place(self):
                    return {"name": "Cafe"}

            class CalendarStub:
                def get_recently_ended(self, hours=1):
                    return [{"summary": "Demo"}]

            evaluator.location_analyzer = LocationStub()
            evaluator.calendar_analyzer = CalendarStub()
            triggers = evaluator._get_question_triggers()

            self.assertEqual(triggers[0]["type"], "question")
            self.assertEqual(evaluator.question_synthesizer.context["current_place"], "Cafe")
            self.assertEqual(evaluator.question_synthesizer.context["recent_event"], "Demo")
            self.assertEqual(evaluator.question_synthesizer.context["trigger"], "calendar_ended")

    def test_generate_calendar_message_variants(self):
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            evaluator = module.TriggerEvaluator()
            upcoming_short = evaluator._generate_calendar_message(
                {"type": "upcoming_event", "event": "Demo", "minutes_until": 15}
            )
            upcoming_long = evaluator._generate_calendar_message(
                {"type": "upcoming_event", "event": "Demo", "minutes_until": 45}
            )
            ended = evaluator._generate_calendar_message(
                {"type": "recently_ended", "event": "Retro"}
            )

        self.assertIn("about 15 minutes", upcoming_short)
        self.assertIn("coming up", upcoming_long)
        self.assertEqual(ended, "How did Retro go?")

    def test_get_escalation_summary_no_log(self):
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env) as module:
            evaluator = module.TriggerEvaluator()
            summary = evaluator.get_escalation_summary()

        self.assertIn("No trigger evaluations", summary)

    def test_main_commands(self):
        stubs = make_trigger_stubs()
        with load_service_module(TRIGGER_EVALUATOR_PATH, env=self.env, stubs=stubs) as module:
            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["trigger_evaluator.py"]), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    module.main()
            self.assertIn("Usage: trigger_evaluator.py <command>", buf.getvalue())

            with (
                mock.patch.object(sys, "argv", ["trigger_evaluator.py", "evaluate"]),
                mock.patch.object(module.TriggerEvaluator, "evaluate", return_value={"ok": True}),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                module.main()

            with (
                mock.patch.object(sys, "argv", ["trigger_evaluator.py", "safeguards"]),
                mock.patch.object(module.TriggerEvaluator, "_check_safeguards", return_value={"all_passed": True}),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                module.main()

            with (
                mock.patch.object(sys, "argv", ["trigger_evaluator.py", "summary"]),
                mock.patch.object(module.TriggerEvaluator, "get_escalation_summary", return_value="Summary"),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                module.main()

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["trigger_evaluator.py", "unknown"]), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    module.main()
            self.assertIn("Unknown command", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
