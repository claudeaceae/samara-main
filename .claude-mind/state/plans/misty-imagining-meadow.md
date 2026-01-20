# Plan: Reliable Programmatic Calendar Invitation Handling

## Problem Statement

The current `calendar-invites.swift` script uses AppleScript to accept/decline invitations, which is unreliable. AppleScript's `participation status` property doesn't consistently work with iCloud calendars because the server-side scheduling requires proper CalDAV protocol responses, not local property changes.

**Root cause:** EventKit's `participantStatus` is read-only by design. Apple intentionally doesn't expose invitation response APIs because responses must go through the CalDAV scheduling protocol to properly notify organizers.

## Research Summary

| Approach | Reading Events | Responding to Invitations |
|----------|---------------|---------------------------|
| EventKit (current) | ✅ Works great | ❌ Read-only, can't respond |
| AppleScript (current fallback) | ✅ Works | ⚠️ Unreliable, doesn't trigger server-side updates |
| UI Automation | ✅ Works | ⚠️ Brittle, slow, requires screenshots |
| **CalDAV + iTIP** | ✅ Works | ✅ **Proper protocol - notifies organizers** |

The CalDAV scheduling protocol (RFC 6638) with iTIP REPLY method is the correct way to respond to invitations. The Python `caldav` library exposes:
- `schedule_inbox().get_items()` - Get pending invitations
- `accept_invite()` / `decline_invite()` / `tentatively_accept_invite()` - Respond properly

## Solution Architecture

```
calendar-invites.swift (EventKit)        calendar-caldav.py (CalDAV)
        │                                        │
        ├── list (reading events)                ├── inbox (pending invitations)
        ├── show (event details)                 ├── accept (proper iTIP REPLY)
        ├── create (new events)                  ├── decline (proper iTIP REPLY)
        └── calendars (list cals)                ├── maybe (proper iTIP REPLY)
                                                 └── sync (force refresh)
```

**Hybrid approach:**
- Keep Swift/EventKit for reading (fast, native, well-integrated)
- Add Python/CalDAV for responding (proper protocol, server-side updates)
- Update the `/invites` skill to use both transparently

## Implementation Steps

### 1. Create `scripts/calendar-caldav.py`

New Python script for CalDAV operations:

```python
#!/usr/bin/env python3
"""CalDAV calendar invitation handler for iCloud."""

import caldav
import json
import os
import sys
from datetime import datetime, timedelta

# Authentication via app-specific password
CALDAV_URL = "https://caldav.icloud.com"
APPLE_ID = os.environ.get("APPLE_ID") or os.environ.get("ICLOUD_USER")
APPLE_PASSWORD = os.environ.get("APPLE_PASSWORD") or os.environ.get("ICLOUD_APP_PASSWORD")

def get_client():
    """Connect to iCloud CalDAV."""
    return caldav.DAVClient(
        url=CALDAV_URL,
        username=APPLE_ID,
        password=APPLE_PASSWORD
    )

def list_inbox():
    """List pending invitations from scheduling inbox."""
    client = get_client()
    principal = client.principal()
    inbox = principal.schedule_inbox()
    items = inbox.get_items()

    invitations = []
    for item in items:
        if item.is_invite_request():
            # Parse event details from ical data
            invitations.append({
                "id": item.id,
                "summary": item.icalendar_component.get("summary"),
                "start": str(item.icalendar_component.get("dtstart").dt),
                "organizer": str(item.icalendar_component.get("organizer")),
            })

    return {"invitations": invitations, "count": len(invitations)}

def respond(item_id: str, response: str):
    """Respond to invitation: accept, decline, or maybe."""
    client = get_client()
    principal = client.principal()
    inbox = principal.schedule_inbox()

    for item in inbox.get_items():
        if item.id == item_id:
            if response == "accept":
                item.accept_invite()
            elif response == "decline":
                item.decline_invite()
            elif response == "maybe":
                item.tentatively_accept_invite()
            item.delete()  # Clean up inbox
            return {"status": "success", "response": response}

    return {"status": "error", "message": "Invitation not found"}
```

### 2. Store credentials securely

Create `~/.claude-mind/config/caldav-credentials.json`:
```json
{
  "apple_id": "claudeaceae@icloud.com",
  "app_password": "<app-specific-password>"
}
```

Generate app-specific password at https://appleid.apple.com/ → Security → App-Specific Passwords.

### 3. Update `calendar-invites.swift`

Modify `respondToEvent()` to try CalDAV first:

```swift
func respondToEvent(eventId: String, response: String) {
    // Try CalDAV approach first (proper protocol)
    let caldavScript = "~/.claude-mind/bin/calendar-caldav"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", caldavScript, response, eventId]

    let pipe = Pipe()
    process.standardOutput = pipe

    do {
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("Successfully \(response)ed invitation via CalDAV")
            return
        }
    } catch {
        // Fall through to AppleScript fallback
    }

    // Existing AppleScript fallback...
}
```

### 4. Update `/invites` skill

Modify `.claude/skills/invites/SKILL.md` to document the CalDAV backend and troubleshooting.

### 5. Add setup script

Create `scripts/setup-caldav-calendar` to:
- Install Python caldav dependency
- Guide user through app-specific password creation
- Test connection and list calendars
- Store credentials securely

## Critical Files

| File | Action |
|------|--------|
| `scripts/calendar-caldav.py` | **Create** - New CalDAV handler |
| `scripts/calendar-invites.swift` | **Modify** - Add CalDAV fallback chain |
| `scripts/setup-caldav-calendar` | **Create** - Setup/credential helper |
| `.claude/skills/invites/SKILL.md` | **Modify** - Update documentation |
| `~/.claude-mind/config/caldav-credentials.json` | **Create** - Secure credential storage |

## Verification

1. **Test CalDAV connection:**
   ```bash
   python3 scripts/calendar-caldav.py calendars
   ```

2. **Test invitation listing:**
   ```bash
   python3 scripts/calendar-caldav.py inbox
   ```

3. **Test accept (have É send a test invitation):**
   ```bash
   python3 scripts/calendar-caldav.py accept <invitation-id>
   # Verify organizer receives acceptance notification
   ```

4. **Test integrated flow:**
   ```bash
   calendar-invites accept <event-id>
   # Should use CalDAV first, fall back to AppleScript if needed
   ```

## Rollback

If CalDAV approach fails, the existing AppleScript fallback remains intact. No functionality is removed - only enhanced.

## Dependencies

- Python 3.x (already available)
- `caldav` library: `pip install caldav`
- App-specific password for iCloud

## Sources

- [EventKit Documentation](https://developer.apple.com/documentation/eventkit)
- [CalDAV Scheduling RFC 6638](https://datatracker.ietf.org/doc/rfc6638/)
- [Python caldav library](https://github.com/python-caldav/caldav)
- [iCloud CalDAV Integration Guide](https://www.onecal.io/blog/how-to-integrate-icloud-calendar-api-into-your-app)
- [Apple Developer Forums - EventKit Limitations](https://developer.apple.com/forums/thread/675559)
