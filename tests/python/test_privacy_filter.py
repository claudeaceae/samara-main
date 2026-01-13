import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../lib')))

import privacy_filter as privacy_module
from privacy_filter import (
    _to_range,
    _engagement_level,
    _filter_themes,
    _filter_highlights,
    filter_for_public,
)

FIXED_NOW = datetime(2026, 1, 2, 8, 30, 0)


class _FixedDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        return FIXED_NOW if tz is None else FIXED_NOW.replace(tzinfo=tz)


class PrivacyFilterTest(unittest.TestCase):
    def test_to_range_boundaries(self):
        self.assertEqual(_to_range(0), "0")
        self.assertEqual(_to_range(1), "< 10")
        self.assertEqual(_to_range(9), "< 10")
        self.assertEqual(_to_range(10), "10-50")
        self.assertEqual(_to_range(49), "10-50")
        self.assertEqual(_to_range(50), "50-100")
        self.assertEqual(_to_range(249), "100-250")
        self.assertEqual(_to_range(250), "250-500")
        self.assertEqual(_to_range(5000), "5000-10000")
        self.assertEqual(_to_range(10000), "10000+")

    def test_engagement_levels(self):
        self.assertEqual(_engagement_level(0), "quiet")
        self.assertEqual(_engagement_level(49), "quiet")
        self.assertEqual(_engagement_level(50), "moderate")
        self.assertEqual(_engagement_level(149), "moderate")
        self.assertEqual(_engagement_level(150), "active")
        self.assertEqual(_engagement_level(299), "active")
        self.assertEqual(_engagement_level(300), "highly active")

    def test_filter_themes_limits_and_whitelist(self):
        themes = [
            "Daily Life and Routines",
            "Secret Project",
            "Technical Implementation",
            "Memory and Continuity",
        ]
        filtered = _filter_themes(themes)
        self.assertEqual(filtered, [
            "Daily Life and Routines",
            "Technical Implementation",
            "Memory and Continuity",
        ])

    def test_filter_highlights_removes_sensitive(self):
        highlights = [
            "Call me at +15555550123",
            "Reach me at test@example.com",
            "Meet at 123 Main St",
            "Published a blog post",
            "Completed 3 commits",
        ]
        filtered = _filter_highlights(highlights)
        self.assertEqual(filtered, [
            "Published a blog post",
            "Completed 3 commits",
        ])

    def test_filter_for_public_shapes_output(self):
        data = {
            "period": "2026-W01",
            "period_type": "week",
            "generated_at": "2026-01-01T12:34:56Z",
            "relational": {
                "total_messages": 42,
                "conversations": 3,
                "top_themes": [
                    "daily life and routines",
                    "secret theme",
                    "technical implementation",
                ],
            },
            "productive": {
                "lines_changed": 120,
                "git_commits": 2,
                "repos_touched": 1,
                "blog_posts": 0,
                "new_learnings": 5,
                "new_decisions": 1,
            },
            "reflective": {
                "reflections_written": 1,
                "dream_cycles": 1,
                "questions_added": 2,
                "observations_added": 4,
                "drift_signals": ["signal-a", "signal-b"],
            },
            "highlights": [
                "Published a blog post",
                "Call me at +15555550123",
                "Completed 3 commits",
            ],
        }

        filtered = filter_for_public(data)

        self.assertEqual(filtered["period"], "2026-W01")
        self.assertEqual(filtered["period_type"], "week")
        self.assertEqual(filtered["generated_at"], "2026-01-01")
        self.assertEqual(filtered["relational"]["message_volume"], "10-50")
        self.assertEqual(filtered["relational"]["conversation_count"], "< 10")
        self.assertEqual(filtered["relational"]["top_themes"], [
            "daily life and routines",
            "technical implementation",
        ])
        self.assertEqual(filtered["productive"]["commit_count"], "< 10")
        self.assertEqual(filtered["reflective"]["patterns_noted"], 2)
        self.assertEqual(filtered["highlights"], [
            "Published a blog post",
            "Completed 3 commits",
        ])

    def test_to_public_markdown_includes_sections_and_highlights(self):
        data = {
            "period": "2026-W01",
            "period_type": "week",
            "relational": {
                "engagement_level": "active",
                "conversation_count": "10-50",
                "top_themes": ["daily life and routines", "technical implementation"],
            },
            "productive": {
                "code_activity": "50-100",
                "repos_active": 2,
                "commit_count": "10-50",
                "blog_posts": 1,
                "learnings_captured": "10-50",
            },
            "reflective": {
                "dream_cycles": 1,
                "reflection_sessions": 2,
                "questions_explored": "10-50",
            },
            "highlights": ["Shipped release"],
        }

        with mock.patch.object(privacy_module, "datetime", _FixedDatetime):
            md = privacy_module.to_public_markdown(data)

        self.assertIn('title: "Week Reflection: 2026-W01"', md)
        self.assertIn("pubDate: 2026-01-02", md)
        self.assertIn("## By the Numbers", md)
        self.assertIn("## Highlights", md)
        self.assertIn("- Shipped release", md)

    def test_main_requires_arguments(self):
        buf = io.StringIO()
        with mock.patch.object(sys, "argv", ["privacy_filter.py"]), contextlib.redirect_stdout(buf):
            with self.assertRaises(SystemExit):
                privacy_module.main()

        self.assertIn("Privacy Filter for Claude's public roundup posts.", buf.getvalue())

    def test_main_handles_missing_input(self):
        buf = io.StringIO()
        with mock.patch.object(
            sys,
            "argv",
            ["privacy_filter.py", "/tmp/does-not-exist.json", "out.json"],
        ), contextlib.redirect_stdout(buf):
            with self.assertRaises(SystemExit):
                privacy_module.main()

        self.assertIn("Error: Input file not found", buf.getvalue())

    def test_main_writes_json_output(self):
        data = {
            "period": "2026-W01",
            "period_type": "week",
            "generated_at": "2026-01-01T12:34:56Z",
        }

        with tempfile.TemporaryDirectory() as tmp:
            input_path = Path(tmp) / "input.json"
            output_path = Path(tmp) / "output.json"
            input_path.write_text(json.dumps(data))

            buf = io.StringIO()
            with mock.patch.object(
                sys,
                "argv",
                ["privacy_filter.py", str(input_path), str(output_path)],
            ), contextlib.redirect_stdout(buf):
                privacy_module.main()

            self.assertTrue(output_path.exists())
            self.assertIn("Filtered JSON saved to:", buf.getvalue())
            output = json.loads(output_path.read_text())
            self.assertTrue(output["public"])

    def test_main_writes_markdown_file(self):
        data = {
            "period": "2026-W01",
            "period_type": "week",
        }

        with tempfile.TemporaryDirectory() as tmp:
            input_path = Path(tmp) / "input.json"
            output_path = Path(tmp) / "output.md"
            input_path.write_text(json.dumps(data))

            buf = io.StringIO()
            with mock.patch.object(
                sys,
                "argv",
                ["privacy_filter.py", str(input_path), "--markdown", str(output_path)],
            ), mock.patch.object(privacy_module, "datetime", _FixedDatetime), contextlib.redirect_stdout(buf):
                privacy_module.main()

            self.assertTrue(output_path.exists())
            self.assertIn("Markdown saved to:", buf.getvalue())
            self.assertIn("pubDate: 2026-01-02", output_path.read_text())

    def test_main_prints_markdown_without_output_path(self):
        data = {"period": "2026-W01", "period_type": "week"}

        with tempfile.TemporaryDirectory() as tmp:
            input_path = Path(tmp) / "input.json"
            input_path.write_text(json.dumps(data))

            buf = io.StringIO()
            with mock.patch.object(
                sys,
                "argv",
                ["privacy_filter.py", str(input_path), "--markdown"],
            ), mock.patch.object(
                privacy_module, "to_public_markdown", return_value="MARKDOWN"
            ), contextlib.redirect_stdout(buf):
                privacy_module.main()

            self.assertEqual(buf.getvalue().strip(), "MARKDOWN")


if __name__ == "__main__":
    unittest.main()
