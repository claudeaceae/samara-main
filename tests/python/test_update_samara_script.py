import os
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
UPDATE_SCRIPT = REPO_ROOT / "scripts" / "update-samara"


class UpdateSamaraScriptTests(unittest.TestCase):
    def test_update_samara_refuses_in_test_mode(self):
        env = os.environ.copy()
        env["SAMARA_TEST_MODE"] = "1"

        result = subprocess.run(
            [str(UPDATE_SCRIPT)],
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to run update-samara in SAMARA_TEST_MODE", result.stderr)
