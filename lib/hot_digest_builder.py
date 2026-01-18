#!/usr/bin/env python3
"""
Hot Digest Builder

Compresses recent events (last 12 hours) into a context-friendly digest.
Uses qwen3:8b via Ollama for summarization of larger event batches.

Output is ~2-4k tokens, suitable for injection into session context.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

# Add parent dir to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.stream_writer import StreamWriter, Surface

# Surface categories for different formatting treatment
CONVERSATIONAL_SURFACES = {"imessage", "x", "bluesky", "email"}
ACTIVITY_SURFACES = {"cli", "wake", "dream"}
SENSE_SURFACES = {"webhook", "location", "calendar", "sense", "system"}

# Token budget allocation by category
TOKEN_WEIGHTS = {
    "conversational": 0.50,  # Conversations most important for continuity
    "activity": 0.35,        # CLI/wake sessions
    "sense": 0.15,           # System events (compact)
}


def estimate_tokens(text: str) -> int:
    """Rough token estimate (4 chars per token on average)."""
    return len(text) // 4


def format_time_ago(timestamp: str) -> str:
    """Format timestamp as human-readable time ago."""
    try:
        event_time = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        delta = now - event_time

        if delta.total_seconds() < 3600:
            return f"{int(delta.total_seconds() // 60)}m ago"
        elif delta.total_seconds() < 86400:
            return f"{int(delta.total_seconds() // 3600)}h ago"
        else:
            return f"{int(delta.total_seconds() // 86400)}d ago"
    except (ValueError, TypeError):
        return "recently"


def group_events_by_window(
    events: list[dict[str, Any]],
    window_minutes: int = 30,
) -> list[list[dict[str, Any]]]:
    """Group events into time windows."""
    if not events:
        return []

    # Sort by timestamp (newest first)
    sorted_events = sorted(
        events,
        key=lambda e: e.get("timestamp", ""),
        reverse=True,
    )

    groups: list[list[dict[str, Any]]] = []
    current_group: list[dict[str, Any]] = []
    current_window_start: Optional[datetime] = None

    for event in sorted_events:
        try:
            event_time = datetime.fromisoformat(
                event["timestamp"].replace("Z", "+00:00")
            )
        except (ValueError, KeyError):
            continue

        if current_window_start is None:
            current_window_start = event_time
            current_group = [event]
        elif (current_window_start - event_time).total_seconds() <= window_minutes * 60:
            current_group.append(event)
        else:
            if current_group:
                groups.append(current_group)
            current_group = [event]
            current_window_start = event_time

    if current_group:
        groups.append(current_group)

    return groups


# =============================================================================
# Surface-Specific Formatters
# =============================================================================


def parse_dialogue(content: str) -> list[tuple[str, str]]:
    """
    Parse **Speaker:** message format into (speaker, message) tuples.

    Handles formats like:
    - **É:** message
    - **Claude:** response
    - **Sense:wallet:** notification
    """
    if not content:
        return []

    # Match **Speaker:** followed by content until next **Speaker:** or end
    pattern = r"\*\*([^*]+):\*\*\s*(.*?)(?=\*\*[^*]+:\*\*|$)"
    matches = re.findall(pattern, content, re.DOTALL)

    return [(speaker.strip(), message.strip()) for speaker, message in matches]


def format_conversational_event(event: dict[str, Any], max_chars: int = 500) -> str:
    """
    Format iMessage/X/Bluesky events as dialogue.

    Output format:
        É: What were we working on earlier?
        Claude: We were implementing the hot digest system...
    """
    content = event.get("content", "")
    dialogue = parse_dialogue(content)

    if not dialogue:
        # Fallback to summary if no dialogue structure found
        return event.get("summary", "")[:max_chars]

    lines = []
    remaining = max_chars

    for speaker, message in dialogue:
        # Normalize Sense:xxx speakers
        if speaker.startswith("Sense:"):
            speaker = f"[{speaker}]"

        # Truncate message if needed, keeping room for speaker
        available = remaining - len(speaker) - 3  # ": " plus newline
        if available <= 0:
            break

        if len(message) > available:
            message = message[: available - 3] + "..."

        line = f"{speaker}: {message}"
        lines.append(line)
        remaining -= len(line) + 1

        if remaining < 50:
            break

    return "\n".join(lines)


def format_activity_event(event: dict[str, Any], max_chars: int = 300) -> str:
    """
    Format CLI/wake session events as activity summaries.

    Uses the full content field (bullet points) rather than truncated summary.
    """
    content = event.get("content", "") or event.get("summary", "")

    if not content:
        return ""

    # CLI events often have bullet points - preserve structure
    lines = content.split("\n")
    result = []
    total = 0

    for line in lines:
        line = line.strip()
        if not line:
            continue
        if total + len(line) > max_chars:
            break
        result.append(line)
        total += len(line) + 1

    return "\n".join(result) if result else content[:max_chars]


def format_sense_event(event: dict[str, Any]) -> str:
    """
    Format sense events as compact one-liners.

    Output: [Webhook] GitHub push notification
    """
    surface = event.get("surface", "sense")
    summary = event.get("summary", "")

    # Clean up "Sense:type:" prefix if present
    if summary.startswith("Sense:"):
        parts = summary.split(":", 2)
        if len(parts) >= 3:
            summary = parts[2].strip()

    return f"[{surface.capitalize()}] {summary[:100]}"


def summarize_with_ollama(events: list[dict[str, Any]], model: str = "qwen3:8b") -> str:
    """Use Ollama to summarize a batch of events."""
    # Build event descriptions
    event_texts = []
    for event in events:
        surface = event.get("surface", "unknown")
        summary = event.get("summary", "")
        content = event.get("content", "")
        timestamp = format_time_ago(event.get("timestamp", ""))

        text = f"[{surface}] ({timestamp}) {summary}"
        if content:
            # Use more content for better summarization (was 200, now 500)
            text += f"\n  Detail: {content[:500]}"
        event_texts.append(text)

    events_str = "\n".join(event_texts)

    prompt = f"""Summarize these events into a brief, informative digest entry.
Focus on: what happened, key topics, any open threads or decisions.
Keep it concise (2-4 sentences). Write in first person if about Claude's actions.

Events:
{events_str}

Output ONLY the summary, no preamble."""

    try:
        result = subprocess.run(
            ["ollama", "run", model, prompt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    # Fallback: just use summaries
    return "; ".join(e.get("summary", "") for e in events[:3])


# =============================================================================
# Section Builders (by category)
# =============================================================================


def build_conversational_section(
    events: list[dict[str, Any]],
    token_budget: int,
    use_ollama: bool,
    model: str,
) -> str:
    """
    Build the conversational surfaces section with dialogue formatting.

    Conversations are shown as actual dialogue:
        É: What were we working on?
        Claude: We were implementing the hot digest...
    """
    if not events:
        return ""

    # Sort by timestamp (newest first)
    events = sorted(events, key=lambda e: e.get("timestamp", ""), reverse=True)

    # Group by time windows
    windows = group_events_by_window(events, window_minutes=30)

    lines = ["### Conversations\n"]
    remaining = token_budget - estimate_tokens(lines[0])

    for window in windows:
        if remaining < 100:
            break

        first_event = window[0]
        time_str = format_time_ago(first_event.get("timestamp", ""))
        surface = first_event.get("surface", "unknown")
        surface_label = surface.upper() if surface == "x" else surface.capitalize()

        window_header = f"**{time_str} [{surface_label}]**\n"

        # Format each event in window as dialogue
        dialogues = []
        for event in window:
            formatted = format_conversational_event(event, max_chars=400)
            if formatted:
                dialogues.append(formatted)

        if not dialogues:
            continue

        # Join dialogues with blank lines between exchanges
        window_content = "\n\n".join(dialogues)
        entry = window_header + window_content + "\n"

        entry_tokens = estimate_tokens(entry)
        if entry_tokens <= remaining:
            lines.append(entry)
            remaining -= entry_tokens

    return "\n".join(lines) if len(lines) > 1 else ""


def build_activity_section(
    events: list[dict[str, Any]],
    token_budget: int,
    use_ollama: bool,
    model: str,
) -> str:
    """
    Build CLI/wake session activity section.

    Activities are shown as summaries:
        **25m ago**: Deep dive into message routing architecture...
    """
    if not events:
        return ""

    events = sorted(events, key=lambda e: e.get("timestamp", ""), reverse=True)
    windows = group_events_by_window(events, window_minutes=30)

    lines = ["### Sessions\n"]
    remaining = token_budget - estimate_tokens(lines[0])

    for window in windows:
        if remaining < 100:
            break

        first_event = window[0]
        time_str = format_time_ago(first_event.get("timestamp", ""))

        # For multiple events in window, use Ollama or summarize
        if len(window) > 3 and use_ollama:
            summary = summarize_with_ollama(window, model=model)
        else:
            # Use first event's content (more detailed than summary)
            summaries = []
            for event in window[:3]:
                formatted = format_activity_event(event, max_chars=200)
                if formatted:
                    # Take first line only for compactness
                    first_line = formatted.split("\n")[0]
                    summaries.append(first_line)
            summary = " | ".join(summaries)
            if len(window) > 3:
                summary += f" (+{len(window) - 3} more)"

        entry = f"**{time_str}**: {summary}\n"
        entry_tokens = estimate_tokens(entry)

        if entry_tokens <= remaining:
            lines.append(entry)
            remaining -= entry_tokens

    return "\n".join(lines) if len(lines) > 1 else ""


def build_sense_section(events: list[dict[str, Any]], token_budget: int) -> str:
    """
    Build compact sense events section.

    Sense events are compact one-liners:
        - 1h ago: [Webhook] GitHub push notification
    """
    if not events:
        return ""

    events = sorted(events, key=lambda e: e.get("timestamp", ""), reverse=True)

    lines = ["### System Events\n"]
    remaining = token_budget - estimate_tokens(lines[0])

    for event in events[:10]:  # Cap at 10 sense events
        if remaining < 50:
            break

        time_str = format_time_ago(event.get("timestamp", ""))
        formatted = format_sense_event(event)
        entry = f"- {time_str}: {formatted}\n"

        entry_tokens = estimate_tokens(entry)
        if entry_tokens <= remaining:
            lines.append(entry)
            remaining -= entry_tokens

    return "\n".join(lines) if len(lines) > 1 else ""


# =============================================================================
# Main Digest Builder
# =============================================================================


def build_digest(
    hours: int = 12,
    max_tokens: int = 3000,
    use_ollama: bool = True,
    ollama_model: str = "qwen3:8b",
) -> str:
    """
    Build a hot digest from recent events with priority-based token budgeting.

    Args:
        hours: Look back this many hours
        max_tokens: Target maximum tokens for output
        use_ollama: Use Ollama for summarization (if False, use heuristics only)
        ollama_model: Ollama model to use

    Returns:
        Markdown-formatted digest with sections:
        - Conversations (iMessage, X, Bluesky) - 50% budget
        - Sessions (CLI, wake) - 35% budget
        - System Events (webhook, location) - 15% budget
    """
    writer = StreamWriter()
    events = writer.query(hours=hours, include_distilled=False)

    if not events:
        return ""

    # Categorize events by surface type
    conversational_events: list[dict[str, Any]] = []
    activity_events: list[dict[str, Any]] = []
    sense_events: list[dict[str, Any]] = []

    for event in events:
        surface = event.get("surface", "unknown")
        if surface in CONVERSATIONAL_SURFACES:
            conversational_events.append(event)
        elif surface in ACTIVITY_SURFACES:
            activity_events.append(event)
        else:
            sense_events.append(event)

    # Calculate token budgets by priority
    header_budget = 100  # Reserve for header
    available = max_tokens - header_budget

    conv_budget = int(available * TOKEN_WEIGHTS["conversational"])
    activity_budget = int(available * TOKEN_WEIGHTS["activity"])
    sense_budget = int(available * TOKEN_WEIGHTS["sense"])

    # Build header
    digest_lines = [
        f"## Recent Activity (last {hours}h)\n",
        "*Background context from memory. This is NOT the current conversation.*\n",
    ]

    # Build sections in priority order
    sections = []

    # 1. Conversational section (highest priority - most important for continuity)
    if conversational_events:
        conv_section = build_conversational_section(
            conversational_events, conv_budget, use_ollama, ollama_model
        )
        if conv_section:
            sections.append(conv_section)

    # 2. Activity section (CLI/wake sessions)
    if activity_events:
        activity_section = build_activity_section(
            activity_events, activity_budget, use_ollama, ollama_model
        )
        if activity_section:
            sections.append(activity_section)

    # 3. Sense section (system events - lowest priority, compact)
    if sense_events:
        sense_section = build_sense_section(sense_events, sense_budget)
        if sense_section:
            sections.append(sense_section)

    # Assemble digest
    if sections:
        digest_lines.extend(sections)

    return "\n".join(digest_lines)


def main():
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Build hot digest from recent events")
    parser.add_argument("--hours", type=int, default=12, help="Hours to look back")
    parser.add_argument("--max-tokens", type=int, default=3000, help="Max output tokens")
    parser.add_argument("--no-ollama", action="store_true", help="Disable Ollama summarization")
    parser.add_argument("--model", default="qwen3:8b", help="Ollama model to use")
    parser.add_argument("--format", choices=["text", "json"], default="text")

    args = parser.parse_args()

    digest = build_digest(
        hours=args.hours,
        max_tokens=args.max_tokens,
        use_ollama=not args.no_ollama,
        ollama_model=args.model,
    )

    if args.format == "json":
        print(json.dumps({"digest": digest, "tokens_estimate": estimate_tokens(digest)}))
    else:
        if digest:
            print(digest)
        else:
            print("No recent events found.")


if __name__ == "__main__":
    main()
