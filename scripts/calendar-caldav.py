#!/usr/bin/env python3
"""
CalDAV calendar invitation handler for iCloud.

Uses the CalDAV scheduling protocol (RFC 6638) to properly accept/decline
invitations, which sends iTIP REPLY messages to organizers.

This complements calendar-invites.swift which uses EventKit for reading
(EventKit's participantStatus is read-only).
"""

import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

try:
    import caldav
    from caldav.elements import dav, cdav
except ImportError:
    print(json.dumps({
        "error": "caldav library not installed",
        "fix": "Run: ~/.claude-mind/venv/bin/pip install caldav"
    }))
    sys.exit(1)

# Configuration
# iCloud uses different server pools, try multiple endpoints
CALDAV_URLS = [
    "https://caldav.icloud.com/",
    "https://p01-caldav.icloud.com/",
    "https://p02-caldav.icloud.com/",
    "https://p03-caldav.icloud.com/",
]
CONFIG_PATH = Path.home() / ".claude-mind" / "config" / "caldav-credentials.json"


def load_credentials():
    """Load iCloud credentials from config file."""
    if not CONFIG_PATH.exists():
        return None, None

    try:
        with open(CONFIG_PATH) as f:
            config = json.load(f)
        return config.get("apple_id"), config.get("app_password")
    except (json.JSONDecodeError, IOError):
        return None, None


def get_client():
    """Connect to iCloud CalDAV with automatic endpoint discovery."""
    apple_id, app_password = load_credentials()

    if not apple_id or not app_password:
        raise ValueError(
            "Credentials not configured. "
            "Create ~/.claude-mind/config/caldav-credentials.json with "
            "apple_id and app_password fields."
        )

    # Try each endpoint until one works
    last_error = None
    for url in CALDAV_URLS:
        try:
            client = caldav.DAVClient(
                url=url,
                username=apple_id,
                password=app_password
            )
            # Test connection by getting principal
            principal = client.principal()
            return client
        except Exception as e:
            last_error = e
            continue

    # If all endpoints fail, raise the last error
    raise last_error or ValueError("Could not connect to any iCloud CalDAV endpoint")


def list_calendars():
    """List all available calendars."""
    client = get_client()
    principal = client.principal()
    calendars = principal.calendars()

    result = []
    for cal in calendars:
        result.append({
            "name": cal.name,
            "url": str(cal.url),
            "id": cal.id if hasattr(cal, 'id') else None
        })

    return {"calendars": result, "count": len(result)}


def list_inbox():
    """List pending invitations from scheduling inbox."""
    client = get_client()
    principal = client.principal()

    try:
        inbox = principal.schedule_inbox()
        items = inbox.get_items()
    except Exception as e:
        # Some servers don't support schedule_inbox
        return {
            "invitations": [],
            "count": 0,
            "note": f"Schedule inbox not available: {e}"
        }

    invitations = []
    for item in items:
        try:
            if hasattr(item, 'is_invite_request') and item.is_invite_request():
                ical = item.icalendar_component

                # Extract event details
                summary = str(ical.get("summary", "(No title)"))
                dtstart = ical.get("dtstart")
                start_str = str(dtstart.dt) if dtstart else "Unknown"
                organizer = str(ical.get("organizer", "Unknown"))
                uid = str(ical.get("uid", item.id))

                invitations.append({
                    "id": item.id,
                    "uid": uid,
                    "summary": summary,
                    "start": start_str,
                    "organizer": organizer.replace("mailto:", ""),
                })
        except Exception as e:
            # Skip malformed items
            continue

    return {"invitations": invitations, "count": len(invitations)}


def find_invitation(item_id: str):
    """Find an invitation by ID in the scheduling inbox."""
    client = get_client()
    principal = client.principal()

    try:
        inbox = principal.schedule_inbox()
        items = inbox.get_items()

        for item in items:
            if item.id == item_id or (hasattr(item, 'icalendar_component') and
                str(item.icalendar_component.get("uid")) == item_id):
                return item
    except Exception:
        pass

    return None


def respond_to_invitation(item_id: str, response: str):
    """
    Respond to an invitation using CalDAV scheduling.

    Args:
        item_id: The invitation ID or UID
        response: One of 'accept', 'decline', or 'maybe'
    """
    item = find_invitation(item_id)

    if not item:
        return {
            "status": "error",
            "message": f"Invitation not found: {item_id}"
        }

    try:
        if response == "accept":
            item.accept_invite()
        elif response == "decline":
            item.decline_invite()
        elif response in ("maybe", "tentative"):
            item.tentatively_accept_invite()
        else:
            return {
                "status": "error",
                "message": f"Invalid response: {response}. Use accept, decline, or maybe."
            }

        # Clean up inbox after responding
        try:
            item.delete()
        except Exception:
            pass  # Some servers auto-delete

        summary = "Unknown"
        try:
            summary = str(item.icalendar_component.get("summary", "Unknown"))
        except Exception:
            pass

        return {
            "status": "success",
            "response": response,
            "event": summary
        }

    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }


def accept_all():
    """Accept all pending invitations."""
    client = get_client()
    principal = client.principal()

    try:
        inbox = principal.schedule_inbox()
        items = inbox.get_items()
    except Exception as e:
        return {
            "status": "error",
            "message": f"Cannot access inbox: {e}"
        }

    accepted = []
    errors = []

    for item in items:
        try:
            if hasattr(item, 'is_invite_request') and item.is_invite_request():
                summary = str(item.icalendar_component.get("summary", "Unknown"))
                item.accept_invite()
                try:
                    item.delete()
                except Exception:
                    pass
                accepted.append(summary)
        except Exception as e:
            errors.append(str(e))

    return {
        "status": "success",
        "accepted": accepted,
        "count": len(accepted),
        "errors": errors if errors else None
    }


def sync_calendars():
    """Force a sync/refresh of calendars."""
    client = get_client()
    principal = client.principal()
    calendars = principal.calendars()

    synced = []
    for cal in calendars:
        try:
            # Fetching events forces a sync
            cal.date_search(
                start=datetime.now(),
                end=datetime.now() + timedelta(days=1),
                expand=False
            )
            synced.append(cal.name)
        except Exception:
            pass

    return {
        "status": "success",
        "synced": synced,
        "count": len(synced)
    }


def test_connection():
    """Test the CalDAV connection."""
    try:
        client = get_client()
        principal = client.principal()
        calendars = principal.calendars()

        return {
            "status": "success",
            "message": "Connected to iCloud CalDAV",
            "calendars_found": len(calendars),
            "principal_url": str(principal.url)
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }


def print_usage():
    """Print usage information."""
    usage = """
calendar-caldav - CalDAV calendar invitation handler

Usage:
    calendar-caldav test              Test connection to iCloud
    calendar-caldav calendars         List available calendars
    calendar-caldav inbox             List pending invitations
    calendar-caldav accept <id>       Accept an invitation
    calendar-caldav decline <id>      Decline an invitation
    calendar-caldav maybe <id>        Mark as tentative
    calendar-caldav accept-all        Accept all pending invitations
    calendar-caldav sync              Force calendar sync

Configuration:
    Credentials are stored in ~/.claude-mind/config/caldav-credentials.json:
    {
        "apple_id": "your@icloud.com",
        "app_password": "xxxx-xxxx-xxxx-xxxx"
    }

    Generate an app-specific password at:
    https://appleid.apple.com/ -> Security -> App-Specific Passwords

Note:
    This script uses the CalDAV scheduling protocol (RFC 6638) to properly
    respond to invitations. Unlike EventKit (which is read-only for status),
    CalDAV sends proper iTIP REPLY messages to notify organizers.
"""
    print(usage)


def main():
    args = sys.argv[1:]

    if not args or args[0] in ("--help", "-h", "help"):
        print_usage()
        return

    command = args[0]

    try:
        if command == "test":
            result = test_connection()
        elif command == "calendars":
            result = list_calendars()
        elif command == "inbox":
            result = list_inbox()
        elif command == "accept":
            if len(args) < 2:
                result = {"error": "Usage: calendar-caldav accept <invitation-id>"}
            else:
                result = respond_to_invitation(args[1], "accept")
        elif command == "decline":
            if len(args) < 2:
                result = {"error": "Usage: calendar-caldav decline <invitation-id>"}
            else:
                result = respond_to_invitation(args[1], "decline")
        elif command == "maybe":
            if len(args) < 2:
                result = {"error": "Usage: calendar-caldav maybe <invitation-id>"}
            else:
                result = respond_to_invitation(args[1], "maybe")
        elif command == "accept-all":
            result = accept_all()
        elif command == "sync":
            result = sync_calendars()
        else:
            result = {"error": f"Unknown command: {command}"}

        print(json.dumps(result, indent=2, default=str))

    except Exception as e:
        print(json.dumps({"error": str(e)}, indent=2))
        sys.exit(1)


if __name__ == "__main__":
    main()
