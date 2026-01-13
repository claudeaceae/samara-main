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

TESTS_DIR = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, TESTS_DIR)
LIB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "lib"))
sys.path.insert(0, LIB_DIR)

from service_test_utils import load_service_module

ROUNDUP_PATH = os.path.join(LIB_DIR, "roundup_aggregator.py")


def write_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class _DummyCompleted:
    def __init__(self, stdout=""):
        self.stdout = stdout


class RoundupAggregatorTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = Path(self.temp_dir.name) / ".claude-mind"
        (self.mind_path / "state").mkdir(parents=True, exist_ok=True)
        (self.mind_path / "memory" / "episodes").mkdir(parents=True, exist_ok=True)
        (self.mind_path / "memory" / "reflections").mkdir(parents=True, exist_ok=True)
        (self.mind_path / "logs").mkdir(parents=True, exist_ok=True)
        self.env = {
            "SAMARA_MIND_PATH": str(self.mind_path),
            "MIND_PATH": str(self.mind_path),
        }

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_parse_periods_and_dates(self):
        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            weekly = module.RoundupAggregator("weekly", "2026-W01")
            monthly = module.RoundupAggregator("monthly", "2026-01")
            yearly = module.RoundupAggregator("yearly", "2026")

        self.assertEqual(weekly.start_date.strftime("%Y-%m-%d"), "2025-12-29")
        self.assertEqual(weekly.end_date.strftime("%Y-%m-%d"), "2026-01-04")
        self.assertEqual(monthly.start_date.strftime("%Y-%m-%d"), "2026-01-01")
        self.assertEqual(monthly.end_date.strftime("%Y-%m-%d"), "2026-01-31")
        self.assertEqual(yearly.start_date.strftime("%Y-%m-%d"), "2026-01-01")
        self.assertEqual(yearly.end_date.strftime("%Y-%m-%d"), "2026-12-31")
        self.assertEqual(len(monthly._dates_in_range()), 31)

    def test_aggregate_relational_counts(self):
        episode_one = """# Episode
## 09:00
[iMessage]
**E:** Hello
**E:** Another
## 10:00
[Email]
**E:** Ping
"""
        episode_two = """# Episode
## 08:00
[Direct]
**E:** Morning
"""
        write_text(self.mind_path / "memory" / "episodes" / "2026-01-01.md", episode_one)
        write_text(self.mind_path / "memory" / "episodes" / "2026-01-02.md", episode_two)

        sent_log = """[2026-01-01 12:00:00] Sent message
[2026-01-03 09:00:00] Sent message
[2025-12-31 09:00:00] Sent message
"""
        write_text(self.mind_path / "logs" / "messages-sent.log", sent_log)

        patterns = {
            "topics": {
                "recurring_themes": [
                    {"topic": "Theme A"},
                    {"topic": "Theme B"},
                ]
            }
        }
        write_text(self.mind_path / "state" / "patterns.json", json.dumps(patterns))

        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            aggregator = module.RoundupAggregator("monthly", "2026-01")
            relational = aggregator._aggregate_relational()

        self.assertEqual(relational["messages_received"], 4)
        self.assertEqual(relational["messages_sent"], 2)
        self.assertEqual(relational["total_messages"], 6)
        self.assertEqual(relational["sessions"], 3)
        self.assertEqual(relational["conversations"], 1)
        self.assertEqual(relational["avg_messages_per_day"], 0.2)
        self.assertEqual(relational["top_themes"], ["Theme A", "Theme B"])

    def test_aggregate_productive_counts(self):
        learnings = """# Learnings
## 2026-01-02
- Learned one
- Learned two
## 2026-02-01
- Out of range
"""
        decisions = """# Decisions
## 2026-01-02
- Decision one
"""
        write_text(self.mind_path / "memory" / "learnings.md", learnings)
        write_text(self.mind_path / "memory" / "decisions.md", decisions)
        (self.mind_path / ".git").mkdir(parents=True, exist_ok=True)

        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            module.WWW_PATH = Path(self.temp_dir.name) / "website"
            module.DEVELOPER_PATH = Path(self.temp_dir.name) / "Developer"

            blog_path = module.WWW_PATH / "src" / "content" / "blog"
            write_text(
                blog_path / "post.md",
                """---
title: Sample Post
pubDate: 2026-01-02
---
""",
            )

            def fake_run(args, capture_output=True, text=True, timeout=10):
                if "--numstat" in args:
                    return _DummyCompleted("5\t2\tfile.txt\n")
                return _DummyCompleted("abcd123 commit one\n")

            with mock.patch.object(module.subprocess, "run", side_effect=fake_run):
                aggregator = module.RoundupAggregator("monthly", "2026-01")
                productive = aggregator._aggregate_productive()

        self.assertEqual(productive["git_commits"], 1)
        self.assertEqual(productive["lines_added"], 5)
        self.assertEqual(productive["lines_deleted"], 2)
        self.assertEqual(productive["lines_changed"], 7)
        self.assertEqual(productive["repos_touched"], 1)
        self.assertIn(self.mind_path.name, productive["repo_names"])
        self.assertEqual(productive["blog_posts"], 1)
        self.assertEqual(productive["new_learnings"], 2)
        self.assertEqual(productive["new_decisions"], 1)

    def test_extract_highlights_includes_blog_and_commit(self):
        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            module.WWW_PATH = Path(self.temp_dir.name) / "website"
            module.DEVELOPER_PATH = Path(self.temp_dir.name) / "Developer"
            (self.mind_path / ".git").mkdir(parents=True, exist_ok=True)

            blog_path = module.WWW_PATH / "src" / "content" / "blog"
            write_text(
                blog_path / "post.md",
                """---
title: Highlight Post
pubDate: 2026-01-02
---
""",
            )

            def fake_run(args, capture_output=True, text=True, timeout=10):
                if "--grep=add" in args:
                    return _DummyCompleted("abcd123 add feature one\n")
                return _DummyCompleted("")

            with mock.patch.object(module.subprocess, "run", side_effect=fake_run):
                aggregator = module.RoundupAggregator("monthly", "2026-01")
                aggregator._aggregate_relational = lambda: {"total_messages": 250}
                aggregator._aggregate_productive = lambda: {"git_commits": 21, "repos_touched": 2}

                highlights = aggregator._extract_highlights()

        self.assertIn("Published: Highlight Post", highlights)
        self.assertTrue(any("add feature one" in h for h in highlights))
        self.assertTrue(any("Active week" in h for h in highlights))
        self.assertTrue(any("Productive week" in h for h in highlights))

    def test_current_period_uses_now(self):
        fixed_now = datetime(2026, 2, 15, 10, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            aggregator = module.RoundupAggregator("monthly")

        self.assertEqual(aggregator.period, "2026-02")

    def test_count_new_lines_ignores_outside_dates(self):
        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            aggregator = module.RoundupAggregator("monthly", "2026-01")
            file_path = self.mind_path / "memory" / "learnings.md"
            write_text(
                file_path,
                """# Learnings
## 2026-01-02
- In range

## 2026-02-01
- Out of range
""",
            )
            count = aggregator._count_new_lines(file_path, ["2026-01-02"])

        self.assertEqual(count, 1)

    def test_aggregate_reflective_counts_and_drift(self):
        write_text(self.mind_path / "memory" / "reflections" / "2026-01-02.md", "Reflection")
        write_text(
            self.mind_path / "logs" / "dream.log",
            "[2026-01-02 09:00:00] Dream cycle starting\n[2025-12-31 09:00:00] Dream cycle starting\n",
        )
        write_text(
            self.mind_path / "memory" / "questions.md",
            "## 2026-01-02\n- Q1\n- Q2\n",
        )
        write_text(
            self.mind_path / "memory" / "observations.md",
            "## 2026-01-02\n- O1\n",
        )
        write_text(
            self.mind_path / "state" / "drift-report.json",
            json.dumps({"drift_signals": ["a", "b", "c", "d"]}),
        )

        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            aggregator = module.RoundupAggregator("monthly", "2026-01")
            reflective = aggregator._aggregate_reflective()

        self.assertEqual(reflective["reflections_written"], 1)
        self.assertEqual(reflective["dream_cycles"], 1)
        self.assertEqual(reflective["questions_added"], 2)
        self.assertEqual(reflective["observations_added"], 1)
        self.assertEqual(reflective["drift_signals"], ["a", "b", "c"])

    def test_aggregate_reflective_handles_bad_drift(self):
        write_text(self.mind_path / "state" / "drift-report.json", "{bad json}")

        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            aggregator = module.RoundupAggregator("monthly", "2026-01")
            reflective = aggregator._aggregate_reflective()

        self.assertEqual(reflective["drift_signals"], [])

    def test_aggregate_relational_handles_bad_patterns(self):
        write_text(self.mind_path / "state" / "patterns.json", "{bad json}")

        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            aggregator = module.RoundupAggregator("monthly", "2026-01")
            relational = aggregator._aggregate_relational()

        self.assertEqual(relational["top_themes"], [])
        self.assertEqual(relational["conversations"], 0)

    def test_aggregate_productive_handles_numstat_and_timeout(self):
        (self.mind_path / ".git").mkdir(parents=True, exist_ok=True)

        def fake_run(args, capture_output=True, text=True, timeout=10):
            if "--numstat" in args:
                return _DummyCompleted("-\t-\tfile.txt\nbad\tline\n")
            return _DummyCompleted("")

        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            module.WWW_PATH = Path(self.temp_dir.name) / "website"
            module.DEVELOPER_PATH = Path(self.temp_dir.name) / "Developer"
            with mock.patch.object(module.subprocess, "run", side_effect=fake_run):
                aggregator = module.RoundupAggregator("monthly", "2026-01")
                productive = aggregator._aggregate_productive()

        self.assertEqual(productive["git_commits"], 0)
        self.assertEqual(productive["lines_added"], 0)
        self.assertEqual(productive["lines_deleted"], 0)

        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            module.WWW_PATH = Path(self.temp_dir.name) / "website"
            module.DEVELOPER_PATH = Path(self.temp_dir.name) / "Developer"
            with mock.patch.object(
                module.subprocess,
                "run",
                side_effect=module.subprocess.TimeoutExpired(cmd="git", timeout=10),
            ):
                aggregator = module.RoundupAggregator("monthly", "2026-01")
                productive = aggregator._aggregate_productive()

        self.assertEqual(productive["git_commits"], 0)

    def test_extract_highlights_limits_and_dedupes(self):
        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            module.WWW_PATH = Path(self.temp_dir.name) / "website"
            module.DEVELOPER_PATH = Path(self.temp_dir.name) / "Developer"
            (self.mind_path / ".git").mkdir(parents=True, exist_ok=True)

            blog_path = module.WWW_PATH / "src" / "content" / "blog"
            write_text(
                blog_path / "post1.md",
                "title: Post One\npubDate: 2026-01-02\n",
            )
            write_text(
                blog_path / "post2.md",
                "title: Post Two\npubDate: 2026-01-03\n",
            )

            def fake_run(args, capture_output=True, text=True, timeout=10):
                if "--grep=add" in args:
                    return _DummyCompleted("abcd123 add feature\nabcd124 add feature\n")
                return _DummyCompleted("")

            with mock.patch.object(module.subprocess, "run", side_effect=fake_run):
                aggregator = module.RoundupAggregator("monthly", "2026-01")
                aggregator._aggregate_relational = lambda: {"total_messages": 250}
                aggregator._aggregate_productive = lambda: {"git_commits": 30, "repos_touched": 3}
                highlights = aggregator._extract_highlights()

        self.assertLessEqual(len(highlights), 5)
        self.assertEqual(len([h for h in highlights if "add feature" in h]), 1)

    def test_to_markdown_no_highlights(self):
        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            aggregator = module.RoundupAggregator("monthly", "2026-01")
            data = {
                "generated_at": "2026-01-05T00:00:00",
                "date_range": {"start": "2026-01-01", "end": "2026-01-31"},
                "relational": {
                    "messages_sent": 0,
                    "messages_received": 0,
                    "conversations": 0,
                    "sessions": 0,
                    "avg_messages_per_day": 0,
                    "top_themes": [],
                },
                "productive": {
                    "git_commits": 0,
                    "lines_changed": 0,
                    "repos_touched": 0,
                    "blog_posts": 0,
                    "new_learnings": 0,
                    "new_decisions": 0,
                },
                "reflective": {
                    "reflections_written": 0,
                    "dream_cycles": 0,
                    "questions_added": 0,
                    "observations_added": 0,
                    "drift_signals": [],
                },
                "highlights": [],
            }

            md = aggregator._to_markdown(data)

        self.assertIn("No specific highlights captured this period", md)

    def test_save_writes_files(self):
        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            module.ROUNDUPS_PATH = Path(self.temp_dir.name) / "roundups"
            aggregator = module.RoundupAggregator("monthly", "2026-01")
            with mock.patch.object(
                aggregator,
                "aggregate",
                return_value={
                    "period": "2026-01",
                    "period_type": "monthly",
                    "date_range": {"start": "2026-01-01", "end": "2026-01-31"},
                    "generated_at": "2026-01-05T00:00:00",
                    "relational": {
                        "messages_sent": 0,
                        "messages_received": 0,
                        "conversations": 0,
                        "sessions": 0,
                        "avg_messages_per_day": 0,
                        "top_themes": [],
                    },
                    "productive": {
                        "git_commits": 0,
                        "lines_changed": 0,
                        "repos_touched": 0,
                        "blog_posts": 0,
                        "new_learnings": 0,
                        "new_decisions": 0,
                    },
                    "reflective": {
                        "reflections_written": 0,
                        "dream_cycles": 0,
                        "questions_added": 0,
                        "observations_added": 0,
                        "drift_signals": [],
                    },
                    "highlights": [],
                },
            ):
                output_file = aggregator.save()

        self.assertTrue(output_file.exists())
        self.assertTrue(output_file.with_suffix(".md").exists())

    def test_main_usage_and_invalid_period(self):
        with load_service_module(ROUNDUP_PATH, env=self.env) as module:
            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["roundup_aggregator.py"]), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    module.main()
            self.assertIn("Roundup Aggregator", buf.getvalue())

            buf = io.StringIO()
            with mock.patch.object(
                sys,
                "argv",
                ["roundup_aggregator.py", "daily"],
            ), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    module.main()
            self.assertIn("Invalid period type", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
