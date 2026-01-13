from __future__ import annotations

import os
from pathlib import Path


def get_mind_path() -> Path:
    """Resolve the Claude mind directory with environment overrides."""
    override = os.environ.get("SAMARA_MIND_PATH") or os.environ.get("MIND_PATH")
    if override:
        return Path(os.path.expanduser(override))
    return Path(os.path.expanduser("~/.claude-mind"))
