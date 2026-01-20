"""
Test suite for ritual scripts (dream, wake) - especially session ID generation.

Run with: PYTHONPATH=. pytest tests/test_ritual_scripts.py -v
"""
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).parent.parent
SCRIPTS_DIR = REPO_ROOT / "scripts"


class TestUuidGeneration:
    """Tests for UUID generation used in ritual scripts."""

    def test_uuidgen_available(self):
        """uuidgen command is available on the system."""
        result = subprocess.run(
            ["uuidgen"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, "uuidgen command not available"

    def test_uuidgen_produces_valid_format(self):
        """uuidgen produces a valid UUID format."""
        result = subprocess.run(
            ["bash", "-c", "uuidgen | tr '[:upper:]' '[:lower:]'"],
            capture_output=True,
            text=True,
        )
        uuid = result.stdout.strip()

        # UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        uuid_pattern = r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        assert re.match(uuid_pattern, uuid), f"Invalid UUID format: {uuid}"

    def test_uuidgen_unique(self):
        """Multiple calls to uuidgen produce unique values."""
        uuids = []
        for _ in range(100):
            result = subprocess.run(
                ["bash", "-c", "uuidgen | tr '[:upper:]' '[:lower:]'"],
                capture_output=True,
                text=True,
            )
            uuids.append(result.stdout.strip())

        assert len(uuids) == len(set(uuids)), "UUIDs are not unique"


class TestDreamScript:
    """Tests for the dream script."""

    def test_dream_script_exists(self):
        """Dream script exists."""
        dream_script = SCRIPTS_DIR / "dream"
        assert dream_script.exists(), f"Dream script not found at {dream_script}"

    def test_dream_uses_uuid_for_session_id(self):
        """Dream script uses uuidgen for session ID."""
        dream_script = SCRIPTS_DIR / "dream"
        content = dream_script.read_text()

        # Should use uuidgen
        assert "uuidgen" in content, "Dream script should use uuidgen for session ID"

        # Should use SESSION_UUID variable
        assert "SESSION_UUID" in content, "Dream script should define SESSION_UUID"

        # Should pass UUID to --session-id
        assert '--session-id "$SESSION_UUID"' in content, (
            "Dream script should pass SESSION_UUID to --session-id"
        )

    def test_dream_does_not_use_date_session_id(self):
        """Dream script does not use date-based session ID format."""
        dream_script = SCRIPTS_DIR / "dream"
        content = dream_script.read_text()

        # Should NOT use the old pattern
        assert 'SESSION_ID="dream-$(date' not in content, (
            "Dream script should not use date-based SESSION_ID"
        )


class TestWakeScript:
    """Tests for the wake script."""

    def test_wake_script_exists(self):
        """Wake script exists."""
        wake_script = SCRIPTS_DIR / "wake"
        assert wake_script.exists(), f"Wake script not found at {wake_script}"

    def test_wake_uses_uuid_for_session_id(self):
        """Wake script uses uuidgen for session ID."""
        wake_script = SCRIPTS_DIR / "wake"
        content = wake_script.read_text()

        # Should use uuidgen
        assert "uuidgen" in content, "Wake script should use uuidgen for session ID"

        # Should use SESSION_UUID variable
        assert "SESSION_UUID" in content, "Wake script should define SESSION_UUID"

        # Should pass UUID to --session-id
        assert '--session-id "$SESSION_UUID"' in content, (
            "Wake script should pass SESSION_UUID to --session-id"
        )

    def test_wake_does_not_use_date_session_id(self):
        """Wake script does not use date-based session ID format."""
        wake_script = SCRIPTS_DIR / "wake"
        content = wake_script.read_text()

        # Should NOT use the old pattern
        assert 'SESSION_ID="wake-$(date' not in content, (
            "Wake script should not use date-based SESSION_ID"
        )


class TestWeeklyLogic:
    """Tests for weekly ritual logic in dream script."""

    def test_dream_has_weekly_detection(self):
        """Dream script detects Sundays for weekly rituals."""
        dream_script = SCRIPTS_DIR / "dream"
        content = dream_script.read_text()

        # Should check for Sunday (day 7 in %u format)
        assert "DAY_OF_WEEK" in content, "Dream should have DAY_OF_WEEK variable"
        assert '"7"' in content or "'7'" in content, (
            "Dream should check for Sunday (day 7)"
        )

    def test_dream_has_weekly_synthesis(self):
        """Dream script has weekly synthesis section."""
        dream_script = SCRIPTS_DIR / "dream"
        content = dream_script.read_text()

        # Should have weekly synthesis logic
        assert "weekly" in content.lower(), "Dream should have weekly logic"

    def test_dream_has_blog_post_logic(self):
        """Dream script has blog post generation."""
        dream_script = SCRIPTS_DIR / "dream"
        content = dream_script.read_text()

        # Should have blog post logic
        assert "blog" in content.lower(), "Dream should have blog post logic"


class TestScriptExecutability:
    """Tests that scripts are executable."""

    @pytest.mark.parametrize("script_name", ["dream", "wake"])
    def test_script_is_executable(self, script_name):
        """Script has executable permission."""
        script = SCRIPTS_DIR / script_name
        assert os.access(script, os.X_OK), f"{script_name} is not executable"

    @pytest.mark.parametrize("script_name", ["dream", "wake"])
    def test_script_has_shebang(self, script_name):
        """Script has proper shebang."""
        script = SCRIPTS_DIR / script_name
        content = script.read_text()
        assert content.startswith("#!/bin/bash"), f"{script_name} missing bash shebang"
