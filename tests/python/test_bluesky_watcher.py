import json
import os
import sys
import tempfile
import types
import unittest
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from service_test_utils import load_service_module


BLUESKY_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "services",
    "bluesky-watcher",
    "server.py",
)


class BlueskyWatcherTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = os.path.join(self.temp_dir.name, ".claude-mind")
        os.makedirs(self.mind_path, exist_ok=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_build_prompt_hint_summarizes_types(self):
        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            interactions = [{"type": "LIKE"}, {"type": "LIKE"}, {"type": "REPLY"}]
            hint = bluesky.build_prompt_hint(interactions)

        self.assertIn("2 likes", hint.lower())
        self.assertIn("1 reply", hint.lower())

    def test_write_sense_event_creates_file(self):
        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            interactions = [{"type": "FOLLOW", "author": "alice"}]
            bluesky.write_sense_event(interactions, priority="background")
            event_path = Path(self.mind_path) / "system" / "senses" / "bluesky.event.json"
            event = json.loads(event_path.read_text())

        self.assertEqual(event["sense"], "bluesky")
        self.assertEqual(event["data"]["count"], 1)
        self.assertEqual(event["priority"], "background")

    def test_fetch_notifications_filters_and_updates_state(self):
        class Author:
            def __init__(self, handle, did):
                self.handle = handle
                self.did = did

        class Notification:
            def __init__(self, reason, handle, did, indexed_at, record=None):
                self.reason = reason
                self.author = Author(handle, did)
                self.indexed_at = indexed_at
                self.record = record

        class Record:
            def __init__(self, text):
                self.text = text

        class Notifications:
            def __init__(self, notifications):
                self.notifications = notifications

        class Client:
            class App:
                class Bsky:
                    class Notification:
                        def __init__(self, notifications):
                            self._notifications = notifications

                        def list_notifications(self, params=None):
                            return Notifications(self._notifications)

                    def __init__(self, notifications):
                        self.notification = Client.App.Bsky.Notification(notifications)

                def __init__(self, notifications):
                    self.bsky = Client.App.Bsky(notifications)

            def __init__(self, notifications):
                self.app = Client.App(notifications)

        notifications = [
            Notification("follow", "newbie", "did:1", "2025-01-02T00:00:00Z"),
            Notification("reply", "bob", "did:2", "2025-01-01T12:00:00Z", record=Record("Hi there")),
        ]

        state = {"last_seen_at": "2025-01-01T00:00:00Z"}

        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            interactions = bluesky.fetch_notifications(Client(notifications), state)

        self.assertEqual(len(interactions), 2)
        self.assertEqual(state["last_seen_at"], "2025-01-02T00:00:00Z")

    def test_fetch_dms_returns_unread_messages(self):
        class Sender:
            def __init__(self, handle, did):
                self.handle = handle
                self.did = did

        class Message:
            def __init__(self, sender, text, message_id):
                self.sender = sender
                self.text = text
                self.id = message_id

        class Convo:
            def __init__(self, convo_id, unread_count):
                self.id = convo_id
                self.unread_count = unread_count

        class Messages:
            def __init__(self, messages):
                self.messages = messages

        class Convos:
            def __init__(self, convos):
                self.convos = convos

        class Client:
            def __init__(self):
                self.me = type("Me", (), {"did": "did:self"})()

                class Chat:
                    class Bsky:
                        class ConvoApi:
                            def list_convos(self):
                                return Convos([Convo("convo-1", 1)])

                            def get_messages(self, convo_id, limit):
                                sender = Sender("friend", "did:friend")
                                return Messages([Message(sender, "Hello", "msg-1")])

                        def __init__(self):
                            self.convo = Chat.Bsky.ConvoApi()

                    def __init__(self):
                        self.bsky = Chat.Bsky()

                self.chat = Chat()

        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            interactions = bluesky.fetch_dms(Client(), {})

        self.assertEqual(len(interactions), 1)
        self.assertEqual(interactions[0]["type"], "DM")

    def test_resolve_mind_dir_prefers_env(self):
        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            with mock.patch.dict(os.environ, {"SAMARA_MIND_PATH": "/tmp/samara"}, clear=True):
                self.assertEqual(bluesky.resolve_mind_dir(), "/tmp/samara")
            with mock.patch.dict(os.environ, {"MIND_PATH": "/tmp/mind"}, clear=True):
                self.assertEqual(bluesky.resolve_mind_dir(), "/tmp/mind")
            with mock.patch.dict(os.environ, {"HOME": "/tmp/home"}, clear=True):
                self.assertEqual(bluesky.resolve_mind_dir(), "/tmp/home/.claude-mind")

    def test_load_and_save_state_roundtrip(self):
        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            self.assertEqual(bluesky.load_state(), {"last_seen_at": None})
            state = {"last_seen_at": "2025-01-02T00:00:00Z"}
            bluesky.save_state(state)
            self.assertEqual(bluesky.load_state(), state)

    def test_load_credentials_missing_logs(self):
        logs = []

        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            with mock.patch.object(bluesky, "log", side_effect=logs.append):
                creds = bluesky.load_credentials()

        self.assertIsNone(creds)
        self.assertTrue(any("Error loading credentials" in line for line in logs))

    def test_fetch_notifications_formats_interactions(self):
        def make_notif(reason, handle, did, indexed_at, record=None):
            return SimpleNamespace(
                reason=reason,
                author=SimpleNamespace(handle=handle, did=did),
                indexed_at=indexed_at,
                record=record,
                uri=f"at://{did}/{reason}",
                cid=f"cid-{handle}",
            )

        record_reply = SimpleNamespace(
            text="Thanks for the update",
            reply=SimpleNamespace(
                parent=SimpleNamespace(uri="at://parent"),
                root=SimpleNamespace(uri="at://root"),
            ),
        )
        record_mention = SimpleNamespace(text="Ping from mention")

        notifications = [
            make_notif("like", "alice", "did:alice", "2025-01-03T00:00:00Z"),
            make_notif("reply", "bob", "did:bob", "2025-01-02T12:00:00Z", record=record_reply),
            make_notif("mention", "carol", "did:carol", "2025-01-02T11:00:00Z", record=record_mention),
            make_notif("quote", "dan", "did:dan", "2025-01-02T10:00:00Z"),
            make_notif("repost", "erin", "did:erin", "2025-01-02T09:00:00Z"),
            make_notif("mystery", "frank", "did:frank", "2025-01-02T08:00:00Z"),
            make_notif("follow", "old", "did:old", "2024-12-31T00:00:00Z"),
        ]

        class Client:
            class App:
                class Bsky:
                    class Notification:
                        def __init__(self, notifications):
                            self._notifications = notifications

                        def list_notifications(self, params=None):
                            return SimpleNamespace(notifications=self._notifications)

                    def __init__(self, notifications):
                        self.notification = Client.App.Bsky.Notification(notifications)

                def __init__(self, notifications):
                    self.bsky = Client.App.Bsky(notifications)

            def __init__(self, notifications):
                self.app = Client.App(notifications)

        state = {"last_seen_at": "2025-01-01T00:00:00Z"}

        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            interactions = bluesky.fetch_notifications(Client(notifications), state)

        self.assertEqual(len(interactions), 6)
        self.assertEqual(state["last_seen_at"], "2025-01-03T00:00:00Z")
        reply = next(i for i in interactions if i["type"] == "REPLY")
        self.assertIn("reply_text", reply)
        self.assertEqual(reply["parent_uri"], "at://parent")
        self.assertEqual(reply["root_uri"], "at://root")
        mention = next(i for i in interactions if i["type"] == "MENTION")
        self.assertIn("mention_text", mention)
        mystery = next(i for i in interactions if i["type"] == "MYSTERY")
        self.assertIn("mystery", mystery["text"])

    def test_fetch_notifications_handles_exception(self):
        class Client:
            class App:
                class Bsky:
                    class Notification:
                        def list_notifications(self, params=None):
                            raise RuntimeError("boom")

                    def __init__(self):
                        self.notification = Client.App.Bsky.Notification()

                def __init__(self):
                    self.bsky = Client.App.Bsky()

            def __init__(self):
                self.app = Client.App()

        logs = []
        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            with mock.patch.object(bluesky, "log", side_effect=logs.append):
                interactions = bluesky.fetch_notifications(Client(), {})

        self.assertEqual(interactions, [])
        self.assertTrue(any("Error fetching notifications" in line for line in logs))

    def test_fetch_dms_skips_own_and_handles_empty(self):
        class Sender:
            def __init__(self, handle, did):
                self.handle = handle
                self.did = did

        class Message:
            def __init__(self, sender, text, message_id):
                self.sender = sender
                self.text = text
                self.id = message_id

        class Convo:
            def __init__(self, convo_id, unread_count):
                self.id = convo_id
                self.unread_count = unread_count

        class Messages:
            def __init__(self, messages):
                self.messages = messages

        class Convos:
            def __init__(self, convos):
                self.convos = convos

        class Client:
            def __init__(self):
                self.me = type("Me", (), {"did": "did:self"})()

                class Chat:
                    class Bsky:
                        class ConvoApi:
                            def list_convos(self):
                                return Convos([Convo("convo-1", 2), Convo("convo-2", 0)])

                            def get_messages(self, convo_id, limit):
                                sender_self = Sender("me", "did:self")
                                sender_other = Sender("friend", "did:friend")
                                return Messages([
                                    Message(sender_self, "Ignore me", "msg-1"),
                                    Message(sender_other, "Hello", "msg-2"),
                                ])

                        def __init__(self):
                            self.convo = Chat.Bsky.ConvoApi()

                    def __init__(self):
                        self.bsky = Chat.Bsky()

                self.chat = Chat()

        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            interactions = bluesky.fetch_dms(Client(), {})

        self.assertEqual(len(interactions), 1)
        self.assertEqual(interactions[0]["message_id"], "msg-2")

    def test_fetch_dms_handles_exception(self):
        class Client:
            def __init__(self):
                self.me = type("Me", (), {"did": "did:self"})()

                class Chat:
                    class Bsky:
                        class ConvoApi:
                            def list_convos(self):
                                raise RuntimeError("boom")

                        def __init__(self):
                            self.convo = Chat.Bsky.ConvoApi()

                    def __init__(self):
                        self.bsky = Chat.Bsky()

                self.chat = Chat()

        logs = []
        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            with mock.patch.object(bluesky, "log", side_effect=logs.append):
                interactions = bluesky.fetch_dms(Client(), {})

        self.assertEqual(interactions, [])
        self.assertTrue(any("Error fetching DMs" in line for line in logs))

    def test_main_exits_without_atproto(self):
        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            real_import = __import__
            def fake_import(name, *args, **kwargs):
                if name == "atproto":
                    raise ImportError("nope")
                return real_import(name, *args, **kwargs)

            with mock.patch("builtins.__import__", side_effect=fake_import):
                with self.assertRaises(SystemExit):
                    bluesky.main()

    def test_main_exits_without_credentials(self):
        stub = types.ModuleType("atproto")
        stub.Client = type("Client", (), {"login": lambda *args, **kwargs: None})

        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            with mock.patch.dict(sys.modules, {"atproto": stub}):
                with mock.patch.object(bluesky, "load_credentials", return_value=None):
                    with self.assertRaises(SystemExit):
                        bluesky.main()

    def test_main_prioritizes_interactions(self):
        stub = types.ModuleType("atproto")
        stub.Client = type("Client", (), {"login": lambda *args, **kwargs: None})

        scenarios = [
            ([{"type": "DM"}], "immediate"),
            ([{"type": "MENTION"}], "normal"),
            ([{"type": "LIKE"}], "background"),
        ]

        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            with mock.patch.dict(sys.modules, {"atproto": stub}):
                with mock.patch.object(bluesky, "load_credentials", return_value={"handle": "me", "app_password": "pw"}):
                    with mock.patch.object(bluesky, "load_state", return_value={}):
                        with mock.patch.object(bluesky, "save_state"):
                            for interactions, expected in scenarios:
                                recorded = {}
                                with self.subTest(expected=expected):
                                    with mock.patch.object(bluesky, "fetch_notifications", return_value=interactions):
                                        with mock.patch.object(bluesky, "fetch_dms", return_value=[]):
                                            with mock.patch.object(bluesky, "write_sense_event", side_effect=lambda i, p: recorded.update(priority=p)):
                                                with mock.patch.object(bluesky, "log"):
                                                    bluesky.main()
                                self.assertEqual(recorded["priority"], expected)

    def test_main_logs_no_interactions(self):
        stub = types.ModuleType("atproto")
        stub.Client = type("Client", (), {"login": lambda *args, **kwargs: None})
        logs = []

        with load_service_module(BLUESKY_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as bluesky:
            with mock.patch.dict(sys.modules, {"atproto": stub}):
                with mock.patch.object(bluesky, "load_credentials", return_value={"handle": "me", "app_password": "pw"}):
                    with mock.patch.object(bluesky, "load_state", return_value={}):
                        with mock.patch.object(bluesky, "save_state"):
                            with mock.patch.object(bluesky, "fetch_notifications", return_value=[]):
                                with mock.patch.object(bluesky, "fetch_dms", return_value=[]):
                                    with mock.patch.object(bluesky, "log", side_effect=logs.append):
                                        bluesky.main()

        self.assertTrue(any("No new interactions" in line for line in logs))
