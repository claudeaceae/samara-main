# Development Patterns

Implementation patterns and workarounds for Samara development.

> **Back to:** [CLAUDE.md](../CLAUDE.md) | [Documentation Index](INDEX.md)

---

## AppleScript over MCP

Prefer direct AppleScript for Mac-native functionality:
- More reliable than MCP abstraction layers
- Calendar, Contacts, Notes, Mail, Reminders all work via AppleScript

---

## Message Handling

Messages are batched for 60 seconds before invoking Claude:
- Prevents fragmented conversations
- Uses `--resume` for session continuity

---

## Pictures Folder Workaround

Sending files via iMessage requires copying to `~/Pictures/.imessage-send/` first:
- macOS TCC quirk discovered 2025-12-21
- Scripts handle this automatically

---

## Bash Subagent for Multi-Step Commands

For multi-step command sequences that don't need file reading/editing, delegate to the Bash subagent:

```
Task tool with subagent_type=Bash
```

Good candidates:
- **Git workflows**: stage → commit → push → verify
- **Process management**: pkill → sleep → open → verify
- **Build operations**: archive → export → notarize → install
- **launchctl operations**: checking and loading multiple services

Not suitable when you need Read/Grep/Edit tools alongside Bash.
