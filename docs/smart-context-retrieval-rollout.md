# Smart Context Retrieval Rollout

## What Changes
- Smart context builds a smaller core context plus selected modules.
- Cache metrics are logged per context build (tokens, cache hits/misses).

## Config Checklist
- `features.smartContext`: `true`
- `features.smartContextTimeout`: set to a safe timeout (default 5s)
- `services.location`: `true` if location context is expected
- `state/hot-digest.md`: keep up to date for continuity

## Verification
- Run `scripts/test-samara --verbose`.
- Send a message and confirm logs include `Context built (smart)`.
- Update a person profile or `state/location.json` and confirm cache invalidation logs.

## Rollback
- Set `features.smartContext` to `false` and restart Samara.
