# Tests

This directory contains fixtures and a lightweight harness for safe, isolated testing.

## Layout
- `fixtures/`: Sample `~/.claude-mind` data used by tests.
- `harness/`: Scripts to set up an isolated test environment and stub side-effectful commands.

## Usage

```bash
source tests/harness/setup.sh
# Node (CLI) unit tests
node --test tests/node

# Python unit tests
python3 -m unittest discover -s tests/python

# Script tests (safe stubs + fixtures)
bash tests/scripts/run.sh
source tests/harness/teardown.sh
```
