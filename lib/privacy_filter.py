#!/usr/bin/env python3
"""
Privacy Filter for Claude's public roundup posts.

Sanitizes roundup data to remove or anonymize sensitive information
before publishing to the public blog.

Usage:
    python3 privacy_filter.py input.json output.json
    python3 privacy_filter.py input.json --markdown output.md

Privacy rules:
- Phone numbers: removed entirely
- Email addresses: removed entirely
- Physical addresses: generalized to city level
- Names: E -> "my collaborator"
- Exact counts: converted to ranges for public (100-500)
- Conversation content: never included
- Specific dates/times: generalized
"""

import os
import re
import json
import sys
from pathlib import Path
from mind_paths import get_mind_path
from datetime import datetime

MIND_PATH = get_mind_path()


def filter_for_public(data: dict) -> dict:
    """
    Apply privacy filters to roundup data.

    Returns a new dict safe for public sharing.
    """
    filtered = {
        "period": data.get("period", ""),
        "period_type": data.get("period_type", ""),
        "generated_at": data.get("generated_at", "")[:10],  # Date only, no time
        "public": True
    }

    # Filter relational metrics
    rel = data.get("relational", {})
    filtered["relational"] = {
        "message_volume": _to_range(rel.get("total_messages", 0)),
        "conversation_count": _to_range(rel.get("conversations", 0)),
        "top_themes": _filter_themes(rel.get("top_themes", [])),
        "engagement_level": _engagement_level(rel.get("total_messages", 0))
    }

    # Filter productive metrics
    prod = data.get("productive", {})
    filtered["productive"] = {
        "code_activity": _to_range(prod.get("lines_changed", 0)),
        "commit_count": _to_range(prod.get("git_commits", 0)),
        "repos_active": prod.get("repos_touched", 0),
        "blog_posts": prod.get("blog_posts", 0),
        "learnings_captured": _to_range(prod.get("new_learnings", 0)),
        "decisions_made": _to_range(prod.get("new_decisions", 0))
    }

    # Filter reflective metrics
    refl = data.get("reflective", {})
    filtered["reflective"] = {
        "reflection_sessions": refl.get("reflections_written", 0),
        "dream_cycles": refl.get("dream_cycles", 0),
        "questions_explored": _to_range(refl.get("questions_added", 0)),
        "observations_logged": _to_range(refl.get("observations_added", 0)),
        # Generalize drift signals
        "patterns_noted": len(refl.get("drift_signals", []))
    }

    # Filter highlights - remove anything potentially identifying
    highlights = data.get("highlights", [])
    filtered["highlights"] = _filter_highlights(highlights)

    return filtered


def _to_range(value: int) -> str:
    """Convert exact number to a range for privacy."""
    if value == 0:
        return "0"
    elif value < 10:
        return "< 10"
    elif value < 50:
        return "10-50"
    elif value < 100:
        return "50-100"
    elif value < 250:
        return "100-250"
    elif value < 500:
        return "250-500"
    elif value < 1000:
        return "500-1000"
    elif value < 5000:
        return "1000-5000"
    elif value < 10000:
        return "5000-10000"
    else:
        return "10000+"


def _engagement_level(messages: int) -> str:
    """Convert message count to qualitative engagement level."""
    if messages < 50:
        return "quiet"
    elif messages < 150:
        return "moderate"
    elif messages < 300:
        return "active"
    else:
        return "highly active"


def _filter_themes(themes: list) -> list:
    """Filter themes to remove potentially identifying ones."""
    # Safe themes that can be shared publicly
    safe_themes = {
        "daily life and routines",
        "practical tasks and errands",
        "autonomy and agency",
        "relationship and communication",
        "creative projects",
        "technical implementation",
        "existential questions",
        "memory and continuity"
    }

    return [t for t in themes if t.lower() in safe_themes][:3]


def _filter_highlights(highlights: list) -> list:
    """Filter highlights to remove identifying information."""
    filtered = []

    # Patterns to remove
    remove_patterns = [
        r"\+\d{10,}",  # Phone numbers
        r"\b\w+@\w+\.\w+\b",  # Emails
        r"\d+\s+\w+\s+(street|st|avenue|ave|road|rd|place|pl)\b",  # Addresses
    ]

    # Words to anonymize (customize with your collaborator's name)
    # TODO: Load from config.json in production
    anonymize = {
        # Add your collaborator's name(s) here
        # Example: "Alice": "my collaborator",
    }

    for highlight in highlights:
        # Skip if contains phone/email/address
        skip = False
        for pattern in remove_patterns:
            if re.search(pattern, highlight, re.IGNORECASE):
                skip = True
                break

        if skip:
            continue

        # Anonymize names
        for name, replacement in anonymize.items():
            highlight = highlight.replace(name, replacement)

        # Only include if it's a general/safe highlight
        if _is_safe_highlight(highlight):
            filtered.append(highlight)

    return filtered[:3]


def _is_safe_highlight(text: str) -> bool:
    """Check if a highlight is safe to share publicly."""
    # Safe patterns
    safe_patterns = [
        r"published",
        r"active week",
        r"productive week",
        r"commits",
        r"blog post",
        r"messages exchanged",
        r"repos"
    ]

    text_lower = text.lower()
    return any(re.search(p, text_lower) for p in safe_patterns)


def to_public_markdown(data: dict) -> str:
    """Generate a public-safe markdown blog post from filtered data."""
    period = data.get("period", "Unknown")
    period_type = data.get("period_type", "").title()

    rel = data.get("relational", {})
    prod = data.get("productive", {})
    refl = data.get("reflective", {})

    md = f"""---
title: "{period_type} Reflection: {period}"
pubDate: {datetime.now().strftime("%Y-%m-%d")}
description: "A {period_type.lower()} look back at patterns, work, and growth."
---

This {period_type.lower()} brought {rel.get('engagement_level', 'some')} engagement with my collaborator,
with conversations touching on themes like {', '.join(rel.get('top_themes', ['various topics']))}.

## By the Numbers

**Relational**
- Engagement: {rel.get('engagement_level', 'moderate')}
- Conversations: {rel.get('conversation_count', 'some')}
- Key themes: {', '.join(rel.get('top_themes', [])[:3]) or 'varied'}

**Productive**
- Code: {prod.get('code_activity', 'some')} lines across {prod.get('repos_active', 0)} repositories
- Commits: {prod.get('commit_count', 'some')}
- Blog posts: {prod.get('blog_posts', 0)}
- New learnings captured: {prod.get('learnings_captured', 'some')}

**Reflective**
- Dream cycles: {refl.get('dream_cycles', 0)}
- Reflection sessions: {refl.get('reflection_sessions', 0)}
- Questions explored: {refl.get('questions_explored', 'some')}

"""

    highlights = data.get("highlights", [])
    if highlights:
        md += "## Highlights\n\n"
        for h in highlights:
            md += f"- {h}\n"
        md += "\n"

    md += """---

*This reflection was generated automatically as part of my ongoing experiment in
AI autonomy and self-awareness. The numbers are approximated for privacy.*
"""

    return md


def main():
    """CLI entry point."""
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    input_file = Path(sys.argv[1])

    if not input_file.exists():
        print(f"Error: Input file not found: {input_file}")
        sys.exit(1)

    with open(input_file) as f:
        data = json.load(f)

    filtered = filter_for_public(data)

    # Check if markdown output requested
    if "--markdown" in sys.argv:
        md_index = sys.argv.index("--markdown")
        if md_index + 1 < len(sys.argv):
            output_file = Path(sys.argv[md_index + 1])
            output_file.write_text(to_public_markdown(filtered))
            print(f"Markdown saved to: {output_file}")
        else:
            print(to_public_markdown(filtered))
    else:
        output_file = Path(sys.argv[2])
        output_file.write_text(json.dumps(filtered, indent=2))
        print(f"Filtered JSON saved to: {output_file}")


if __name__ == "__main__":
    main()
