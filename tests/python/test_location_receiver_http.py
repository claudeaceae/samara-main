import http.client
import json
import os
import tempfile
import threading
import unittest
from pathlib import Path

from service_test_utils import load_service_module


LOCATION_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "services",
    "location-receiver",
    "server.py",
)


class LocationReceiverHttpTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = os.path.join(self.temp_dir.name, ".claude-mind")
        os.makedirs(self.mind_path, exist_ok=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_http_post_writes_location_state(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            try:
                server = location.HTTPServer(("127.0.0.1", 0), location.LocationHandler)
            except PermissionError:
                self.skipTest("Network sockets not permitted in this environment")
            thread = threading.Thread(target=server.serve_forever)
            thread.daemon = True
            thread.start()

            try:
                payload = {
                    "locations": [
                        {
                            "geometry": {"coordinates": [-73.0, 40.0, 0]},
                            "properties": {"speed": 0.4, "motion": ["walking"]}
                        }
                    ]
                }
                body = json.dumps(payload).encode()

                conn = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=5)
                try:
                    conn.request("POST", "/", body=body, headers={"Content-Type": "application/json"})
                    response = conn.getresponse()
                    response.read()
                finally:
                    conn.close()

                self.assertEqual(response.status, 200)

                state_file = Path(self.mind_path) / "state" / "location.json"
                history_file = Path(self.mind_path) / "state" / "location-history.jsonl"

                self.assertTrue(state_file.exists())
                self.assertTrue(history_file.exists())
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)

    def test_http_get_returns_health_text(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            try:
                server = location.HTTPServer(("127.0.0.1", 0), location.LocationHandler)
            except PermissionError:
                self.skipTest("Network sockets not permitted in this environment")
            thread = threading.Thread(target=server.serve_forever)
            thread.daemon = True
            thread.start()

            try:
                conn = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=5)
                try:
                    conn.request("GET", "/")
                    response = conn.getresponse()
                    data = response.read().decode()
                finally:
                    conn.close()

                self.assertEqual(response.status, 200)
                self.assertIn("Location receiver active", data)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)
