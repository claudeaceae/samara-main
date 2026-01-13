import json
import os
import tempfile
import unittest
from pathlib import Path

from service_test_utils import load_service_module


WEBHOOK_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "services",
    "webhook-receiver",
    "server.py",
)


try:
    from fastapi.testclient import TestClient
    FASTAPI_AVAILABLE = True
except Exception:
    FASTAPI_AVAILABLE = False


@unittest.skipUnless(FASTAPI_AVAILABLE, "fastapi not installed")
class WebhookReceiverHttpTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = os.path.join(self.temp_dir.name, ".claude-mind")
        os.makedirs(self.mind_path, exist_ok=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_webhook_accepts_valid_secret(self):
        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as webhook:
            config_path = Path(self.mind_path) / "credentials" / "webhook-secrets.json"
            config_path.parent.mkdir(parents=True, exist_ok=True)
            config_path.write_text(json.dumps({
                "sources": {
                    "test": {
                        "secret": "test-secret",
                        "allowed_ips": None,
                        "rate_limit": "60/minute"
                    }
                }
            }))
            client = TestClient(webhook.app)
            response = client.post(
                "/webhook/test",
                json={"triggerName": "demo"},
                headers={"x-webhook-secret": "test-secret"}
            )

            self.assertEqual(response.status_code, 200)
            payload = response.json()
            self.assertEqual(payload["status"], "accepted")

            senses_dir = Path(self.mind_path) / "senses"
            events = list(senses_dir.glob("webhook-test-*.event.json"))
            self.assertTrue(events)

            event = json.loads(events[0].read_text())
            self.assertEqual(event["data"]["source"], "test")

    def test_webhook_rejects_missing_auth(self):
        with load_service_module(WEBHOOK_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as webhook:
            config_path = Path(self.mind_path) / "credentials" / "webhook-secrets.json"
            config_path.parent.mkdir(parents=True, exist_ok=True)
            config_path.write_text(json.dumps({
                "sources": {
                    "test": {
                        "secret": "test-secret",
                        "allowed_ips": None,
                        "rate_limit": "60/minute"
                    }
                }
            }))
            client = TestClient(webhook.app)
            response = client.post(
                "/webhook/test",
                json={"triggerName": "demo"}
            )

            self.assertEqual(response.status_code, 401)
