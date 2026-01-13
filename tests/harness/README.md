# Test Harness

Use this harness to run tests without touching real runtime state or live services.

## Quick Start

```bash
source tests/harness/setup.sh
# run tests with SAMARA_MIND_PATH pointing at fixtures
source tests/harness/teardown.sh
```

## What It Does
- Sets `SAMARA_MIND_PATH` and `MIND_PATH` to an isolated temp directory.
- Overrides `HOME` so scripts that still use `~/.claude-mind` stay isolated.
- Prepends stub commands to `PATH` to avoid side effects.
- Copies fixture data from `tests/fixtures/claude-mind`.
- Sets `SAMARA_TEST_MODE=1` and defaults `CLAUDE_PATH` to the stubbed command.

## Stub Controls
Stubbed commands log to `SAMARA_STUB_LOG_FILE`. You can override output or exit codes per command:

- `SAMARA_STUB_STDOUT_<CMD>`
- `SAMARA_STUB_STDERR_<CMD>`
- `SAMARA_STUB_EXIT_CODE_<CMD>`

Example:

```bash
export SAMARA_STUB_EXIT_CODE_PGREP=0
export SAMARA_STUB_STDOUT_PGREP="12345"
```
