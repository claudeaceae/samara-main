#!/usr/bin/env python3
"""
Bluesky Watcher - Satellite service that polls Bluesky for notifications/DMs
and writes sense events for Samara to process.

Designed to run via launchd every 15 minutes.
"""

import json
import os
import sys
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any

def resolve_mind_dir() -> str:
    override = os.environ.get("SAMARA_MIND_PATH") or os.environ.get("MIND_PATH")
    if override:
        return os.path.expanduser(override)
    home_dir = os.environ.get('HOME', os.path.expanduser('~'))
    return os.path.join(home_dir, '.claude-mind')


# Paths
MIND_DIR = resolve_mind_dir()
STATE_DIR = os.path.join(MIND_DIR, 'state')
SENSES_DIR = os.path.join(MIND_DIR, 'system', 'senses')
CREDENTIAL_BIN = os.path.join(MIND_DIR, 'system', 'bin', 'credential')
STATE_FILE = os.path.join(STATE_DIR, 'services', 'bluesky-state.json')
LOG_FILE = os.path.join(MIND_DIR, 'system', 'logs', 'bluesky-watcher.log')


def log(message: str):
    """Log to file and stdout."""
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    line = f"[{timestamp}] {message}"
    print(line)
    with open(LOG_FILE, 'a') as f:
        f.write(line + '\n')


def load_state() -> Dict:
    """Load persistent state."""
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except:
        return {"last_seen_at": None}


def save_state(state: Dict):
    """Save persistent state."""
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)


def load_credentials() -> Optional[Dict]:
    """Load Bluesky credentials from macOS Keychain."""
    try:
        import subprocess
        result = subprocess.run(
            [CREDENTIAL_BIN, 'get', 'bluesky'],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            log("Credentials not found in Keychain")
            return None
        return json.loads(result.stdout)
    except Exception as e:
        log(f"Error loading credentials: {e}")
        return None


def write_sense_event(interactions: List[Dict], priority: str = "normal"):
    """Write a sense event for Samara to process."""
    os.makedirs(SENSES_DIR, exist_ok=True)

    event = {
        "sense": "bluesky",
        "timestamp": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
        "priority": priority,
        "data": {
            "type": "notifications",
            "count": len(interactions),
            "interactions": interactions
        },
        "context": {
            "suggested_prompt": build_prompt_hint(interactions)
        },
        "auth": {
            "source_id": "bluesky-watcher"
        }
    }

    event_file = os.path.join(SENSES_DIR, 'bluesky.event.json')
    with open(event_file, 'w') as f:
        json.dump(event, f, indent=2)

    log(f"Wrote sense event with {len(interactions)} interaction(s)")


def build_prompt_hint(interactions: List[Dict]) -> str:
    """Build a prompt hint for Claude based on the interactions."""
    types = {}
    for i in interactions:
        t = i.get('type', 'unknown')
        types[t] = types.get(t, 0) + 1

    parts = []
    for t, count in types.items():
        if count == 1:
            parts.append(f"1 {t.lower()}")
        else:
            parts.append(f"{count} {t.lower()}s")

    summary = ", ".join(parts)
    return f"You have new Bluesky notifications: {summary}. Review and respond appropriately using bluesky-post for replies/posts or the Python AT Protocol client for DMs."


def fetch_notifications(client, state: Dict) -> List[Dict]:
    """Fetch new notifications from Bluesky."""
    interactions = []

    try:
        notifs = client.app.bsky.notification.list_notifications(params={"limit": 50})

        for n in notifs.notifications:
            # Skip if we've already seen this
            if state.get("last_seen_at") and n.indexed_at <= state["last_seen_at"]:
                continue

            reason = n.reason  # like, repost, follow, mention, reply, quote
            author = n.author.handle
            uri = getattr(n, 'uri', None)
            cid = getattr(n, 'cid', None)

            interaction = {
                "type": reason.upper(),
                "author": author,
                "author_did": n.author.did,
                "uri": uri,
                "cid": cid,
                "indexed_at": n.indexed_at
            }

            if reason == "follow":
                interaction["text"] = f"@{author} followed you"
            elif reason == "like":
                interaction["text"] = f"@{author} liked your post"
            elif reason == "reply":
                record_text = ""
                if hasattr(n, 'record') and hasattr(n.record, 'text'):
                    record_text = n.record.text[:300]
                interaction["text"] = f"@{author} replied: {record_text}"
                interaction["reply_text"] = record_text
                if hasattr(n, 'record') and hasattr(n.record, 'reply'):
                    interaction["parent_uri"] = n.record.reply.parent.uri
                    interaction["root_uri"] = n.record.reply.root.uri
            elif reason == "mention":
                record_text = ""
                if hasattr(n, 'record') and hasattr(n.record, 'text'):
                    record_text = n.record.text[:300]
                interaction["text"] = f"@{author} mentioned you: {record_text}"
                interaction["mention_text"] = record_text
            elif reason == "quote":
                interaction["text"] = f"@{author} quoted your post"
            elif reason == "repost":
                interaction["text"] = f"@{author} reposted your post"
            else:
                interaction["text"] = f"@{author}: {reason}"

            interactions.append(interaction)

        # Update state with newest notification timestamp
        if notifs.notifications:
            state["last_seen_at"] = notifs.notifications[0].indexed_at

    except Exception as e:
        log(f"Error fetching notifications: {e}")

    return interactions


def fetch_dms(client, state: Dict) -> List[Dict]:
    """Fetch unread DMs from Bluesky."""
    interactions = []

    try:
        convos = client.chat.bsky.convo.list_convos()
        for convo in convos.convos:
            if convo.unread_count > 0:
                msgs = client.chat.bsky.convo.get_messages(
                    convo_id=convo.id,
                    limit=convo.unread_count
                )
                for msg in msgs.messages:
                    # Skip our own messages
                    if hasattr(msg, 'sender') and msg.sender.did != client.me.did:
                        interaction = {
                            "type": "DM",
                            "author": msg.sender.handle,
                            "author_did": msg.sender.did,
                            "text": f"DM from @{msg.sender.handle}: {msg.text[:300]}",
                            "dm_text": msg.text,
                            "convo_id": convo.id,
                            "message_id": msg.id
                        }
                        interactions.append(interaction)
    except Exception as e:
        # DMs may fail if scope not granted
        log(f"Error fetching DMs (may be expected): {e}")

    return interactions


def main():
    log("Starting Bluesky watcher...")

    # Check for atproto library
    try:
        from atproto import Client
    except ImportError:
        log("Error: atproto library not installed. Run: pip install atproto")
        sys.exit(1)

    # Load credentials
    creds = load_credentials()
    if not creds:
        log("No credentials found, exiting")
        sys.exit(1)

    # Load state
    state = load_state()

    # Connect to Bluesky
    try:
        client = Client()
        client.login(creds['handle'], creds['app_password'])
        log(f"Logged in as {creds['handle']}")
    except Exception as e:
        log(f"Error connecting to Bluesky: {e}")
        sys.exit(1)

    # Fetch interactions
    interactions = []
    interactions.extend(fetch_notifications(client, state))
    interactions.extend(fetch_dms(client, state))

    # Save state
    save_state(state)

    # Write sense event if we have interactions
    if interactions:
        log(f"Found {len(interactions)} new interaction(s)")

        # Determine priority based on interaction types
        has_dm = any(i['type'] == 'DM' for i in interactions)
        has_mention = any(i['type'] in ['MENTION', 'REPLY'] for i in interactions)

        if has_dm:
            priority = "immediate"  # DMs are urgent
        elif has_mention:
            priority = "normal"
        else:
            priority = "background"  # Likes, reposts, follows

        write_sense_event(interactions, priority)
    else:
        log("No new interactions")

    log("Bluesky watcher complete")


if __name__ == '__main__':
    main()
