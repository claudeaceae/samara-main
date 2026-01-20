"""
Tests for the sync-core script stream logging.
"""
from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).parent.parent
SCRIPTS_DIR = REPO_ROOT / "scripts"


def test_sync_core_emits_system_stream_event():
    script = SCRIPTS_DIR / "sync-core"
    content = script.read_text()

    assert "--surface system" in content
    assert "--type system" in content
    assert "--direction internal" in content


def test_sync_core_syncs_lib_dir():
    script = SCRIPTS_DIR / "sync-core"
    content = script.read_text()

    assert "sync_lib" in content
    assert "## Lib" in content
    assert "$REPO_DIR/lib" in content
    assert "$MIND_PATH/lib" in content
