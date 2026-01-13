import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from service_test_utils import load_service_module


GITHUB_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "services",
    "github-watcher",
    "server.py",
)


class GithubWatcherTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = os.path.join(self.temp_dir.name, ".claude-mind")
        os.makedirs(self.mind_path, exist_ok=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_build_prompt_hint_summarizes_reasons(self):
        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            interactions = [{"reason": "mention"}, {"reason": "mention"}, {"reason": "comment"}]
            hint = github.build_prompt_hint(interactions)

        self.assertIn("2 mentions", hint.lower())
        self.assertIn("1 comment", hint.lower())

    def test_fetch_notifications_parses_new_items(self):
        comment_url = "https://api.github.com/repos/octo/repo/issues/comments/1"
        subject_url = "https://api.github.com/repos/octo/repo/issues/2"
        notifications = [
            {
                "id": "1",
                "reason": "mention",
                "subject": {
                    "type": "Issue",
                    "title": "Bug report",
                    "url": subject_url,
                    "latest_comment_url": comment_url,
                },
                "repository": {"full_name": "octo/repo"},
            }
        ]

        def fake_run(args, capture_output=False, text=False, timeout=None):
            if args[:3] == ["gh", "api", "notifications?all=true"]:
                return SimpleNamespace(returncode=0, stdout=json.dumps(notifications), stderr="")
            if args[:2] == ["gh", "api"] and args[2] == comment_url:
                payload = {"body": "Looks good", "user": {"login": "alice"}, "html_url": "https://github.com"}
                return SimpleNamespace(returncode=0, stdout=json.dumps(payload), stderr="")
            if args[:2] == ["gh", "api"] and args[2] == subject_url:
                payload = {"html_url": "https://github.com/octo/repo/issues/2", "state": "open", "number": 2}
                return SimpleNamespace(returncode=0, stdout=json.dumps(payload), stderr="")
            return SimpleNamespace(returncode=0, stdout="{}", stderr="")

        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.object(github.subprocess, "run", side_effect=fake_run):
                state = {"seen_ids": [], "last_check": None}
                interactions = github.fetch_notifications(state)

        self.assertEqual(len(interactions), 1)
        self.assertEqual(state["seen_ids"], ["1"])
        self.assertIn("comment_body", interactions[0])
        self.assertIn("html_url", interactions[0])

    def test_write_sense_event_creates_file(self):
        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            interactions = [{"reason": "mention", "text": "Ping"}]
            github.write_sense_event(interactions, priority="immediate")
            event_path = Path(self.mind_path) / "senses" / "github.event.json"
            event = json.loads(event_path.read_text())

        self.assertEqual(event["sense"], "github")
        self.assertEqual(event["priority"], "immediate")
        self.assertEqual(event["data"]["count"], 1)

    def test_check_gh_auth_reports_success(self):
        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.object(github.subprocess, "run", return_value=SimpleNamespace(returncode=0)):
                self.assertTrue(github.check_gh_auth())

    def test_resolve_mind_dir_prefers_env(self):
        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.dict(os.environ, {"SAMARA_MIND_PATH": "/tmp/samara"}, clear=True):
                self.assertEqual(github.resolve_mind_dir(), "/tmp/samara")
            with mock.patch.dict(os.environ, {"MIND_PATH": "/tmp/mind"}, clear=True):
                self.assertEqual(github.resolve_mind_dir(), "/tmp/mind")
            with mock.patch.dict(os.environ, {"HOME": "/tmp/home"}, clear=True):
                self.assertEqual(github.resolve_mind_dir(), "/tmp/home/.claude-mind")

    def test_load_and_save_state_roundtrip(self):
        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            self.assertEqual(github.load_state(), {"seen_ids": [], "last_check": None})
            state = {"seen_ids": ["1"], "last_check": "2025-01-01T00:00:00Z"}
            github.save_state(state)
            self.assertEqual(github.load_state(), state)

    def test_check_gh_auth_handles_exception(self):
        logs = []
        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.object(github.subprocess, "run", side_effect=RuntimeError("boom")):
                with mock.patch.object(github, "log", side_effect=logs.append):
                    self.assertFalse(github.check_gh_auth())

        self.assertTrue(any("Error checking gh auth" in line for line in logs))

    def test_fetch_notifications_skips_seen_and_noise(self):
        notifications = [
            {
                "id": "1",
                "reason": "ci_activity",
                "subject": {"type": "Issue", "title": "Noise"},
                "repository": {"full_name": "octo/repo"},
            },
            {
                "id": "2",
                "reason": "mention",
                "subject": {"type": "Issue", "title": "Needs attention"},
                "repository": {"full_name": "octo/repo"},
            },
            {
                "id": "3",
                "reason": "assign",
                "subject": {"type": "PR", "title": "Assign me"},
                "repository": {"full_name": "octo/repo"},
            },
        ]

        def fake_run(args, capture_output=False, text=False, timeout=None):
            if args[:3] == ["gh", "api", "notifications?all=true"]:
                return SimpleNamespace(returncode=0, stdout=json.dumps(notifications), stderr="")
            return SimpleNamespace(returncode=0, stdout="{}", stderr="")

        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.object(github.subprocess, "run", side_effect=fake_run):
                state = {"seen_ids": ["3"], "last_check": None}
                interactions = github.fetch_notifications(state)

        reasons = {i["reason"] for i in interactions}
        self.assertIn("mention", reasons)
        self.assertNotIn("ci_activity", reasons)
        self.assertNotIn("assign", reasons)  # already seen
        self.assertIn("1", state["seen_ids"])

    def test_fetch_notifications_handles_errors(self):
        def fake_run_error(*args, **kwargs):
            return SimpleNamespace(returncode=1, stdout="", stderr="nope")

        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.object(github.subprocess, "run", side_effect=fake_run_error):
                interactions = github.fetch_notifications({"seen_ids": []})

        self.assertEqual(interactions, [])

        def fake_timeout(*args, **kwargs):
            raise github.subprocess.TimeoutExpired(cmd="gh", timeout=10)

        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.object(github.subprocess, "run", side_effect=fake_timeout):
                interactions = github.fetch_notifications({"seen_ids": []})

        self.assertEqual(interactions, [])

        def fake_exception(*args, **kwargs):
            raise RuntimeError("boom")

        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.object(github.subprocess, "run", side_effect=fake_exception):
                interactions = github.fetch_notifications({"seen_ids": []})

        self.assertEqual(interactions, [])

    def test_mark_notifications_read_handles_error(self):
        logs = []
        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.object(github.subprocess, "run", side_effect=RuntimeError("boom")):
                with mock.patch.object(github, "log", side_effect=logs.append):
                    github.mark_notifications_read()

        self.assertTrue(any("Error marking notifications read" in line for line in logs))

    def test_main_exits_when_auth_missing(self):
        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.object(github, "check_gh_auth", return_value=False):
                with self.assertRaises(SystemExit):
                    github.main()

    def test_main_prioritizes_interactions(self):
        scenarios = [
            ([{"reason": "mention"}], "immediate"),
            ([{"reason": "review_requested"}], "immediate"),
            ([{"reason": "comment"}], "normal"),
            ([{"reason": "assign"}], "background"),
        ]

        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.object(github, "check_gh_auth", return_value=True):
                with mock.patch.object(github, "load_state", return_value={"seen_ids": []}):
                    with mock.patch.object(github, "save_state"):
                        for interactions, expected in scenarios:
                            recorded = {}
                            with self.subTest(expected=expected):
                                with mock.patch.object(github, "fetch_notifications", return_value=interactions):
                                    with mock.patch.object(github, "write_sense_event", side_effect=lambda i, p: recorded.update(priority=p)):
                                        with mock.patch.object(github, "mark_notifications_read"):
                                            with mock.patch.object(github, "log"):
                                                github.main()
                            self.assertEqual(recorded["priority"], expected)

    def test_main_logs_no_interactions(self):
        logs = []
        with load_service_module(GITHUB_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as github:
            with mock.patch.object(github, "check_gh_auth", return_value=True):
                with mock.patch.object(github, "load_state", return_value={"seen_ids": []}):
                    with mock.patch.object(github, "save_state"):
                        with mock.patch.object(github, "fetch_notifications", return_value=[]):
                            with mock.patch.object(github, "log", side_effect=logs.append):
                                github.main()

        self.assertTrue(any("No new interactions" in line for line in logs))
