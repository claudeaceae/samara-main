# Apple Notes Scratchpad Issue Report

## Summary

The scratchpad note watcher was failing to detect updates after Apple Notes renamed the note. The watcher relied on a static note name, but Apple Notes uses the first line of content as the title, so normal edits changed the name and broke detection. The fix was to track notes by stable id, persist the id in runtime state, and scope lookups to the correct account and folder.

## Background And Branch Point

This work branched off the smart-context retrieval rollout and tests. After those changes landed, the focus shifted to verifying that Apple Notes sensing still worked, since recent work had concentrated on Messages and Mail. The scratchpad note was a shared Apple Note in the iCloud "Notes" folder, and its title was expected to change as the first line changed.

## How We Discovered It

- You edited the shared scratchpad note from your own machine.
- Samara did not emit the usual "Scratchpad update detected" log.
- AppleScript inspection showed only one note in iCloud/Notes, but its name did not match the configured scratchpad name.
- That pointed to name-based lookup failure rather than sync or permissions.

## Symptoms

- No scratchpad updates triggered in `samara.log`.
- `NoteWatcher` warned that the configured note could not be found.
- Renaming the first line of the note made it invisible to the watcher.

## Root Cause

`NoteWatcher` located notes only by name, and Apple Notes titles are derived from the first line. That means normal edits effectively rename the note, so the watcher could no longer locate it. The lookup also defaulted to "first note whose name is X", which is fragile for shared notes or multiple notes with the same name.

## Investigation Details

- Used AppleScript to enumerate notes in the iCloud "Notes" folder.
- Verified there was a single shared note with a changing name.
- Confirmed that name-based lookup failed once the title diverged from the configured value.

## Fix Implemented

### Design Changes

- Track notes by stable id instead of mutable name.
- Persist note ids in runtime state so they survive restarts.
- Scope scratchpad to the expected account and folder.
- Fall back to a unique note in account+folder when name is stale.

### Code Changes

- `Samara/Samara/Senses/NoteWatcher.swift`:
  - Added `WatchedNote` (key, name, account, folder).
  - Added `NoteReadResult` and id-based note resolution.
  - Persisted ids to `~/.claude-mind/state/note-watcher.json`.
  - Returned `noteKey` and `noteId` on `NoteUpdate`.
- `Samara/Samara/main.swift`:
  - Configured scratchpad as a `WatchedNote` with account and folder.
  - Handled scratchpad updates by `noteKey` to avoid name drift.

## Validation

- Ran `scripts/test-samara --verbose` successfully.
- Confirmed `NoteWatcher` logs change detection after edits.
- Verified scratchpad updates fire even when the note title changes.

## Operational Notes

- Runtime mapping lives at `~/.claude-mind/state/note-watcher.json`.
- If the note is deleted and recreated, the stored id will be invalid until resolved via name or unique-note fallback.
- If more than one note exists in the account+folder, the unique-note fallback will not select a note.

## Session Log Location (This Conversation)

This is a Codex CLI session. The conversation is logged here:

- `~/.codex/history.jsonl` (append-only, always updated during the session)
- `~/.codex/sessions/YYYY/MM/DD/*.jsonl` (session transcript written on session end)

For scratchpad activity, Samara logs live at `~/.claude-mind/logs/samara.log` and are separate from the Codex transcript.
