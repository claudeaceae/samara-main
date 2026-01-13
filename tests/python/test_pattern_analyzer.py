import os
import sys
import tempfile
import types
import unittest
from datetime import datetime, timedelta
from pathlib import Path

TESTS_DIR = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, TESTS_DIR)
LIB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "lib"))
sys.path.insert(0, LIB_DIR)

from service_test_utils import load_service_module

PATTERN_ANALYZER_PATH = os.path.join(LIB_DIR, "pattern_analyzer.py")


def make_chroma_stub(search_fn):
    chroma_module = types.ModuleType("chroma_helper")

    class MemoryIndex:
        def __init__(self):
            pass

        def search(self, query, n_results=10, date_filter=None):
            return search_fn(query, n_results=n_results, date_filter=date_filter)

    chroma_module.MemoryIndex = MemoryIndex
    return {"chroma_helper": chroma_module}


class PatternAnalyzerTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = Path(self.temp_dir.name) / ".claude-mind"
        (self.mind_path / "state").mkdir(parents=True, exist_ok=True)
        (self.mind_path / "memory" / "episodes").mkdir(parents=True, exist_ok=True)
        (self.mind_path / "memory").mkdir(parents=True, exist_ok=True)
        self.env = {
            "SAMARA_MIND_PATH": str(self.mind_path),
            "MIND_PATH": str(self.mind_path),
        }

    def tearDown(self):
        self.temp_dir.cleanup()

    def _write_episode(self, date, content):
        path = self.mind_path / "memory" / "episodes" / f"{date}.md"
        path.write_text(content)

    def test_parse_episode_sections_extracts_counts(self):
        content = """# Episode
## 09:00
[iMessage]
**E:** Hi
**E:** Another
## 12:30
[Email]
**E:** Ping
"""

        with load_service_module(PATTERN_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.PatternAnalyzer()
            sections = analyzer._parse_episode_sections(content)

        self.assertEqual(len(sections), 2)
        self.assertEqual(sections[0]["time"], "09:00")
        self.assertEqual(sections[0]["e_message_count"], 2)
        self.assertEqual(sections[1]["channel"], "Email")

    def test_anomalies_detect_silence_and_unusual_timing(self):
        fixed_now = datetime(2025, 1, 10, 9, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        previous_day = "2025-01-09"
        today = "2025-01-10"

        self._write_episode(
            previous_day,
            """# Episode
## 03:00
[iMessage]
**E:** Late ping
## 09:00
[iMessage]
**E:** Hi
**E:** Another
**E:** Third
## 12:00
[Email]
**E:** Ping
""",
        )

        self._write_episode(
            today,
            """# Episode
## 09:00
[iMessage]
No messages yet.
""",
        )

        with load_service_module(PATTERN_ANALYZER_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.PatternAnalyzer()
            analyzer.chroma = None
            anomalies = analyzer.detect_anomalies()

        anomaly_types = {a.get("type") for a in anomalies.get("anomalies", [])}
        self.assertIn("silence", anomaly_types)
        self.assertIn("unusual_timing", anomaly_types)

    def test_analyze_all_writes_pattern_files(self):
        fixed_now = datetime(2025, 1, 10, 9, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        self._write_episode(
            "2025-01-09",
            """# Episode
## 09:00
[iMessage]
**E:** Hi
**E:** Another
## 10:00
[iMessage]
**E:** Quick note
""",
        )

        with load_service_module(PATTERN_ANALYZER_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.PatternAnalyzer()
            analyzer.chroma = None
            analyzer.analyze_all()

        patterns_path = self.mind_path / "state" / "patterns.json"
        self.assertTrue(patterns_path.exists())
        log_path = self.mind_path / "memory" / "patterns.jsonl"
        self.assertTrue(log_path.exists())

    def test_analyze_temporal_patterns_counts_messages(self):
        fixed_now = datetime(2025, 1, 10, 10, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        self._write_episode(
            "2025-01-09",
            """# Episode
## 09:00
[iMessage]
**E:** Hi
**E:** Another
## 09:30
[iMessage]
**E:** Follow-up
""",
        )
        self._write_episode(
            "2025-01-10",
            """# Episode
## 20:00
[Email]
**E:** Evening note
""",
        )

        with load_service_module(PATTERN_ANALYZER_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.PatternAnalyzer()
            analyzer.chroma = None
            temporal = analyzer.analyze_temporal_patterns()

        self.assertEqual(temporal["hour_distribution"][9], 3)
        self.assertEqual(temporal["hour_distribution"][20], 1)
        self.assertEqual(temporal["total_days_analyzed"], 2)
        self.assertIn(9, temporal["active_hours"])
        self.assertEqual(temporal["typical_gap_minutes"], 30)

    def test_analyze_drift_detects_volume_change(self):
        fixed_now = datetime(2025, 1, 8, 12, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        # Older day with no messages.
        self._write_episode(
            "2025-01-01",
            """# Episode
## 09:00
[iMessage]
""",
        )

        # Recent week with more messages.
        for day in range(2, 9):
            date = f"2025-01-0{day}"
            self._write_episode(
                date,
                """# Episode
## 10:00
[iMessage]
**E:** Hi
**E:** Another
**E:** Third
**E:** Fourth
""",
            )

        with load_service_module(PATTERN_ANALYZER_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.PatternAnalyzer()
            analyzer.chroma = None
            drift = analyzer.analyze_drift()

        signals = drift.get("drift_signals", [])
        self.assertTrue(any("Message volume increased" in s for s in signals))

    def test_analyze_topic_patterns_uses_chroma(self):
        fixed_now = datetime(2025, 1, 10, 12, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        def search_stub(query, n_results=10, date_filter=None):
            if date_filter:
                return [{"text": f"Topic {date_filter}", "metadata": {"date": date_filter}, "distance": 0.1}]
            if query == "memory and continuity":
                return [
                    {"metadata": {"date": "2025-01-09"}, "distance": 0.2, "text": "First"},
                    {"metadata": {"date": "2025-01-08"}, "distance": 0.3, "text": "Second"},
                ]
            return []

        stubs = make_chroma_stub(search_stub)
        with load_service_module(PATTERN_ANALYZER_PATH, env=self.env, stubs=stubs) as module:
            module.datetime = FixedDatetime
            analyzer = module.PatternAnalyzer()
            topics = analyzer.analyze_topic_patterns()

        self.assertEqual(topics["seed_topics_checked"], 8)
        self.assertTrue(topics["recurring_themes"])
        self.assertEqual(topics["recurring_themes"][0]["topic"], "memory and continuity")
        self.assertEqual(len(topics["recent_focus"]), 3)

    def test_get_pattern_summary_includes_key_sections(self):
        fixed_now = datetime(2025, 1, 10, 9, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        self._write_episode(
            "2025-01-09",
            """# Episode
## 09:00
[iMessage]
**E:** Hi
**E:** Another
## 10:00
[iMessage]
**E:** Quick note
""",
        )

        with load_service_module(PATTERN_ANALYZER_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            module.CHROMA_AVAILABLE = False
            analyzer = module.PatternAnalyzer()
            analyzer.chroma = None
            summary = analyzer.get_pattern_summary()

        self.assertIn("Active hours", summary)
        self.assertIn("Average messages/day", summary)


if __name__ == "__main__":
    unittest.main()
