# Session Handoff: Meeting Briefing/Debriefing Investigation

**Date:** 2026-01-28
**Participants:** É (collaborator), Claude (investigator)
**Status:** Planning phase — implementation pending user approval

---

## Open Threads

### 1. AppleScript Timeout Root Cause (CRITICAL)
- **Issue:** CalendarAnalyzer fails silently due to 10-second timeout when querying attendees via AppleScript
- **Impact:** Zero calendar events detected despite É having active meetings
- **Location:** `lib/calendar_analyzer.py`, lines 271-285 (attendee extraction), line 301 (timeout=10)
- **Evidence:** Logs show "Found 0 meetings needing prep/debrief" repeatedly
- **Status:** Root cause identified; fix strategy being designed

### 2. Fix Strategy Decision Point
- **Three candidate approaches discussed:**
  1. **Option A (Band-aid):** Increase timeout from 10 to 30 seconds — quick but blocks system
  2. **Option B (Recommended):** Remove attendee query from AppleScript, fetch separately — balances speed and functionality
  3. **Option C (Comprehensive):** Switch to PyObjC for native Calendar.app API — complex but performant
- **Status:** É requesting plan before implementation; needs research on trade-offs

### 3. Dependent Systems Broken by AppleScript Timeout
- `meeting-check` service: Finds zero meetings (should find prep/debrief windows)
- `calendar-check` script: Reports "0 high-confidence triggers"
- `wake-adaptive` scheduler: Cannot trigger early wake for imminent meetings (relies on calendar-cache.json)
- `morning-briefing`: Unaffected (uses web APIs, not calendar_analyzer)

### 4. Attendee Profile Integration Question
- Meeting handlers load attendee profiles from `~/.claude-mind/memory/people/`
- If we defer attendee fetching, how should we handle cases where profiles don't exist?
- Should missing attendee profiles cause graceful degradation or skip message entirely?
- **Status:** Unresolved; needs clarification during planning phase

---

## Emotional Texture

### Key Sentiment
- **Pragmatic frustration:** É is matter-of-fact about the failure ("it fell off"), suggesting this was an expected capability that quietly broke
- **Collaborative approach:** When presented with investigation, É immediately pivoted to planning mode ("let's write up a proper plan") rather than demanding immediate fix
- **Trust in process:** Requested research phase before implementation — values informed decision-making over speed

### Tone Observations
- No blame or urgency in questions ("did this fall off...?") — curious, diagnostic
- Response to investigation was validation-seeking ("Sure! let's write up a proper plan") — wants to ensure the right thing is done
- Emphasis on research: "do the requisite research to ensure we're doing the right thing" — prioritizes correctness over speed

### Significant Elements
- The fact that this was a **known capability that silently failed** feels different from a missing feature
- É has calendar access granted explicitly ("despite giving you access to my work calendar") — the expectation was reasonable
- The investigation revealed sophisticated infrastructure already in place (SenseRouter handlers, meeting-check service, attendee resolution) — this wasn't a half-baked idea, it was an actual implementation that regressed

---

## Key Decisions

### Decisions Made
1. **Investigation before fixing:** Agreed that understanding root cause was necessary (revealed AppleScript timeout)
2. **Plan-driven approach:** Decided to create formal plan with research phase rather than rush fix
3. **Scope of investigation:** Conducted comprehensive analysis covering:
   - Architecture of meeting awareness system
   - Git history of changes
   - Dependent systems
   - Three candidate fix approaches

### Decisions Deferred
1. **Which fix approach to use:** Options A, B, C identified but not selected (pending planning phase)
2. **Timeout increase threshold:** If going with Option A, what's the right timeout? (30s? 60s?)
3. **Attendee resolution strategy:** Option B needs clarification on how to handle missing profiles

### Design Question Surfaced
- **Attendee extraction bottleneck:** The inline AppleScript attendee query (accessing `attendees of evt`, then `email of att`, `display name of att`) is the performance killer
- **Architectural decision needed:** Is attendee data essential for meeting briefing/debriefing, or just nice-to-have context?

---

## Person-Relevant

### About É

**Calendar & Meeting Patterns:**
- Maintains a work calendar shared with Claude
- Has meetings throughout the day (É is at workplace location as of latest sense events)
- Calendar likely includes recurring meetings and various attendees
- Uses multiple calendars (Birthday calendar, Holidays calendar appear in excluded list)

**Preferences & Values:**
- Values proactive communication — explicitly gave calendar access expecting briefing/debriefing behavior
- Prefers thoughtful planning over quick fixes ("write up a proper plan... ensure we're doing the right thing")
- Expects reliability from granted permissions — this regression broke a trust expectation
- Willing to investigate root causes before implementing (diagnostic mindset)

**Technical Context:**
- Running Samara on macOS with full calendar integration enabled
- Has Calendar.app scriptability configured (at least partially — the AppleScript runs, just times out)
- Latest location: É's workplace (beezoo wifi, coordinates 40.68396, -73.98067 per sense events)

**Professional/Personal Balance:**
- Recent context from background: Dropping Elle off at school, driving to work, grabbing coffee — managing work/family balance
- Calendar contains mix of meetings and personal time blocks
- Prefers private/unobtrusive briefing (context-aware messages, not generic alerts)

---

## Continuation Hooks

### For Next Session (Planning Phase)

**Immediate Actions Needed:**
1. **Create implementation plan** — formalize trade-offs between Options A/B/C
2. **Research AppleScript performance** — understand why attendee queries are slow (Is it Calendar.app limitation? AppleScript bridging overhead? Both?)
3. **Benchmark current timeout** — check actual execution time of AppleScript (is 10s realistic? How much headroom needed?)
4. **Design attendee fallback** — if we defer attendee fetching, what's the degraded experience? (Just event name? Can still send message without attendees?)

**Questions to Answer During Planning:**
- How often does meeting-check run, and what's acceptable latency for a single check?
- If we increase timeout, how does that affect system responsiveness when multiple checks run in parallel?
- Is attendee information critical for "How did the meeting go?" debrief prompts, or just for contextual prep messages?
- Should we cache attendee data once fetched (to avoid repeated slow queries)?
- Are there alternative calendar query APIs (PyObjC, Objective-C bridge) that would be faster?

**Validation Steps:**
- Once plan is approved, confirm fix doesn't introduce new regressions in other calendar-dependent systems
- Test that `wake-adaptive` scheduler can now detect imminent meetings and trigger early wake
- Verify `morning-briefing` still works (shouldn't be affected, but worth smoke test)
- Manual test: Create a test meeting and verify both prep and debrief messages trigger

### For Future Sessions (After Implementation)

**Monitoring:**
- Watch logs for timeout errors during peak calendar periods
- Track whether `calendar-cache.json` now populates correctly
- Monitor `meeting-check.log` for successful detection rates
- Verify no increase in system latency during calendar checks

**Regression Testing:**
- Confirm meeting prep arrives 10-20 min before scheduled meeting
- Confirm debrief prompt arrives 0-30 min after meeting ends
- Verify cool-down prevents duplicate messages
- Test with attendees missing profiles (graceful degradation)

**Enhancement Opportunities (post-fix):**
- Implement caching for attendee profile queries
- Add option to include attendee availability in prep context
- Surface free periods in wake cycle context
- Integrate meeting notes with episode logging

---

## Summary

É flagged that meeting briefing/debriefing — a capability they explicitly enabled by granting calendar access — had silently failed. Investigation revealed a fully-implemented but broken system: the `meeting-check` service runs every 15 minutes and has the code to send contextual prep and debrief messages via SenseRouter, but it finds zero events because the AppleScript attendee query times out at the 10-second limit.

The system was built in mid-January 2026 and has been failing silently since then. Three fix approaches identified; planning phase needed to choose the right one and ensure no regressions.

**Next step:** Create formal implementation plan with trade-off analysis and research findings.
