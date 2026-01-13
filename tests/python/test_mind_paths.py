import os
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../lib')))

from mind_paths import get_mind_path


class MindPathsTest(unittest.TestCase):
    def setUp(self):
        self._env = os.environ.copy()

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._env)

    def test_samara_mind_path_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.environ["SAMARA_MIND_PATH"] = tmp
            os.environ.pop("MIND_PATH", None)
            self.assertEqual(get_mind_path(), Path(tmp))

    def test_mind_path_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            override = os.path.join(tmp, "mind")
            os.environ.pop("SAMARA_MIND_PATH", None)
            os.environ["MIND_PATH"] = override
            self.assertEqual(get_mind_path(), Path(override))

    def test_default_uses_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.environ.pop("SAMARA_MIND_PATH", None)
            os.environ.pop("MIND_PATH", None)
            os.environ["HOME"] = tmp
            expected = Path(tmp) / ".claude-mind"
            self.assertEqual(get_mind_path(), expected)


if __name__ == "__main__":
    unittest.main()
