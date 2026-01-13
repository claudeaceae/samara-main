import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WAKE_ADAPTIVE = REPO_ROOT / "scripts" / "wake-adaptive"


class WakeAdaptiveScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = Path(self.temp_dir.name) / ".claude-mind"
        (self.mind_path / "bin").mkdir(parents=True, exist_ok=True)
        (self.mind_path / "logs").mkdir(parents=True, exist_ok=True)
        (self.mind_path / "state").mkdir(parents=True, exist_ok=True)

        self._write_stub(
            self.mind_path / "bin" / "wake-scheduler",
            "#!/bin/bash\n"
            "if [ -n \"$WAKE_SCHEDULER_RESPONSE\" ]; then\n"
            "  printf '%s' \"$WAKE_SCHEDULER_RESPONSE\"\n"
            "else\n"
            "  printf '%s' '{\"should_wake\":false,\"type\":\"none\",\"reason\":\"none\"}'\n"
            "fi",
        )
        self._write_stub(
            self.mind_path / "bin" / "wake",
            "#!/bin/bash\n"
            "echo wake >> \"$MIND_PATH/state/wake-called\"",
        )
        self._write_stub(
            self.mind_path / "bin" / "wake-light",
            "#!/bin/bash\n"
            "echo wake-light >> \"$MIND_PATH/state/wake-called\"",
        )

    def tearDown(self):
        self.temp_dir.cleanup()

    def _write_stub(self, path: Path, contents: str):
        path.write_text(contents)
        path.chmod(0o755)

    def _run_script(self, extra_env=None, args=None):
        env = os.environ.copy()
        env["MIND_PATH"] = str(self.mind_path)
        env["SAMARA_MIND_PATH"] = str(self.mind_path)
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [str(WAKE_ADAPTIVE), *(args or [])],
            capture_output=True,
            text=True,
            cwd=str(REPO_ROOT),
            env=env,
            check=False,
        )

    def test_wake_adaptive_dispatches_full(self):
        if shutil.which("jq") is None:
            self.skipTest("jq not installed")

        response = '{"should_wake": true, "type": "full", "reason": "Scheduled"}'
        result = self._run_script(extra_env={"WAKE_SCHEDULER_RESPONSE": response})

        self.assertEqual(result.returncode, 0)
        marker = self.mind_path / "state" / "wake-called"
        self.assertTrue(marker.exists())
        self.assertIn("wake", marker.read_text())

        log_text = (self.mind_path / "logs" / "wake-adaptive.log").read_text()
        self.assertIn("Dispatching to full wake cycle", log_text)

    def test_wake_adaptive_force_light(self):
        if shutil.which("jq") is None:
            self.skipTest("jq not installed")

        result = self._run_script(args=["--force", "light"])

        self.assertEqual(result.returncode, 0)
        marker = self.mind_path / "state" / "wake-called"
        self.assertTrue(marker.exists())
        self.assertIn("wake-light", marker.read_text())
