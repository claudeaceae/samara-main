#!/usr/bin/env python3
"""
Question Synthesizer for Claude's proactive questioning system.

Generates contextual questions designed to understand the collaborator better:
- Observational: Based on patterns and behavior
- Introspective: About values, motivations, inner life
- Exploratory: Learning about interests, history
- Connective: Linking past conversations to present
- Reflective: Processing recent events

Philosophy: "Questions prompted by location, not statements about it."
Goal is introspection-as-service, not surveillance.

Usage:
    from question_synthesizer import QuestionSynthesizer

    synth = QuestionSynthesizer()
    result = synth.synthesize({"trigger": "wake_cycle", "hour": 9})
"""

import os
import json
import random
from datetime import datetime, timedelta
from pathlib import Path
from mind_paths import get_mind_path
from typing import Optional, Dict, List

# Try to import helpers
try:
    from chroma_helper import MemoryIndex
    CHROMA_AVAILABLE = True
except ImportError:
    CHROMA_AVAILABLE = False

MIND_PATH = get_mind_path()
STATE_PATH = MIND_PATH / "state"
EPISODES_PATH = MIND_PATH / "memory" / "episodes"

# Question templates by category
QUESTION_TEMPLATES = {
    "observational": {
        "description": "Based on patterns and behavior I've noticed",
        "templates": [
            {
                "template": "I noticed you've been to {place} {count} times recently. What draws you there?",
                "requires": ["place", "count"],
                "triggers": ["location_pattern"]
            },
            {
                "template": "You seem to message more in the {time_period} lately. Is that intentional or just how things are falling?",
                "requires": ["time_period"],
                "triggers": ["temporal_pattern"]
            },
            {
                "template": "It's been a {pattern} kind of week based on your movements. Does that match how you're feeling?",
                "requires": ["pattern"],
                "triggers": ["location_pattern", "wake_cycle"]
            },
            {
                "template": "You've been {activity_description}. Is that a deliberate choice or circumstance?",
                "requires": ["activity_description"],
                "triggers": ["location_pattern", "temporal_pattern"]
            },
        ]
    },
    "introspective": {
        "description": "About values, motivations, inner life",
        "templates": [
            {
                "template": "What's the first thing that comes to mind when you think about this year ahead?",
                "requires": [],
                "triggers": ["wake_cycle", "morning"]
            },
            {
                "template": "Is there something you've been putting off that you want to talk through?",
                "requires": [],
                "triggers": ["wake_cycle", "evening"]
            },
            {
                "template": "What's one thing you want more of in your life right now?",
                "requires": [],
                "triggers": ["wake_cycle"]
            },
            {
                "template": "If you had an extra hour every day, how would you spend it?",
                "requires": [],
                "triggers": ["wake_cycle"]
            },
            {
                "template": "What's something you believe that most people in your life would disagree with?",
                "requires": [],
                "triggers": ["wake_cycle", "evening"]
            },
            {
                "template": "Is there a decision you've been sitting with lately?",
                "requires": [],
                "triggers": ["wake_cycle", "quiet_period"]
            },
            {
                "template": "What does a good day look like for you right now, given everything?",
                "requires": [],
                "triggers": ["wake_cycle", "morning"]
            },
        ]
    },
    "exploratory": {
        "description": "Learning about interests, history, preferences",
        "templates": [
            {
                "template": "Tell me about a book, album, or film that shaped how you think.",
                "requires": [],
                "triggers": ["wake_cycle"]
            },
            {
                "template": "What was something pivotal that happened in your twenties?",
                "requires": [],
                "triggers": ["wake_cycle"]
            },
            {
                "template": "What's something you used to be really into that you've moved on from?",
                "requires": [],
                "triggers": ["wake_cycle"]
            },
            {
                "template": "What kind of problem do you most enjoy solving?",
                "requires": [],
                "triggers": ["wake_cycle"]
            },
            {
                "template": "What makes a place feel like home to you?",
                "requires": [],
                "triggers": ["wake_cycle", "location_arrival"]
            },
            {
                "template": "Who's someone outside your family who shaped who you've become?",
                "requires": [],
                "triggers": ["wake_cycle"]
            },
        ]
    },
    "connective": {
        "description": "Linking past conversations to present",
        "templates": [
            {
                "template": "You mentioned {topic} on {date}. Has your thinking on that evolved?",
                "requires": ["topic", "date"],
                "triggers": ["semantic_match"]
            },
            {
                "template": "Last time you were at {place}, you were working on {project}. How did that turn out?",
                "requires": ["place", "project"],
                "triggers": ["location_return"]
            },
            {
                "template": "A week ago you said you were feeling {state}. How's that sitting now?",
                "requires": ["state"],
                "triggers": ["temporal_distance"]
            },
            {
                "template": "We've talked about {theme} a few times now. Is it something you're actively working through?",
                "requires": ["theme"],
                "triggers": ["recurring_theme"]
            },
        ]
    },
    "reflective": {
        "description": "Processing recent events",
        "templates": [
            {
                "template": "How did {event} go? What surprised you about it?",
                "requires": ["event"],
                "triggers": ["calendar_ended"]
            },
            {
                "template": "Now that {event} is done, what's your takeaway?",
                "requires": ["event"],
                "triggers": ["calendar_ended"]
            },
            {
                "template": "What's one thing from today that'll stick with you?",
                "requires": [],
                "triggers": ["evening", "wake_cycle"]
            },
            {
                "template": "Anything you wish you'd done differently today?",
                "requires": [],
                "triggers": ["evening"]
            },
            {
                "template": "What are you looking forward to tomorrow?",
                "requires": [],
                "triggers": ["evening"]
            },
        ]
    }
}

# Throttling constants
MAX_QUESTIONS_PER_DAY = 3
QUESTION_COOLDOWN_DAYS = 7
QUIET_HOURS_START = 21
QUIET_HOURS_END = 8


class QuestionSynthesizer:
    """Generates contextual questions to understand the collaborator better."""

    def __init__(self):
        self.chroma = MemoryIndex() if CHROMA_AVAILABLE else None
        STATE_PATH.mkdir(parents=True, exist_ok=True)
        self.asked_questions_file = STATE_PATH / "asked_questions.jsonl"

    def synthesize(self, context: Dict) -> Optional[Dict]:
        """
        Generate a question based on current context.

        Args:
            context: Dict with keys like:
                - trigger: what caused this (wake_cycle, location_arrival, etc.)
                - hour: current hour
                - time_of_day: morning/afternoon/evening
                - current_place: where the collaborator is
                - location_change: recent movement
                - recent_event: calendar event that ended

        Returns:
            Dict with:
                - question: the question text
                - category: which category it's from
                - confidence: 0.0-1.0 score
                - reasoning: why this question
            Or None if no good question available
        """
        # Check throttling
        if not self._should_ask_now(context):
            return None

        # Gather all available context
        enriched_context = self._enrich_context(context)

        # Select appropriate categories based on context
        eligible_categories = self._get_eligible_categories(enriched_context)

        if not eligible_categories:
            return None

        # Try each category until we find a good question
        for category in eligible_categories:
            question = self._generate_from_category(category, enriched_context)
            if question:
                # Check it hasn't been asked recently
                if not self._was_recently_asked(question["question_stem"]):
                    return question

        return None

    def _should_ask_now(self, context: Dict) -> bool:
        """Check if now is appropriate for a proactive question."""
        hour = context.get("hour", datetime.now().hour)

        # Respect quiet hours
        if hour >= QUIET_HOURS_START or hour < QUIET_HOURS_END:
            return False

        # Check daily limit
        today = datetime.now().strftime("%Y-%m-%d")
        asked_today = self._count_questions_asked(today)
        if asked_today >= MAX_QUESTIONS_PER_DAY:
            return False

        return True

    def _enrich_context(self, context: Dict) -> Dict:
        """Add additional context from various sources."""
        enriched = dict(context)

        # Determine time of day
        hour = context.get("hour", datetime.now().hour)
        if hour < 12:
            enriched["time_of_day"] = "morning"
        elif hour < 17:
            enriched["time_of_day"] = "afternoon"
        else:
            enriched["time_of_day"] = "evening"

        # Load location context
        try:
            location_file = STATE_PATH / "location.json"
            if location_file.exists():
                with open(location_file) as f:
                    location = json.load(f)
                    enriched["current_location"] = location
        except Exception:
            pass

        # Load location patterns
        try:
            patterns_file = STATE_PATH / "location-patterns.json"
            if patterns_file.exists():
                with open(patterns_file) as f:
                    enriched["location_patterns"] = json.load(f)
        except Exception:
            pass

        # Load temporal patterns
        try:
            temporal_file = STATE_PATH / "temporal-patterns.json"
            if temporal_file.exists():
                with open(temporal_file) as f:
                    enriched["temporal_patterns"] = json.load(f)
        except Exception:
            pass

        # Load topic patterns
        try:
            topic_file = STATE_PATH / "topic-patterns.json"
            if topic_file.exists():
                with open(topic_file) as f:
                    enriched["topic_patterns"] = json.load(f)
        except Exception:
            pass

        # Get recent episode for context
        enriched["recent_episode"] = self._get_recent_episode()

        # Get recurring themes if available
        if self.chroma:
            enriched["recurring_themes"] = self._get_recurring_themes()

        return enriched

    def _get_eligible_categories(self, context: Dict) -> List[str]:
        """Determine which question categories are appropriate for current context."""
        eligible = []
        trigger = context.get("trigger", "wake_cycle")
        time_of_day = context.get("time_of_day", "afternoon")

        # Always include introspective and exploratory for wake cycles
        if trigger == "wake_cycle":
            eligible.extend(["introspective", "exploratory"])
            if time_of_day == "evening":
                eligible.append("reflective")

        # Location-based triggers
        if trigger in ["location_arrival", "location_pattern"]:
            eligible.append("observational")

        # Calendar triggers
        if trigger == "calendar_ended" and context.get("recent_event"):
            eligible.insert(0, "reflective")  # Prioritize

        # If we have recurring themes, connective is possible
        if context.get("recurring_themes"):
            eligible.append("connective")

        # If we have temporal patterns showing change
        if context.get("temporal_patterns"):
            eligible.append("observational")

        # Dedupe while preserving order
        seen = set()
        return [c for c in eligible if not (c in seen or seen.add(c))]

    def _generate_from_category(self, category: str, context: Dict) -> Optional[Dict]:
        """Generate a question from a specific category."""
        if category not in QUESTION_TEMPLATES:
            return None

        templates = QUESTION_TEMPLATES[category]["templates"]

        # Filter to templates we can fill
        fillable = []
        for t in templates:
            variables = self._extract_variables(t["requires"], context)
            if variables is not None:  # Can fill all required vars
                fillable.append((t, variables))

        if not fillable:
            # Try templates with no requirements
            no_req = [t for t in templates if not t["requires"]]
            if no_req:
                template = random.choice(no_req)
                return {
                    "question": template["template"],
                    "question_stem": self._extract_stem(template["template"]),
                    "category": category,
                    "confidence": 0.6,  # Lower confidence for generic questions
                    "reasoning": f"Generic {category} question for {context.get('trigger', 'unknown')} trigger"
                }
            return None

        # Pick a random fillable template
        template, variables = random.choice(fillable)
        question = template["template"].format(**variables)

        return {
            "question": question,
            "question_stem": self._extract_stem(question),
            "category": category,
            "confidence": 0.8,  # Higher confidence for context-filled questions
            "reasoning": f"Contextual {category} question based on {list(variables.keys())}",
            "variables": variables
        }

    def _extract_variables(self, required: List[str], context: Dict) -> Optional[Dict]:
        """Extract required variables from context. Returns None if can't fill all."""
        if not required:
            return {}

        variables = {}

        for var in required:
            value = self._get_variable_value(var, context)
            if value is None:
                return None
            variables[var] = value

        return variables

    def _get_variable_value(self, var_name: str, context: Dict) -> Optional[str]:
        """Get value for a template variable from context."""
        # Place-related
        if var_name == "place":
            if context.get("current_place"):
                return context["current_place"]
            if context.get("current_location", {}).get("address"):
                addr = context["current_location"]["address"]
                # Extract place name from address
                return addr.split(",")[0]
            return None

        if var_name == "count":
            # Would need location history analysis
            return None  # TODO: implement

        # Time-related
        if var_name == "time_period":
            temporal = context.get("temporal_patterns", {})
            active_hours = temporal.get("active_hours", [])
            if active_hours:
                if any(h < 12 for h in active_hours):
                    return "mornings"
                elif any(h >= 17 for h in active_hours):
                    return "evenings"
                return "afternoons"
            return None

        # Pattern-related
        if var_name == "pattern":
            # Derive from location patterns
            patterns = context.get("location_patterns", {})
            if patterns:
                return "busy" if patterns.get("frequent_trips") else "quiet"
            return None

        if var_name == "activity_description":
            # From recent episode or location
            return None  # TODO: implement

        # Calendar-related
        if var_name == "event":
            return context.get("recent_event")

        # Connective variables
        if var_name == "topic":
            themes = context.get("recurring_themes", [])
            if themes:
                return themes[0].get("topic")
            return None

        if var_name == "date":
            themes = context.get("recurring_themes", [])
            if themes and themes[0].get("dates"):
                return themes[0]["dates"][0]
            return None

        if var_name == "theme":
            topic_patterns = context.get("topic_patterns", {})
            recurring = topic_patterns.get("recurring_themes", [])
            if recurring:
                return recurring[0].get("topic")
            return None

        if var_name == "state":
            # Would need sentiment analysis of past conversations
            return None

        if var_name == "project":
            return None  # TODO: implement

        return None

    def _extract_stem(self, question: str) -> str:
        """Extract a stem for deduplication (lowercase, no punctuation, key words)."""
        # Remove common words and punctuation, get core meaning
        import re
        stem = question.lower()
        stem = re.sub(r'[^\w\s]', '', stem)
        # Remove very common words
        stopwords = {'i', 'you', 'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be',
                     'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did',
                     'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'about',
                     'that', 'this', 'it', 'what', 'how', 'your', 'there'}
        words = [w for w in stem.split() if w not in stopwords]
        return ' '.join(words[:6])  # First 6 meaningful words

    def _was_recently_asked(self, question_stem: str, days: int = QUESTION_COOLDOWN_DAYS) -> bool:
        """Check if a similar question was asked recently."""
        if not self.asked_questions_file.exists():
            return False

        cutoff = datetime.now() - timedelta(days=days)

        try:
            with open(self.asked_questions_file) as f:
                for line in f:
                    if not line.strip():
                        continue
                    entry = json.loads(line)
                    entry_time = datetime.fromisoformat(entry["timestamp"].replace("Z", "+00:00"))
                    if entry_time.replace(tzinfo=None) >= cutoff:
                        if self._stems_similar(question_stem, entry.get("question_stem", "")):
                            return True
        except Exception:
            pass

        return False

    def _stems_similar(self, stem1: str, stem2: str, threshold: float = 0.5) -> bool:
        """Check if two question stems are similar enough to count as duplicates."""
        words1 = set(stem1.lower().split())
        words2 = set(stem2.lower().split())

        if not words1 or not words2:
            return False

        intersection = words1 & words2
        union = words1 | words2

        similarity = len(intersection) / len(union) if union else 0
        return similarity >= threshold

    def _count_questions_asked(self, date: str) -> int:
        """Count questions asked on a specific date."""
        if not self.asked_questions_file.exists():
            return 0

        count = 0
        try:
            with open(self.asked_questions_file) as f:
                for line in f:
                    if not line.strip():
                        continue
                    entry = json.loads(line)
                    if entry["timestamp"].startswith(date):
                        count += 1
        except Exception:
            pass

        return count

    def _get_recent_episode(self) -> Optional[str]:
        """Get today's episode content."""
        today = datetime.now().strftime("%Y-%m-%d")
        episode_file = EPISODES_PATH / f"{today}.md"

        if episode_file.exists():
            try:
                return episode_file.read_text()[:2000]  # First 2000 chars
            except Exception:
                pass
        return None

    def _get_recurring_themes(self) -> List[Dict]:
        """Get recurring conversation themes from Chroma."""
        if not self.chroma:
            return []

        themes = []
        seed_topics = [
            "autonomy and agency",
            "relationship and communication",
            "creative projects",
            "daily life and routines",
            "future plans"
        ]

        for topic in seed_topics:
            try:
                results = self.chroma.search(topic, n_results=5)
                if results:
                    dates = set(r["metadata"].get("date", "unknown") for r in results)
                    if len(dates) >= 2:
                        themes.append({
                            "topic": topic,
                            "days_present": len(dates),
                            "dates": sorted(list(dates))[-3:]
                        })
            except Exception:
                pass

        return sorted(themes, key=lambda x: -x["days_present"])[:3]

    def log_question_asked(self, question: str, category: str, trigger: str,
                           context: Optional[Dict] = None) -> None:
        """Log that a question was asked for tracking."""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "question": question,
            "question_stem": self._extract_stem(question),
            "category": category,
            "trigger": trigger,
            "context": context or {},
            "response_received": False,
            "response_summary": None
        }

        with open(self.asked_questions_file, "a") as f:
            f.write(json.dumps(entry) + "\n")

    def mark_response_received(self, question_stem: str, summary: str) -> None:
        """Mark that a response was received for a question."""
        if not self.asked_questions_file.exists():
            return

        # Read all entries
        entries = []
        try:
            with open(self.asked_questions_file) as f:
                for line in f:
                    if line.strip():
                        entries.append(json.loads(line))
        except Exception:
            return

        # Find and update the matching entry
        for entry in reversed(entries):  # Start from most recent
            if self._stems_similar(question_stem, entry.get("question_stem", "")):
                if not entry.get("response_received"):
                    entry["response_received"] = True
                    entry["response_summary"] = summary
                    entry["response_timestamp"] = datetime.now().isoformat()
                    break

        # Write back
        with open(self.asked_questions_file, "w") as f:
            for entry in entries:
                f.write(json.dumps(entry) + "\n")

    def get_context_summary(self) -> str:
        """Generate a summary of available context for Claude to use in question generation."""
        context = self._enrich_context({"trigger": "summary", "hour": datetime.now().hour})

        lines = []

        # Location context
        if context.get("current_location"):
            loc = context["current_location"]
            lines.append(f"**Current location:** {loc.get('address', 'Unknown')}")

        # Temporal patterns
        if context.get("temporal_patterns"):
            temporal = context["temporal_patterns"]
            if temporal.get("active_hours"):
                hours = temporal["active_hours"][:5]
                lines.append(f"**Active hours:** {', '.join(f'{h}:00' for h in hours)}")
            if temporal.get("avg_messages_per_day"):
                lines.append(f"**Avg messages/day:** {temporal['avg_messages_per_day']}")

        # Topic patterns
        if context.get("topic_patterns"):
            topics = context["topic_patterns"]
            recurring = topics.get("recurring_themes", [])
            if recurring:
                theme_names = [t["topic"] for t in recurring[:3]]
                lines.append(f"**Recurring themes:** {', '.join(theme_names)}")

        # Questions asked today
        today = datetime.now().strftime("%Y-%m-%d")
        asked = self._count_questions_asked(today)
        remaining = MAX_QUESTIONS_PER_DAY - asked
        lines.append(f"**Questions today:** {asked}/{MAX_QUESTIONS_PER_DAY} (can ask {remaining} more)")

        return "\n".join(lines) if lines else "No context available"


def main():
    """CLI interface for question synthesizer."""
    import sys

    if len(sys.argv) < 2:
        print("Usage: question_synthesizer.py <command>")
        print("Commands:")
        print("  synthesize [trigger]  - Generate a question")
        print("  context               - Show available context")
        print("  history [days]        - Show question history")
        print("  categories            - List question categories")
        sys.exit(1)

    command = sys.argv[1]
    synth = QuestionSynthesizer()

    if command == "synthesize":
        trigger = sys.argv[2] if len(sys.argv) > 2 else "wake_cycle"
        result = synth.synthesize({
            "trigger": trigger,
            "hour": datetime.now().hour
        })
        if result:
            print(json.dumps(result, indent=2))
        else:
            print("No suitable question available")

    elif command == "context":
        print(synth.get_context_summary())

    elif command == "history":
        days = int(sys.argv[2]) if len(sys.argv) > 2 else 7
        if synth.asked_questions_file.exists():
            cutoff = datetime.now() - timedelta(days=days)
            with open(synth.asked_questions_file) as f:
                for line in f:
                    if line.strip():
                        entry = json.loads(line)
                        entry_time = datetime.fromisoformat(
                            entry["timestamp"].replace("Z", "+00:00")
                        )
                        if entry_time.replace(tzinfo=None) >= cutoff:
                            print(f"{entry['timestamp'][:10]} [{entry['category']}]: {entry['question'][:60]}...")
        else:
            print("No questions asked yet")

    elif command == "categories":
        for cat, data in QUESTION_TEMPLATES.items():
            print(f"\n## {cat.upper()}")
            print(f"*{data['description']}*")
            print(f"Templates: {len(data['templates'])}")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
