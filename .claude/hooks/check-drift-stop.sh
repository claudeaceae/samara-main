#!/bin/bash
# Stop hook: Check for system drift at end of session
#
# This hook runs when a Claude session ends. If drift is detected,
# it reminds Claude to consider syncing before the next session.
#
# Input: JSON with session info on stdin
# Output: JSON with {ok: boolean, message?: string}

INPUT=$(cat)

# Run drift check (quick, just exit status)
if ~/.claude-mind/bin/sync-organism --check >/dev/null 2>&1; then
    # No drift, nothing to say
    echo '{"ok": true}'
else
    # Drift detected
    DRIFT_SUMMARY=$(~/.claude-mind/bin/sync-organism 2>&1 | grep -E "^(Repo scripts|Runtime scripts|Only in|Differ|Total drift)" | head -6)

    echo "{\"ok\": true, \"message\": \"System drift detected. Consider running /sync or syncing scripts to repo before next session.\n\nQuick summary:\n$DRIFT_SUMMARY\"}"
fi
