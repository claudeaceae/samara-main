# Smart Context Retrieval Plan

## Current State
- `ContextRouter` exists and is wired in `SenseRouter`, but iMessage/email/scratchpad still call `MemoryContext.buildContext()` in `Samara/Samara/main.swift`.
- `MemoryContext` already has `buildCoreContext()` and `buildSmartContext()` plus module loaders.
- `ContextCache` exists but is unused.
- Smart context path does not include hot digest/open threads (continuity risk).
- `ContextRouter` parsing expects raw JSON but the CLI returns a JSON wrapper, so Haiku classification likely falls back to keywords.

## Goals
- Cut context size from ~36K tokens to ~5-10K for conversational flows.
- Preserve continuity signals (hot digest + open threads).
- Keep privacy rules for collaborator profiles.
- Maintain a safe fallback to the legacy full-context path.

## Non-Goals
- Replace the stream, memory formats, or search storage.
- Add new model providers or embeddings layers.
- Overhaul message routing, TaskRouter, or ClaudeInvoker.

## Risks and Mitigations
- **Misclassification** → keyword fallback + optional full-context fallback.
- **Continuity loss** → include hot digest/open threads in core context.
- **Latency** → enforce short timeout for classification; keep logs for context size.
- **Context starvation** → search results included via FTS/Chroma when queries are present.

## Phased Plan (TDD-First)

### Phase 0: Baseline Tests
- Add unit tests for `ContextRouter` parsing + fallback behavior.
- Add tests for `MemoryContext.buildCoreContext()` and `buildSmartContext()` module inclusion.

### Phase 1: Router Correctness + Core Context
- Fix `ContextRouter` parsing to handle CLI JSON wrapper (`result` and `structured_output`).
- Extend classification schema to cover learnings/observations (with defaults).
- Ensure smart context path includes hot digest/open threads.

### Phase 2: iMessage Wiring (Primary Flow)
- Use `ContextRouter` + `buildSmartContext()` for iMessage batches.
- Respect `features.smartContext` / `features.smartContextTimeout`.
- Keep explicit fallback to legacy `buildContext()` when disabled.

### Phase 3: Other Surfaces (Email + Scratchpad)
- Apply the same smart-context selection for email and scratchpad flows.
- Keep legacy fallback for safety and debugging.

### Phase 4: Cache and Tune
- Integrate `ContextCache` for modules and search results.
- Add cache invalidation for memory file writes.
- Tune token budgets and module weights.

## Test Plan
- `ContextRouterTests`: parses CLI JSON wrappers; falls back when CLI missing.
- `MemoryContextTests`: core context includes digest/threads; smart context loads modules; privacy guard for collaborator profile.
- Integration smoke: iMessage flow builds smart context when enabled.

## Success Metrics
- Typical context size reduced to ~5-10K tokens on iMessage.
- Hot digest and open threads still present in session context.
- No regressions in privacy filtering for group chats.

## Rollback Plan
- Flip `features.smartContext` to `false`.
- If needed, revert `main.swift` to `buildContext()` usage.
