# Contiguous Memory System Postmortem and Next Steps

## Scope and goals

The contiguous memory system was built to unify every interaction surface into a
single, append-only event stream, then distill that stream into a compact hot
digest for session hydration. Goals for this phase:

- Cross-surface continuity (iMessage, CLI, wake/dream, services, senses).
- Append-only safety with fail-open behavior for writes.
- Auditable stream coverage with explicit gaps.
- Deterministic distillation path for dream cycles.
- Minimal drift between repo and runtime configuration.

## What shipped

Core stream:
- Daily shard files in `~/.claude-mind/stream/daily/events-YYYY-MM-DD.jsonl`.
- Sidecar distillation index `~/.claude-mind/stream/distilled-index.jsonl`.
- Legacy compatibility: `events.jsonl` and `events.legacy.jsonl`.

Hot digest:
- Adaptive windowing based on event density + velocity.
- Token-budgeted formatting by category (conversations, sessions, sense/system).
- CLI supports `--hours auto`, with config defaults.

Audit and telemetry:
- Stream audit with coverage, digest inclusion, and gap reporting.
- Surface expectations support (config-driven).
- Respect service toggles (disabled services do not count as missing surfaces).

Lifecycle:
- Dream cycle already calls stream distillation and archive.
- Migration tooling: `stream migrate-daily` and `stream rebuild-distilled-index`.

## Architecture changes (summary)

1. Stream storage
   - Writes now go to daily shards for scale and faster reads on time windows.
   - Distillation state moved to a sidecar index to keep the stream append-only.

2. Distillation
   - `mark-distilled` appends to `distilled-index.jsonl` and avoids stream rewrites.
   - `rebuild-distilled-index` rehydrates the sidecar from legacy flags if needed.

3. Adaptive hot digest
   - Event density (long rate) and velocity (short vs. mid window) determine the
     resolved window. The output is bounded by configured min/max values.

4. Audit coverage
   - Coverage now reports expected surfaces, missing surfaces, digest inclusion,
     and resolved hot digest windowing metrics.

## Configuration (runtime defaults)

The following keys control default behavior when CLI flags are absent:

- `stream.hot_digest.mode` (string) - `"auto"` or a numeric string.
- `stream.hot_digest.base_hours` (number)
- `stream.hot_digest.min_hours` (number)
- `stream.hot_digest.max_hours` (number)
- `stream.hot_digest.target_rate` (number)
- `stream.audit.window_hours` (number)
- `stream.audit.digest_hours` (number or `"auto"`)
- `stream.audit.expected_surfaces` (array of strings)

These defaults live in `config.example.json` and are copied into
`~/.claude-mind/config.json`.

## Migration and recovery

Migration flow:
1. `stream migrate-daily` - splits `events.jsonl` into daily shards and renames
   the legacy file to `events.legacy.jsonl`.
2. `stream rebuild-distilled-index` - rebuilds sidecar index if needed.

Recovery:
- Daily shards are append-only and archived by `stream archive`.
- `events.legacy.jsonl` is retained after migration for fallback.
- If a rebuild is needed, `rebuild-distilled-index` is idempotent.

## Operational runbook

Hot digest:
- `build-hot-digest --hours auto --no-ollama`
- `build-hot-digest --hours 12 --max-tokens 3000`

Stream audit:
- `stream-audit --digest-hours auto --format text`
- `stream-audit --hours 168 --format json --output ~/.claude-mind/state/stream-audit.json`

Distillation:
- `stream --format json undistilled --before YYYY-MM-DD`
- `stream mark-distilled --before YYYY-MM-DD`
- `stream archive --days 30`

## Validation and tests

Key tests:
- `tests/test_stream_writer.py` (daily shards, sidecar index).
- `tests/test_stream_cli.py` (migrate-daily, rebuild-distilled-index).
- `tests/test_stream_validator.py` (daily shard validation).
- `tests/test_hot_digest_builder.py` (adaptive windowing + config).
- `tests/test_stream_audit.py` (expected surfaces + disabled services).

Recommended manual checks:
- `stream stats`
- `stream validate`
- `stream-audit --format text`

## Known limitations and tradeoffs

- Distilled state is stored in a sidecar index; if index is lost, it must be
  rebuilt from stream flags or recomputed via distillation.
- Digest inclusion uses summary substring matching; it is a heuristic, not
  semantic scoring.
- Adaptive windowing is heuristic; tuning should follow real usage patterns.

## Next steps (optional)

1. Tuning and monitoring
   - Adjust `target_rate` and min/max hours using real-world telemetry.
   - Track changes in inclusion rate and resolved window hours over time.

2. Index lifecycle
   - Add periodic compaction or snapshotting for the distilled index if needed.

3. Digest fidelity
   - Explore stronger inclusion heuristics or embeddings to measure coverage.

4. Surface expansion
   - Add event generators for any missing surfaces and verify audit coverage.

## Closeout criteria

This phase is complete when:
- Stream writes are daily sharded and audit reports are healthy.
- Dream cycle continues to mark distilled events and archive without errors.
- Runtime config defaults are aligned with repo defaults.
- Drift checks pass (`sync-core` + `sync-organism --check`).
