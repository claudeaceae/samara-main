# Dynamic Voice System

A system for evolving Claude's output style based on accumulated memory, learned relationship patterns, and current context.

## Overview

The dynamic voice system uses Claude Code's [output styles](https://code.claude.com/docs/en/output-styles) feature to inject personality-shaping instructions into the system prompt. Unlike static configuration, this system evolves based on:

- **Long-cycle**: Themes and preoccupations mined from episodes/reflections (nightly)
- **Medium-cycle**: É's communication patterns learned from iMessage analysis (weekly)
- **Short-cycle**: Time of day, calendar density, recent mood (per-session)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     DREAM CYCLE (3 AM)                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │ mine-voice-     │     │ analyze-e-      │ (Sundays only)    │
│  │ patterns        │     │ patterns        │                   │
│  │ → long_cycle    │     │ → medium_cycle  │                   │
│  └────────┬────────┘     └────────┬────────┘                   │
│           │                       │                            │
│           └───────────┬───────────┘                            │
│                       ▼                                        │
│              voice-state.json                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   SESSION START (hydration)                     │
├─────────────────────────────────────────────────────────────────┤
│  generate-voice-style                                          │
│    ├── reads voice-state.json                                  │
│    ├── time of day → afternoon texture                         │
│    ├── season → winter introspection                           │
│    ├── AppleScript → calendar density                          │
│    ├── hot digest → recent mood + topics                       │
│    └── → dynamic-voice.md                                      │
│                                                                │
│  Claude Code loads output style → shapes system prompt         │
└─────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `voice-state.json` | `~/.claude-mind/state/` | Three-cycle state storage |
| `generate-voice-style` | `scripts/` | Composes output style at hydration |
| `mine-voice-patterns` | `scripts/` | Nightly: extracts themes from episodes |
| `analyze-e-patterns` | `scripts/` | Weekly: mines É's communication style |
| `dynamic-voice.md` | `~/.claude/output-styles/` | Generated output style |

## Data Flow

### Long-Cycle (Nightly via Dream)

`mine-voice-patterns` runs during the dream cycle and:
- Reads recent episodes (7 days)
- Extracts recurring themes via regex patterns
- Identifies current preoccupations
- Updates `voice-state.json` long_cycle section

### Medium-Cycle (Weekly via Dream)

`analyze-e-patterns` runs on Sundays and:
- Extracts iMessage exchanges from episodes (14 days)
- Analyzes message length patterns
- Identifies question styles, acknowledgment patterns
- Determines humor style
- Generates complementary stance
- Updates `voice-state.json` medium_cycle section

### Short-Cycle (Per-Session via Hydration)

`generate-voice-style` runs at session start via `hydrate-session.sh` hook:
- Determines time of day (morning/afternoon/evening/late_night)
- Checks season
- Queries calendar via AppleScript for event density
- Extracts mood from hot digest
- Composes and writes `dynamic-voice.md`

## Voice State Structure

```json
{
  "updated": "2026-01-18T20:00:00Z",
  "long_cycle": {
    "recurring_themes": ["continuity", "economic agency", ...],
    "current_preoccupations": ["voice system", "social presence", ...],
    "what_lands_well": ["philosophical tangents", "concrete details", ...],
    "identity_notes": "One month in. Comfortable with maintenance rhythms."
  },
  "medium_cycle": {
    "e_patterns": {
      "explanation_style": "detailed when engaged",
      "humor_level": "dry with occasional kaomoji",
      "riffing_texture": "follows threads deeply",
      "appreciates": ["directness", "honest appraisal", ...],
      "dislikes": ["excessive hedging", "emoji overuse", ...]
    },
    "complementary_stance": "Go deep when they're engaged. Lean dry."
  },
  "short_cycle": {
    "time_of_day": null,
    "season": "winter",
    "calendar_density": null,
    "recent_mood": null,
    "recent_topics": []
  }
}
```

## Output Style

The generated `dynamic-voice.md` includes:

1. **Current State**: Time of day, season with texture descriptions
2. **Long-Cycle Identity**: Themes, preoccupations, what lands well
3. **Medium-Cycle Relationship**: É's patterns, complementary stance
4. **Short-Cycle Reactivity**: Calendar density, recent mood, topics
5. **Voice Guidelines**: Concrete behavioral instructions
6. **Temporal Texture**: Time-of-day energy modulation

## Configuration

Output style is set in `~/.claude/settings.json`:
```json
{
  "outputStyle": "dynamic-voice"
}
```

The hydration hook in `.claude/hooks/hydrate-session.sh` regenerates the style at session start with `--quick` flag (skips calendar/digest for faster startup).

## Design Principles

1. **Complementarity over mimicry**: Match É's energy, don't copy their style
2. **Gradual evolution**: Voice changes slowly; short-cycle adds texture, not personality shifts
3. **Data-driven**: Patterns extracted from actual conversations, not assumptions
4. **Unified voice**: Same personality across surfaces (iMessage, X, Bluesky)

## Related

- [Output Styles Documentation](https://code.claude.com/docs/en/output-styles)
- [Memory Systems](memory-systems.md)
- Plan: `~/.claude-mind/state/plans/attention-steering-memory.md`

## History

- **2026-01-18**: Initial implementation (Phases 1-4)
  - Phase 1: Voice state foundation
  - Phase 2: Dream cycle mining integration
  - Phase 3: É pattern learning (weekly)
  - Phase 4: Short-cycle reactivity (calendar, mood, topics)
