#!/usr/bin/env python3
"""
GitHub Watcher - Satellite service that polls GitHub for notifications
and writes sense events for Samara to process.

Requires: gh CLI authenticated (gh auth login)
Designed to run via launchd every 15 minutes.
"""

import json
import os
import subprocess
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
SENSES_DIR = os.path.join(MIND_DIR, 'senses')
STATE_FILE = os.path.join(STATE_DIR, 'github-seen-ids.json')
LOG_FILE = os.path.join(MIND_DIR, 'logs', 'github-watcher.log')


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
        return {"seen_ids": [], "last_check": None}


def save_state(state: Dict):
    """Save persistent state."""
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)


def check_gh_auth() -> bool:
    """Check if gh CLI is authenticated."""
    try:
        result = subprocess.run(
            ["gh", "auth", "status"],
            capture_output=True,
            timeout=10
        )
        return result.returncode == 0
    except Exception as e:
        log(f"Error checking gh auth: {e}")
        return False


def write_sense_event(interactions: List[Dict], priority: str = "normal"):
    """Write a sense event for Samara to process."""
    os.makedirs(SENSES_DIR, exist_ok=True)

    event = {
        "sense": "github",
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
            "source_id": "github-watcher"
        }
    }

    event_file = os.path.join(SENSES_DIR, 'github.event.json')
    with open(event_file, 'w') as f:
        json.dump(event, f, indent=2)

    log(f"Wrote sense event with {len(interactions)} interaction(s)")


def build_prompt_hint(interactions: List[Dict]) -> str:
    """Build a prompt hint for Claude based on the interactions."""
    reasons = {}
    for i in interactions:
        r = i.get('reason', 'unknown')
        reasons[r] = reasons.get(r, 0) + 1

    parts = []
    for r, count in reasons.items():
        if count == 1:
            parts.append(f"1 {r}")
        else:
            parts.append(f"{count} {r}s")

    summary = ", ".join(parts)
    return f"You have GitHub notifications: {summary}. Review and respond using gh CLI (gh pr comment, gh issue comment) as appropriate."


def fetch_notifications(state: Dict) -> List[Dict]:
    """Fetch notifications from GitHub using gh CLI."""
    seen_ids = set(state.get("seen_ids", []))
    interactions = []

    # Fetch all notifications (including read ones, to catch ones marked read via web)
    try:
        result = subprocess.run(
            ["gh", "api", "notifications?all=true", "--paginate"],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            log(f"Error fetching notifications: {result.stderr}")
            return []

        notifications = json.loads(result.stdout) if result.stdout.strip() else []

    except subprocess.TimeoutExpired:
        log("Timeout fetching notifications")
        return []
    except Exception as e:
        log(f"Error fetching notifications: {e}")
        return []

    for n in notifications:
        notif_id = n.get("id")

        # Skip already seen
        if notif_id in seen_ids:
            continue

        reason = n.get("reason", "")
        subject = n.get("subject", {})
        subject_type = subject.get("type", "")
        subject_title = subject.get("title", "")
        subject_url = subject.get("url", "")  # API URL
        latest_comment_url = subject.get("latest_comment_url", "")
        repo_name = n.get("repository", {}).get("full_name", "")

        # Skip CI notifications and some noise
        if reason in ["ci_activity", "security_alert", "subscribed"]:
            seen_ids.add(notif_id)
            continue

        interaction = {
            "id": notif_id,
            "reason": reason,
            "subject_type": subject_type,
            "title": subject_title,
            "repo": repo_name,
            "api_url": subject_url,
            "comment_url": latest_comment_url
        }

        # Fetch more details for actionable notifications
        if reason in ["mention", "comment", "review_requested", "author", "state_change"]:
            # Get the actual comment content if available
            if latest_comment_url:
                try:
                    comment_result = subprocess.run(
                        ["gh", "api", latest_comment_url],
                        capture_output=True,
                        text=True,
                        timeout=15
                    )
                    if comment_result.returncode == 0:
                        comment_data = json.loads(comment_result.stdout)
                        interaction["comment_body"] = comment_data.get("body", "")[:500]
                        interaction["comment_author"] = comment_data.get("user", {}).get("login", "")
                        interaction["comment_html_url"] = comment_data.get("html_url", "")
                except:
                    pass

            # Get subject details (PR or Issue)
            if subject_url:
                try:
                    subject_result = subprocess.run(
                        ["gh", "api", subject_url],
                        capture_output=True,
                        text=True,
                        timeout=15
                    )
                    if subject_result.returncode == 0:
                        subject_data = json.loads(subject_result.stdout)
                        interaction["html_url"] = subject_data.get("html_url", "")
                        interaction["state"] = subject_data.get("state", "")
                        interaction["number"] = subject_data.get("number", "")
                except:
                    pass

        # Build human-readable text
        if reason == "mention":
            interaction["text"] = f"You were mentioned in {subject_type} '{subject_title}' on {repo_name}"
        elif reason == "comment":
            author = interaction.get("comment_author", "someone")
            interaction["text"] = f"@{author} commented on {subject_type} '{subject_title}' on {repo_name}"
        elif reason == "review_requested":
            interaction["text"] = f"Review requested on PR '{subject_title}' on {repo_name}"
        elif reason == "author":
            interaction["text"] = f"Activity on your {subject_type} '{subject_title}' on {repo_name}"
        elif reason == "state_change":
            interaction["text"] = f"State changed on {subject_type} '{subject_title}' on {repo_name}"
        elif reason == "assign":
            interaction["text"] = f"You were assigned to {subject_type} '{subject_title}' on {repo_name}"
        else:
            interaction["text"] = f"{reason}: {subject_type} '{subject_title}' on {repo_name}"

        interactions.append(interaction)
        seen_ids.add(notif_id)

    # Update state
    state["seen_ids"] = list(seen_ids)[-500:]  # Keep last 500 to prevent unbounded growth
    state["last_check"] = datetime.now().isoformat()

    return interactions


def mark_notifications_read():
    """Mark all notifications as read."""
    try:
        subprocess.run(
            ["gh", "api", "-X", "PUT", "notifications"],
            capture_output=True,
            timeout=10
        )
    except Exception as e:
        log(f"Error marking notifications read: {e}")


def main():
    log("Starting GitHub watcher...")

    # Check gh auth
    if not check_gh_auth():
        log("Error: gh not authenticated. Run: gh auth login")
        sys.exit(1)

    # Load state
    state = load_state()

    # Fetch interactions
    interactions = fetch_notifications(state)

    # Save state
    save_state(state)

    # Write sense event if we have interactions
    if interactions:
        log(f"Found {len(interactions)} new interaction(s)")

        # Determine priority based on interaction reasons
        has_mention = any(i['reason'] == 'mention' for i in interactions)
        has_review = any(i['reason'] == 'review_requested' for i in interactions)
        has_comment = any(i['reason'] in ['comment', 'author'] for i in interactions)

        if has_mention or has_review:
            priority = "immediate"
        elif has_comment:
            priority = "normal"
        else:
            priority = "background"

        write_sense_event(interactions, priority)

        # Mark as read after processing
        mark_notifications_read()
    else:
        log("No new interactions")

    log("GitHub watcher complete")


if __name__ == '__main__':
    main()
