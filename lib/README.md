# lib/

Python utilities and Bash helpers that power Samara's scripts and services.

All files are symlinked to `~/.claude-mind/system/lib/` at runtime.

---

## Core Infrastructure

| File | Purpose |
|------|---------|
| `config.sh` | Bash config helper. Source it to get config values with fallbacks. |
| `mind_paths.py` | Python path resolution. `get_mind_path()` returns `~/.claude-mind` with env overrides. |

---

## Memory & Search

| File | Purpose |
|------|---------|
| `chroma_helper.py` | Chroma vector DB wrapper. `MemoryIndex` for curated memory, `TranscriptIndex` for raw transcripts. |
| `transcript_indexer.py` | JSONL parser for Claude Code session transcripts. Extracts thinking blocks, user messages, assistant text. |
| `archive_index_cli.py` | CLI implementation for `archive-index` script. Rebuild, sync, search transcript archive. |

**Usage:**
```python
from chroma_helper import MemoryIndex, TranscriptIndex

# Curated memory search
index = MemoryIndex()
results = index.search("coffee shops")

# Transcript archive search
archive = TranscriptIndex()
results = archive.search("model fallback implementation")
```

---

## Unified Event Stream

The contiguous memory system - captures all interactions across surfaces.

| File | Purpose |
|------|---------|
| `stream_writer.py` | Core event writer. `StreamWriter`, `Event`, `Surface`, `EventType`, `Direction` classes. |
| `stream_cli.py` | CLI for stream operations. Write events, query, mark distilled, archive. |
| `stream_distill.py` | Converts undistilled events into narrative summaries. |
| `stream_metrics.py` | Metrics helpers for adaptive digest windowing. |
| `stream_validator.py` | Schema validation for stream events. |
| `stream_audit.py` | Coverage and digest inclusion metrics. |

**Usage:**
```python
from lib.stream_writer import StreamWriter, Surface, EventType, Direction

writer = StreamWriter()
event = writer.create_event(
    surface=Surface.CLI,
    event_type=EventType.INTERACTION,
    direction=Direction.INBOUND,
    summary="User asked about memory architecture"
)
writer.write(event)
```

---

## Context & Awareness

Analyzers for proactive engagement and situational awareness.

| File | Purpose |
|------|---------|
| `hot_digest_builder.py` | Builds session hydration digests from recent events. Uses qwen3:8b via Ollama. |
| `calendar_analyzer.py` | Calendar event analysis. Upcoming events, recently ended, recurring detection. |
| `location_analyzer.py` | Location/place analysis. Arrival/departure detection, movement patterns. |
| `pattern_analyzer.py` | Behavioral pattern detection. Temporal rhythms, topic recurrence, anomalies. |
| `trigger_evaluator.py` | Proactive engagement decision-making. Combines signals, applies safeguards. |
| `weather_helper.py` | Weather data via Open-Meteo API. No API key required. |

**Usage:**
```python
from trigger_evaluator import TriggerEvaluator

evaluator = TriggerEvaluator()
decision = evaluator.evaluate()
if decision["should_engage"]:
    # Send proactive message
```

---

## Questions & Threads

| File | Purpose |
|------|---------|
| `question_synthesizer.py` | Generates contextual questions. Observational, introspective, exploratory, connective. |
| `thread_indexer.py` | Parses session handoffs, updates `threads.json` for open thread tracking. |

---

## Analytics

| File | Purpose |
|------|---------|
| `roundup_aggregator.py` | Metrics aggregation for weekly/monthly/yearly roundups. Relational, productive, reflective. |
| `privacy_filter.py` | Sanitizes roundup data for public sharing. Removes PII, generalizes specifics. |

**Usage:**
```bash
# Generate weekly roundup
python3 roundup_aggregator.py weekly 2026-W03

# Filter for public blog
python3 privacy_filter.py input.json output.json
```

---

## Import Patterns

**From scripts (with venv):**
```python
# Scripts typically run from ~/.claude-mind with venv active
from chroma_helper import MemoryIndex
from mind_paths import get_mind_path
```

**From lib modules (relative imports):**
```python
from .mind_paths import get_mind_path
from lib.stream_writer import StreamWriter
```

**From services:**
```python
# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from chroma_helper import MemoryIndex
```

---

## Adding New Libraries

1. Create the Python file in `lib/`
2. Run `symlink-scripts --apply` to create runtime symlink
3. Import using `mind_paths.get_mind_path()` for path resolution
4. Document here
