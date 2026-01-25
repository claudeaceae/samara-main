# Tests

Test suite for the Samara project. Tests are organized by type and coverage area.

---

## Quick Start

```bash
# Run all Python tests
python3 -m pytest tests/ -v

# Run specific test categories
python3 -m pytest tests/python/ -v          # Service and lib tests
python3 -m pytest tests/test_stream*.py -v  # Stream system tests

# Run script tests (requires harness)
source tests/harness/setup.sh
bash tests/scripts/run.sh
source tests/harness/teardown.sh

# Run Node.js tests
node --test tests/node/
```

---

## Test Structure

```
tests/
├── README.md                  # This file
├── fixtures/                  # Test data (mock ~/.claude-mind)
│   └── claude-mind/           # 4-domain fixture structure
│       ├── config.json
│       ├── self/              # identity, goals, credentials
│       ├── memory/            # episodes, people, learnings
│       ├── state/             # location, triggers, services
│       └── system/            # logs, senses
├── harness/                   # Test isolation infrastructure
│   ├── setup.sh               # Creates isolated test environment
│   ├── teardown.sh            # Cleans up test environment
│   ├── stubs/                 # Stubbed commands (osascript, gh, etc.)
│   └── README.md              # Harness documentation
├── python/                    # Python unit tests
│   ├── test_*.py              # Service and lib tests
│   └── service_test_utils.py  # Test utilities
├── node/                      # Node.js tests (CLI)
│   └── *.test.mjs             # CLI validation, context, utilities
├── scripts/                   # Shell script integration tests
│   └── run.sh                 # Script test runner
└── test_*.py                  # Root-level tests (stream system)
```

---

## Test Categories

### Service Tests (`tests/python/`)

Tests for background services in `services/`:

| Test File | Service | Coverage |
|-----------|---------|----------|
| `test_location_receiver.py` | location-receiver | Trip segmentation, GPS processing |
| `test_location_receiver_http.py` | location-receiver | HTTP endpoint |
| `test_webhook_receiver.py` | webhook-receiver | Signature verification, rate limiting |
| `test_webhook_receiver_http.py` | webhook-receiver | HTTP endpoint |
| `test_bluesky_watcher.py` | bluesky-watcher | Notification fetching, DMs |
| `test_github_watcher.py` | github-watcher | Notification parsing |
| `test_mcp_memory_bridge.py` | mcp-memory-bridge | MCP tools |
| `test_wake_scheduler.py` | wake-scheduler | Schedule calculation |

### Library Tests (`tests/python/`)

Tests for Python utilities in `lib/`:

| Test File | Library | Coverage |
|-----------|---------|----------|
| `test_mind_paths.py` | mind_paths.py | Path resolution |
| `test_chroma_helper.py` | chroma_helper.py | Semantic search |
| `test_pattern_analyzer.py` | pattern_analyzer.py | Pattern detection |
| `test_calendar_analyzer.py` | calendar_analyzer.py | Calendar events |
| `test_weather_helper.py` | weather_helper.py | Weather API |
| `test_privacy_filter.py` | privacy_filter.py | PII filtering |
| `test_location_analyzer.py` | location_analyzer.py | Location patterns |
| `test_trigger_evaluator.py` | trigger_evaluator.py | Proactive triggers |
| `test_roundup_aggregator.py` | roundup_aggregator.py | Content aggregation |
| `test_question_synthesizer.py` | question_synthesizer.py | Question generation |

### Stream System Tests (`tests/`)

Tests for the unified event stream:

| Test File | Coverage |
|-----------|----------|
| `test_stream_writer.py` | Event creation, JSONL writing |
| `test_stream_distill.py` | Event distillation |
| `test_stream_metrics.py` | Metrics calculation |
| `test_stream_validator.py` | Schema validation |
| `test_stream_cli.py` | CLI commands |
| `test_stream_audit.py` | Audit functionality |
| `test_hot_digest_builder.py` | Digest building |
| `test_distill_async.py` | Async distillation |
| `test_thread_indexer.py` | Thread indexing |

### Script Tests (`tests/python/`, `tests/scripts/`)

Tests for shell scripts in `scripts/`:

| Test File | Scripts |
|-----------|---------|
| `test_birth_script.py` | birth.sh |
| `test_update_samara_script.py` | update-samara |
| `test_wake_adaptive_script.py` | wake-adaptive |
| `test_sync_core_script.py` | sync-core |
| `test_ritual_scripts.py` | dream, wake |
| `scripts/run.sh` | message, send-attachment, etc. |

### CLI Tests (`tests/node/`)

Tests for Claude Code CLI integration:

| Test File | Coverage |
|-----------|----------|
| `cli-context.test.mjs` | Context loading |
| `cli-shell-utils.test.mjs` | Shell utilities |
| `cli-validation.test.mjs` | Input validation |

---

## Test Harness

The harness provides isolated testing without touching real runtime state.

### What It Does

1. Creates temp directory for `SAMARA_MIND_PATH`
2. Copies fixture data to temp location
3. Overrides `HOME` for isolation
4. Prepends stub commands to `PATH`
5. Sets `SAMARA_TEST_MODE=1`

### Stub Commands

Located in `harness/stubs/`, these prevent side effects:

- `osascript` - AppleScript (Messages, Calendar, etc.)
- `gh` - GitHub CLI
- `claude` - Claude Code CLI
- `launchctl` - Service management
- `open`, `curl`, `brew`, `codesign`, `xcodebuild`

### Controlling Stubs

```bash
# Override stdout
export SAMARA_STUB_STDOUT_PGREP="12345"

# Override exit code
export SAMARA_STUB_EXIT_CODE_PGREP=0

# Check stub logs
cat "$SAMARA_STUB_LOG_FILE"
```

---

## Fixtures

The `fixtures/claude-mind/` directory mirrors the 4-domain runtime structure:

```
fixtures/claude-mind/
├── config.json              # Test configuration
├── self/
│   ├── identity.md
│   ├── goals.md
│   ├── capabilities/
│   │   └── inventory.md
│   └── credentials/
│       ├── bluesky.json
│       └── webhook-secrets.json
├── memory/
│   ├── episodes/
│   │   └── 2026-01-01.md
│   ├── people/
│   │   └── tester/profile.md
│   ├── learnings.md
│   ├── observations.md
│   ├── decisions.md
│   └── questions.md
├── state/
│   ├── location.json
│   ├── places.json
│   ├── subway-stations.json
│   ├── location-history.jsonl
│   ├── trips.jsonl
│   ├── triggers/triggers.json
│   └── proactive-queue/queue.json
└── system/
    ├── logs/
    └── senses/
```

---

## Running Tests

### Prerequisites

```bash
# Python dependencies
pip install pytest chromadb

# For service tests with HTTP clients
pip install fastapi uvicorn httpx
```

### CI Integration

Tests run on every PR via GitHub Actions. See `.github/workflows/test.yml`.

### Coverage

```bash
# Run with coverage
python3 -m pytest tests/ --cov=lib --cov=services --cov-report=html
```

---

## Writing Tests

### Service Tests

Use `service_test_utils.py` to load service modules with environment overrides:

```python
from service_test_utils import load_service_module

def test_something(self):
    with load_service_module(SERVICE_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as service:
        result = service.some_function()
        self.assertEqual(result, expected)
```

### Path Conventions

Always use 4-domain paths in tests:
- `self/credentials/` not `credentials/`
- `system/senses/` not `senses/`
- `system/logs/` not `logs/`

### Adding New Tests

1. Create test file in appropriate directory
2. Follow existing naming: `test_<component>.py`
3. Use temp directories for isolation
4. Add to this README if it's a new category
