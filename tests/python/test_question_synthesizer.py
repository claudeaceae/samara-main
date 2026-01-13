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

QUESTION_SYNTH_PATH = os.path.join(LIB_DIR, "question_synthesizer.py")


def write_jsonl(path, entries):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as handle:
        for entry in entries:
            handle.write(json.dumps(entry) + "\n")


def make_chroma_stub(results):
    chroma_module = types.ModuleType("chroma_helper")

    class MemoryIndex:
        def __init__(self):
            pass

        def search(self, query, n_results=5):
            return results

    chroma_module.MemoryIndex = MemoryIndex
    return chroma_module


class QuestionSynthesizerTests(unittest.TestCase):
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

    def test_should_ask_now_respects_quiet_hours_and_daily_limit(self):
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            module.CHROMA_AVAILABLE = False
            synth = module.QuestionSynthesizer()
            quiet = synth._should_ask_now({"hour": 22})

        self.assertFalse(quiet)

        today = datetime.now().strftime("%Y-%m-%d")
        entries = [
            {
                "timestamp": f"{today}T08:00:00",
                "question": "Q1",
                "question_stem": "q1",
                "category": "introspective",
                "trigger": "wake_cycle",
                "context": {},
            },
            {
                "timestamp": f"{today}T09:00:00",
                "question": "Q2",
                "question_stem": "q2",
                "category": "introspective",
                "trigger": "wake_cycle",
                "context": {},
            },
            {
                "timestamp": f"{today}T10:00:00",
                "question": "Q3",
                "question_stem": "q3",
                "category": "introspective",
                "trigger": "wake_cycle",
                "context": {},
            },
        ]
        asked_file = self.mind_path / "state" / "asked_questions.jsonl"
        write_jsonl(asked_file, entries)

        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            module.CHROMA_AVAILABLE = False
            synth = module.QuestionSynthesizer()
            should_ask = synth._should_ask_now({"hour": 10})

        self.assertFalse(should_ask)

    def test_stem_extraction_and_similarity(self):
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            stem = synth._extract_stem("What's one thing you want more of?")
            self.assertNotIn("?", stem)
            self.assertIn("want", stem)
            self.assertIn("more", stem)
            self.assertTrue(synth._stems_similar(stem, stem))

    def test_log_and_mark_response(self):
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            question = "What project are you excited about?"
            synth.log_question_asked(question, "introspective", "wake_cycle")
            stem = synth._extract_stem(question)
            synth.mark_response_received(stem, "They felt good")

        entries = [
            json.loads(line)
            for line in (self.mind_path / "state" / "asked_questions.jsonl").read_text().splitlines()
        ]
        self.assertEqual(len(entries), 1)
        self.assertTrue(entries[0].get("response_received"))
        self.assertEqual(entries[0].get("response_summary"), "They felt good")

    def test_synthesize_returns_question(self):
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            module.CHROMA_AVAILABLE = False
            synth = module.QuestionSynthesizer()
            result = synth.synthesize({"trigger": "wake_cycle", "hour": 10})

        self.assertIsNotNone(result)
        self.assertIn(result.get("category"), {"introspective", "exploratory"})
        self.assertTrue(result.get("question"))

    def test_enrich_context_loads_state_files(self):
        state_dir = self.mind_path / "state"
        state_dir.mkdir(parents=True, exist_ok=True)
        (self.mind_path / "memory" / "episodes").mkdir(parents=True, exist_ok=True)
        (self.mind_path / "memory" / "episodes" / f"{datetime.now():%Y-%m-%d}.md").write_text(
            "Recent episode content"
        )
        (state_dir / "location.json").write_text(json.dumps({"address": "123 Main St, City"}))
        (state_dir / "location-patterns.json").write_text(json.dumps({"frequent_trips": True}))
        (state_dir / "temporal-patterns.json").write_text(json.dumps({"active_hours": [9, 10]}))
        (state_dir / "topic-patterns.json").write_text(
            json.dumps({"recurring_themes": [{"topic": "focus"}]})
        )

        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            module.CHROMA_AVAILABLE = False
            synth = module.QuestionSynthesizer()
            context = synth._enrich_context({"trigger": "wake_cycle", "hour": 9})

        self.assertEqual(context.get("time_of_day"), "morning")
        self.assertIn("current_location", context)
        self.assertIn("location_patterns", context)
        self.assertIn("temporal_patterns", context)
        self.assertIn("topic_patterns", context)
        self.assertEqual(context.get("recent_episode"), "Recent episode content")

    def test_get_eligible_categories_prioritizes_calendar(self):
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            categories = synth._get_eligible_categories(
                {
                    "trigger": "calendar_ended",
                    "recent_event": "Demo",
                    "recurring_themes": [{"topic": "plans", "dates": ["2025-01-01"]}],
                    "temporal_patterns": {"active_hours": [9]},
                }
            )

        self.assertEqual(categories[0], "reflective")
        self.assertIn("connective", categories)
        self.assertIn("observational", categories)

    def test_generate_from_category_uses_time_period(self):
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            result = synth._generate_from_category(
                "observational",
                {"temporal_patterns": {"active_hours": [9]}, "trigger": "temporal_pattern"},
            )

        self.assertIsNotNone(result)
        self.assertIn("mornings", result.get("question"))
        self.assertEqual(result.get("confidence"), 0.8)

    def test_was_recently_asked_detects_similarity(self):
        today = datetime.now().strftime("%Y-%m-%d")
        asked_file = self.mind_path / "state" / "asked_questions.jsonl"
        write_jsonl(
            asked_file,
            [
                {
                    "timestamp": f"{today}T08:00:00",
                    "question": "What are you excited about?",
                    "question_stem": "excited about",
                    "category": "introspective",
                    "trigger": "wake_cycle",
                    "context": {},
                }
            ],
        )

        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            recent = synth._was_recently_asked("excited about")

        self.assertTrue(recent)

    def test_count_questions_asked_uses_date_filter(self):
        today = datetime.now().strftime("%Y-%m-%d")
        asked_file = self.mind_path / "state" / "asked_questions.jsonl"
        write_jsonl(
            asked_file,
            [
                {"timestamp": f"{today}T08:00:00", "question": "Q1", "question_stem": "q1"},
                {"timestamp": f"{today}T09:00:00", "question": "Q2", "question_stem": "q2"},
                {"timestamp": "2024-01-01T09:00:00", "question": "Old", "question_stem": "old"},
            ],
        )

        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            count = synth._count_questions_asked(today)

        self.assertEqual(count, 2)

    def test_get_recurring_themes_uses_chroma(self):
        results = [
            {"metadata": {"date": "2025-01-01"}},
            {"metadata": {"date": "2025-01-02"}},
        ]
        stubs = {"chroma_helper": make_chroma_stub(results)}
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env, stubs=stubs) as module:
            synth = module.QuestionSynthesizer()
            themes = synth._get_recurring_themes()

        self.assertTrue(themes)
        self.assertGreaterEqual(themes[0].get("days_present", 0), 2)

    def test_get_variable_value_uses_context(self):
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            module.CHROMA_AVAILABLE = False
            synth = module.QuestionSynthesizer()
            self.assertEqual(
                synth._get_variable_value("place", {"current_place": "Cafe"}),
                "Cafe",
            )
            self.assertEqual(
                synth._get_variable_value("place", {"current_location": {"address": "123 Main St, City"}}),
                "123 Main St",
            )
            self.assertEqual(
                synth._get_variable_value("time_period", {"temporal_patterns": {"active_hours": [9]}}),
                "mornings",
            )
            self.assertEqual(
                synth._get_variable_value("time_period", {"temporal_patterns": {"active_hours": [18]}}),
                "evenings",
            )
            self.assertEqual(
                synth._get_variable_value("time_period", {"temporal_patterns": {"active_hours": [14]}}),
                "afternoons",
            )
            self.assertEqual(
                synth._get_variable_value("pattern", {"location_patterns": {"frequent_trips": True}}),
                "busy",
            )
            self.assertEqual(
                synth._get_variable_value("pattern", {"location_patterns": {"frequent_trips": False}}),
                "quiet",
            )
            self.assertEqual(
                synth._get_variable_value("event", {"recent_event": "Demo"}),
                "Demo",
            )
            self.assertEqual(
                synth._get_variable_value(
                    "topic",
                    {"recurring_themes": [{"topic": "Focus"}]},
                ),
                "Focus",
            )
            self.assertEqual(
                synth._get_variable_value(
                    "date",
                    {"recurring_themes": [{"topic": "Focus", "dates": ["2025-01-01"]}]},
                ),
                "2025-01-01",
            )
            self.assertEqual(
                synth._get_variable_value(
                    "theme",
                    {"topic_patterns": {"recurring_themes": [{"topic": "Growth"}]}},
                ),
                "Growth",
            )
            self.assertIsNone(synth._get_variable_value("count", {}))

    def test_generate_from_category_handles_missing_and_fallback(self):
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            module.CHROMA_AVAILABLE = False
            synth = module.QuestionSynthesizer()
            self.assertIsNone(synth._generate_from_category("observational", {"trigger": "wake_cycle"}))

            module.QUESTION_TEMPLATES = {
                "test": {
                    "description": "test",
                    "templates": [
                        {"template": "Tell me something", "requires": [], "triggers": ["wake_cycle"]}
                    ],
                }
            }
            with mock.patch.object(synth, "_extract_variables", return_value=None):
                with mock.patch.object(module.random, "choice", side_effect=lambda items: items[0]):
                    question = synth._generate_from_category("test", {"trigger": "wake_cycle"})

        self.assertEqual(question["confidence"], 0.6)
        self.assertEqual(question["category"], "test")

    def test_synthesize_returns_none_for_quiet_or_missing_categories(self):
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            module.CHROMA_AVAILABLE = False
            synth = module.QuestionSynthesizer()
            self.assertIsNone(synth.synthesize({"trigger": "wake_cycle", "hour": 23}))
            self.assertIsNone(synth.synthesize({"trigger": "unknown", "hour": 10}))

            with mock.patch.object(synth, "_generate_from_category", return_value={"question_stem": "stem"}):
                with mock.patch.object(synth, "_was_recently_asked", return_value=True):
                    self.assertIsNone(synth.synthesize({"trigger": "wake_cycle", "hour": 10}))

    def test_stems_similar_requires_overlap(self):
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            self.assertFalse(synth._stems_similar("alpha beta", "gamma delta"))
            self.assertFalse(synth._stems_similar("", "alpha"))

    def test_was_recently_asked_handles_bad_json(self):
        asked_file = self.mind_path / "state" / "asked_questions.jsonl"
        asked_file.write_text("{bad json}\n")

        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            self.assertFalse(synth._was_recently_asked("anything"))

    def test_count_questions_asked_handles_bad_json(self):
        today = datetime.now().strftime("%Y-%m-%d")
        asked_file = self.mind_path / "state" / "asked_questions.jsonl"
        asked_file.write_text("{bad json}\n")

        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            self.assertEqual(synth._count_questions_asked(today), 0)

    def test_get_recent_episode_handles_read_error(self):
        episode_file = self.mind_path / "memory" / "episodes" / f"{datetime.now():%Y-%m-%d}.md"
        episode_file.write_text("Some episode")

        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            with mock.patch.object(Path, "read_text", side_effect=OSError("boom")):
                self.assertIsNone(synth._get_recent_episode())

    def test_mark_response_received_skips_already_responded(self):
        asked_file = self.mind_path / "state" / "asked_questions.jsonl"
        entries = [
            {
                "timestamp": "2026-01-01T08:00:00",
                "question": "Q1",
                "question_stem": "q1",
                "response_received": True,
                "response_summary": "done",
            }
        ]
        write_jsonl(asked_file, entries)

        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            synth.mark_response_received("q1", "new summary")

        updated = json.loads(asked_file.read_text().strip())
        self.assertEqual(updated["response_summary"], "done")

    def test_main_commands_output(self):
        asked_file = self.mind_path / "state" / "asked_questions.jsonl"
        today = datetime.now().strftime("%Y-%m-%d")
        write_jsonl(
            asked_file,
            [
                {
                    "timestamp": f"{today}T08:00:00",
                    "question": "Q1",
                    "question_stem": "q1",
                    "category": "introspective",
                }
            ],
        )

        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            module.CHROMA_AVAILABLE = False
            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["question_synthesizer.py"]), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    module.main()
            self.assertIn("Usage: question_synthesizer.py <command>", buf.getvalue())

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["question_synthesizer.py", "history", "1"]), contextlib.redirect_stdout(buf):
                module.main()
            self.assertIn(today, buf.getvalue())

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["question_synthesizer.py", "categories"]), contextlib.redirect_stdout(buf):
                module.main()
            self.assertIn("## INTROSPECTIVE", buf.getvalue())

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["question_synthesizer.py", "context"]), contextlib.redirect_stdout(buf):
                module.main()
            self.assertIn("Questions today", buf.getvalue())

            buf = io.StringIO()
            with (
                mock.patch.object(sys, "argv", ["question_synthesizer.py", "synthesize"]),
                mock.patch.object(module.QuestionSynthesizer, "synthesize", return_value=None),
                contextlib.redirect_stdout(buf),
            ):
                module.main()
            self.assertIn("No suitable question available", buf.getvalue())

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["question_synthesizer.py", "unknown"]), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    module.main()
            self.assertIn("Unknown command", buf.getvalue())

    def test_mark_response_received_no_file(self):
        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            synth.mark_response_received("missing", "summary")

        self.assertFalse((self.mind_path / "state" / "asked_questions.jsonl").exists())

    def test_get_context_summary_includes_patterns(self):
        today = datetime.now().strftime("%Y-%m-%d")
        asked_file = self.mind_path / "state" / "asked_questions.jsonl"
        write_jsonl(asked_file, [{"timestamp": f"{today}T08:00:00", "question": "Q1"}])
        (self.mind_path / "state" / "temporal-patterns.json").write_text(
            json.dumps({"active_hours": [9, 10], "avg_messages_per_day": 5})
        )
        (self.mind_path / "state" / "topic-patterns.json").write_text(
            json.dumps({"recurring_themes": [{"topic": "focus"}]})
        )

        with load_service_module(QUESTION_SYNTH_PATH, env=self.env) as module:
            synth = module.QuestionSynthesizer()
            summary = synth.get_context_summary()

        self.assertIn("Active hours", summary)
        self.assertIn("Recurring themes", summary)
        self.assertIn("Questions today", summary)


if __name__ == "__main__":
    unittest.main()
