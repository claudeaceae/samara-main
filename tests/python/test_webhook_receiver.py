import asyncio
import hmac
import hashlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from service_test_utils import load_service_module, make_fastapi_stubs


WEBHOOK_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "services",
    "webhook-receiver",
    "server.py",
)


class WebhookReceiverTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = os.path.join(self.temp_dir.name, ".claude-mind")
        os.makedirs(self.mind_path, exist_ok=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_verify_signature_accepts_valid_sha256(self):
        payload = b'{"hello":"world"}'
        secret = "top-secret"
        digest = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()
        signature = f"sha256={digest}"

        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_fastapi_stubs()) as webhook:
            self.assertTrue(webhook.verify_signature(payload, signature, secret))
            self.assertFalse(webhook.verify_signature(payload, "sha256=bad", secret))

    def test_check_rate_limit_enforces_limits(self):
        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_fastapi_stubs()) as webhook:
            webhook.rate_limits.clear()
            self.assertTrue(webhook.check_rate_limit("test", "2/minute"))
            self.assertTrue(webhook.check_rate_limit("test", "2/minute"))
            self.assertFalse(webhook.check_rate_limit("test", "2/minute"))

    def test_load_config_creates_default_file(self):
        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_fastapi_stubs()) as webhook:
            config = webhook.load_config()
            config_path = Path(self.mind_path) / "credentials" / "webhook-secrets.json"

        self.assertTrue(config_path.exists())
        self.assertIn("test", config["sources"])
        self.assertEqual(config["sources"]["test"]["secret"], "test-secret")

    def test_create_sense_event_writes_payload(self):
        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_fastapi_stubs()) as webhook:
            data = {"action": "opened", "repository": {"full_name": "octo/repo"}}
            filename = webhook.create_sense_event("github", data, {"x-test": "1", "content-type": "json"})
            event_path = Path(self.mind_path) / "senses" / filename
            event = json.loads(event_path.read_text())

        self.assertEqual(event["sense"], "webhook")
        self.assertEqual(event["priority"], "normal")
        self.assertEqual(event["data"]["source"], "github")
        self.assertIn("x-test", event["data"]["headers"])

    def test_verify_signature_missing_and_rate_limit_variants(self):
        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_fastapi_stubs()) as webhook:
            self.assertFalse(webhook.verify_signature(b"payload", "", "secret"))
            webhook.rate_limits.clear()
            self.assertTrue(webhook.check_rate_limit("test", "bad"))
            self.assertTrue(webhook.check_rate_limit("test", "1/day"))
            self.assertFalse(webhook.check_rate_limit("test", "1/day"))

    def test_check_ip_allowed_and_priority(self):
        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_fastapi_stubs()) as webhook:
            self.assertTrue(webhook.check_ip_allowed("127.0.0.1", None))
            self.assertFalse(webhook.check_ip_allowed("10.0.0.1", ["127.0.0.1"]))

            priority = webhook.determine_priority("github", {"action": "opened"})
            self.assertEqual(priority, "normal")
            priority = webhook.determine_priority("github", {"action": "ping"})
            self.assertEqual(priority, "background")
            priority = webhook.determine_priority("github", {"note": "security alert"})
            self.assertEqual(priority, "immediate")
            self.assertEqual(webhook.determine_priority("other", {}), "normal")

    def test_generate_prompt_hint_variants(self):
        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_fastapi_stubs()) as webhook:
            self.assertIn("GitHub", webhook.generate_prompt_hint("github", {"action": "opened", "repository": {"full_name": "octo/repo"}}))
            self.assertIn("IFTTT", webhook.generate_prompt_hint("ifttt", {"triggerName": "demo"}))
            self.assertIn("Webhook from custom", webhook.generate_prompt_hint("custom", {}))

    def test_load_config_reads_existing(self):
        config_path = Path(self.mind_path) / "credentials" / "webhook-secrets.json"
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps({"sources": {"custom": {"secret": "abc"}}}))

        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_fastapi_stubs()) as webhook:
            config = webhook.load_config()

        self.assertIn("custom", config["sources"])

    def test_status_and_health_endpoints(self):
        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_fastapi_stubs()) as webhook:
            status = asyncio.run(webhook.status())
            health = asyncio.run(webhook.health_check())

        self.assertIn("registered_sources", status)
        self.assertEqual(health["status"], "healthy")

    def test_main_sets_config_path(self):
        stubs = make_fastapi_stubs()
        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=stubs) as webhook:
            config_path = Path(self.mind_path) / "credentials" / "custom.json"
            args = ["server.py", "--port", "9090", "--host", "127.0.0.1", "--config", str(config_path)]
            with mock.patch.object(sys, "argv", args):
                called = {}
                def fake_run(app, host=None, port=None):
                    called["host"] = host
                    called["port"] = port
                with mock.patch.object(webhook.uvicorn, "run", side_effect=fake_run):
                    webhook.main()

        self.assertEqual(webhook.WEBHOOK_CONFIG, config_path)
        self.assertEqual(called["host"], "127.0.0.1")
        self.assertEqual(called["port"], 9090)
