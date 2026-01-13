import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
BIRTH_SCRIPT = REPO_ROOT / "birth.sh"


class BirthScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_birth_creates_templates_and_launchd(self):
        if shutil.which("jq") is None:
            self.skipTest("jq not installed")

        config_path = self.temp_path / "config.json"
        config_path.write_text(json.dumps({
            "entity": {
                "name": "TestClaude",
                "icloud": "test@example.com",
                "bluesky": "@test",
                "github": "test-claude"
            },
            "collaborator": {
                "name": "Tester",
                "phone": "+15555550123",
                "email": "tester@example.com",
                "bluesky": "@tester"
            },
            "notes": {
                "location": "Test Location Log",
                "scratchpad": "Test Scratchpad"
            },
            "mail": {
                "account": "iCloud"
            }
        }))

        target_dir = self.temp_path / ".claude-mind"
        env = os.environ.copy()
        env["HOME"] = str(self.temp_path)
        env["SAMARA_MIND_PATH"] = str(target_dir)
        env["MIND_PATH"] = str(target_dir)

        result = subprocess.run(
            [str(BIRTH_SCRIPT), str(config_path), str(target_dir)],
            input="y\n",
            text=True,
            capture_output=True,
            cwd=str(REPO_ROOT),
            env=env,
            check=False,
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        identity_path = target_dir / "identity.md"
        self.assertTrue(identity_path.exists())
        identity_text = identity_path.read_text()
        self.assertIn("TestClaude", identity_text)
        self.assertNotIn("{{entity.name}}", identity_text)

        config_out = target_dir / "config.json"
        self.assertTrue(config_out.exists())
        config_data = json.loads(config_out.read_text())
        self.assertEqual(config_data["collaborator"]["name"], "Tester")

        about_link = target_dir / "memory" / "about-tester.md"
        self.assertTrue(about_link.exists())
        self.assertTrue(about_link.is_symlink())

        launchd_dir = target_dir / "launchd"
        wake_plist = launchd_dir / "com.claude.wake-adaptive.plist"
        self.assertTrue(wake_plist.exists())
        plist_text = wake_plist.read_text()
        self.assertIn("<string>com.claude.wake-adaptive</string>", plist_text)
        self.assertIn("<integer>900</integer>", plist_text)
        self.assertIn("<true/>", plist_text)

        wake_script = target_dir / "bin" / "wake-adaptive"
        self.assertTrue(wake_script.exists())
        self.assertTrue(wake_script.is_symlink())
