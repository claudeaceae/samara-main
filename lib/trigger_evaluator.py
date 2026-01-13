#!/usr/bin/env python3
"""
Trigger Evaluator for Claude's proactive engagement system.

Combines multiple signals to decide when proactive engagement is appropriate:
- Pattern-based triggers (temporal rhythms, topic recurrence)
- Calendar-based triggers (upcoming events, recently ended)
- Anomaly-based triggers (unusual silence, unexpected patterns)
- Cross-temporal triggers (connections to past conversations)
- Location-based triggers (arrival/departure, movement state)

Includes safeguards:
- 1-hour cooldown between proactive messages
- Quiet hours (11 PM - 7 AM)
- Recent interaction check (don't interrupt active conversations)
- Calendar respect (don't message during meetings)
- Confidence thresholds

Escalation model:
- < 0.3: Log only
- 0.3 - 0.6: Add to dream context
- 0.6 - 0.8: Include in wake prep
- > 0.8: Consider proactive message

Usage:
    from trigger_evaluator import TriggerEvaluator

    evaluator = TriggerEvaluator()
    decision = evaluator.evaluate()
    if decision["should_engage"]:
        # Send proactive message
"""

import os
import re
import json
from datetime import datetime, timedelta
from pathlib import Path
from mind_paths import get_mind_path
from typing import Optional

# Import other analyzers
try:
    from pattern_analyzer import PatternAnalyzer
    PATTERNS_AVAILABLE = True
except ImportError:
    PATTERNS_AVAILABLE = False

try:
    from calendar_analyzer import CalendarAnalyzer
    CALENDAR_AVAILABLE = True
except ImportError:
    CALENDAR_AVAILABLE = False

try:
    from chroma_helper import MemoryIndex
    CHROMA_AVAILABLE = True
except ImportError:
    CHROMA_AVAILABLE = False

try:
    from location_analyzer import LocationAnalyzer
    LOCATION_AVAILABLE = True
except ImportError:
    LOCATION_AVAILABLE = False

try:
    from weather_helper import WeatherHelper
    WEATHER_AVAILABLE = True
except ImportError:
    WEATHER_AVAILABLE = False

try:
    from question_synthesizer import QuestionSynthesizer
    QUESTIONS_AVAILABLE = True
except ImportError:
    QUESTIONS_AVAILABLE = False

MIND_PATH = get_mind_path()
STATE_PATH = MIND_PATH / "state"
EPISODES_PATH = MIND_PATH / "memory" / "episodes"


class TriggerEvaluator:
    """Evaluates whether to initiate proactive engagement."""

    # Safeguard constants
    COOLDOWN_MINUTES = 60
    QUIET_HOUR_START = 23  # 11 PM
    QUIET_HOUR_END = 7     # 7 AM
    RECENT_INTERACTION_HOURS = 2
    CONFIDENCE_THRESHOLD = 0.8

    def __init__(self):
        self.pattern_analyzer = PatternAnalyzer() if PATTERNS_AVAILABLE else None
        self.calendar_analyzer = CalendarAnalyzer() if CALENDAR_AVAILABLE else None
        self.chroma = MemoryIndex() if CHROMA_AVAILABLE else None
        self.location_analyzer = LocationAnalyzer() if LOCATION_AVAILABLE else None
        self.weather_helper = WeatherHelper() if WEATHER_AVAILABLE else None
        self.question_synthesizer = QuestionSynthesizer() if QUESTIONS_AVAILABLE else None
        STATE_PATH.mkdir(parents=True, exist_ok=True)

    def evaluate(self) -> dict:
        """
        Main evaluation function.

        Returns:
            dict with:
                - should_engage: bool
                - confidence: float (0-1)
                - reason: str (why engaging or not)
                - trigger_type: str (pattern, calendar, anomaly, cross_temporal)
                - suggested_message: str (if engaging)
                - escalation_level: str (log, dream, wake, engage)
                - safeguard_status: dict (which safeguards passed/failed)
        """
        now = datetime.now()

        # Check safeguards first
        safeguards = self._check_safeguards()
        if not safeguards["all_passed"]:
            return {
                "should_engage": False,
                "confidence": 0.0,
                "reason": safeguards["blocking_reason"],
                "trigger_type": None,
                "suggested_message": None,
                "escalation_level": "blocked",
                "safeguard_status": safeguards
            }

        # Collect all triggers
        triggers = []

        # Pattern-based triggers
        if self.pattern_analyzer:
            pattern_triggers = self._get_pattern_triggers()
            triggers.extend(pattern_triggers)

        # Calendar-based triggers
        if self.calendar_analyzer:
            calendar_triggers = self._get_calendar_triggers()
            triggers.extend(calendar_triggers)

        # Anomaly-based triggers
        anomaly_triggers = self._get_anomaly_triggers()
        triggers.extend(anomaly_triggers)

        # Cross-temporal triggers
        if self.chroma:
            cross_temporal = self._get_cross_temporal_triggers()
            triggers.extend(cross_temporal)

        # Location-based triggers
        if self.location_analyzer:
            location_triggers = self._get_location_triggers()
            triggers.extend(location_triggers)

            # Check for motion suppression (don't engage while collaborator is moving)
            for lt in location_triggers:
                if lt.get("suppress_engagement"):
                    return {
                        "should_engage": False,
                        "confidence": 0.0,
                        "reason": lt.get("reason", "In motion"),
                        "trigger_type": "location",
                        "suggested_message": None,
                        "escalation_level": "suppressed",
                        "safeguard_status": safeguards
                    }

            # Battery-based triggers
            battery_triggers = self._get_battery_triggers()
            triggers.extend(battery_triggers)

            # Check for low battery suppression of non-urgent messages
            for bt in battery_triggers:
                if bt.get("suppress_non_urgent"):
                    # Don't suppress entirely, but note it for the evaluator
                    safeguards["low_battery"] = True

        # Weather-based triggers
        if self.weather_helper:
            weather_triggers = self._get_weather_triggers()
            triggers.extend(weather_triggers)

        # Question-based triggers (proactive questioning)
        if self.question_synthesizer:
            question_triggers = self._get_question_triggers()
            triggers.extend(question_triggers)

        if not triggers:
            return {
                "should_engage": False,
                "confidence": 0.0,
                "reason": "No triggers detected",
                "trigger_type": None,
                "suggested_message": None,
                "escalation_level": "log",
                "safeguard_status": safeguards
            }

        # Find highest confidence trigger
        triggers.sort(key=lambda t: t.get("confidence", 0), reverse=True)
        best_trigger = triggers[0]
        confidence = best_trigger.get("confidence", 0)

        # Determine escalation level
        if confidence < 0.3:
            escalation = "log"
        elif confidence < 0.6:
            escalation = "dream"
        elif confidence < 0.8:
            escalation = "wake"
        else:
            escalation = "engage"

        # Log the evaluation
        self._log_evaluation(triggers, best_trigger, escalation)

        return {
            "should_engage": escalation == "engage",
            "confidence": confidence,
            "reason": best_trigger.get("reason", "Unknown trigger"),
            "trigger_type": best_trigger.get("type", "unknown"),
            "suggested_message": best_trigger.get("suggested_message"),
            "escalation_level": escalation,
            "safeguard_status": safeguards,
            "all_triggers": triggers[:5]  # Top 5 for context
        }

    def _check_safeguards(self) -> dict:
        """Check all safeguards."""
        now = datetime.now()
        results = {
            "all_passed": True,
            "blocking_reason": None,
            "checks": {}
        }

        # 1. Quiet hours check
        hour = now.hour
        in_quiet_hours = hour >= self.QUIET_HOUR_START or hour < self.QUIET_HOUR_END
        results["checks"]["quiet_hours"] = not in_quiet_hours
        if in_quiet_hours:
            results["all_passed"] = False
            results["blocking_reason"] = f"Quiet hours ({self.QUIET_HOUR_START}:00 - {self.QUIET_HOUR_END}:00)"
            return results

        # 2. Cooldown check
        last_trigger_file = STATE_PATH / "last-proactive-trigger.txt"
        cooldown_ok = True
        if last_trigger_file.exists():
            try:
                last_trigger = int(last_trigger_file.read_text().strip())
                elapsed = (now.timestamp() - last_trigger) / 60
                cooldown_ok = elapsed >= self.COOLDOWN_MINUTES
                if not cooldown_ok:
                    remaining = int(self.COOLDOWN_MINUTES - elapsed)
                    results["all_passed"] = False
                    results["blocking_reason"] = f"Cooldown active ({remaining} min remaining)"
            except:
                cooldown_ok = True
        results["checks"]["cooldown"] = cooldown_ok
        if not cooldown_ok:
            return results

        # 3. Recent interaction check
        recent_interaction = self._check_recent_interaction()
        results["checks"]["no_recent_interaction"] = not recent_interaction
        if recent_interaction:
            results["all_passed"] = False
            results["blocking_reason"] = "Recent conversation activity"
            return results

        # 4. In meeting check
        in_meeting = self._check_in_meeting()
        results["checks"]["not_in_meeting"] = not in_meeting
        if in_meeting:
            results["all_passed"] = False
            results["blocking_reason"] = "Collaborator appears to be in a meeting"
            return results

        return results

    def _check_recent_interaction(self) -> bool:
        """Check if there's been recent conversation activity."""
        today = datetime.now().strftime("%Y-%m-%d")
        episode_file = EPISODES_PATH / f"{today}.md"

        if not episode_file.exists():
            return False

        try:
            content = episode_file.read_text()
            cutoff = datetime.now() - timedelta(hours=self.RECENT_INTERACTION_HOURS)

            # Look for timestamps in the last N hours
            for hour_offset in range(self.RECENT_INTERACTION_HOURS + 1):
                check_time = datetime.now() - timedelta(hours=hour_offset)
                time_pattern = f"## {check_time.strftime('%H')}:"
                if time_pattern in content:
                    return True

            return False
        except:
            return False

    def _check_in_meeting(self) -> bool:
        """Check if the collaborator is currently in a meeting."""
        if not self.calendar_analyzer:
            return False

        try:
            # Get events happening right now
            upcoming = self.calendar_analyzer.get_upcoming_events(hours=0)
            # If there's an event with minutes_until <= 0, we're in a meeting
            for event in upcoming:
                if event.get("minutes_until", 999) <= 0:
                    return True
            return False
        except:
            return False

    def _get_pattern_triggers(self) -> list:
        """Get triggers based on pattern analysis."""
        triggers = []

        try:
            # Load cached patterns
            patterns_file = STATE_PATH / "patterns.json"
            if not patterns_file.exists():
                return triggers

            patterns = json.loads(patterns_file.read_text())

            # Check temporal patterns
            temporal = patterns.get("temporal", {})
            active_hours = temporal.get("active_hours", [])
            current_hour = datetime.now().hour

            # If we're in an active hour but no recent messages, might be worth checking in
            if current_hour in active_hours:
                anomalies = patterns.get("anomalies", {})
                today_status = anomalies.get("today_status", {})
                today_messages = today_status.get("messages", 0)
                avg_messages = temporal.get("avg_messages_per_day", 0)

                # If significantly below average for this time
                if avg_messages > 0 and today_messages < avg_messages * 0.3:
                    triggers.append({
                        "type": "pattern",
                        "confidence": 0.4,  # Low - just noting the pattern
                        "reason": f"Quieter than usual ({today_messages} messages vs {avg_messages:.0f} avg)",
                        "suggested_message": None
                    })

            # Check for topic patterns that might be worth revisiting
            topics = patterns.get("topics", {})
            recurring = topics.get("recurring_themes", [])
            if recurring:
                # High-recurrence topics might be worth proactive engagement
                top_theme = recurring[0]
                if top_theme.get("days_present", 0) >= 5:
                    triggers.append({
                        "type": "pattern",
                        "confidence": 0.3,  # Low - for dream context
                        "reason": f"Recurring theme: {top_theme.get('topic')}",
                        "suggested_message": None
                    })

        except Exception as e:
            pass

        return triggers

    def _get_calendar_triggers(self) -> list:
        """Get triggers based on calendar events."""
        triggers = []

        try:
            calendar_triggers = self.calendar_analyzer.check_for_triggers()
            for t in calendar_triggers:
                triggers.append({
                    "type": "calendar",
                    "confidence": t.get("confidence", 0.5),
                    "reason": t.get("suggested_action", "Calendar event"),
                    "suggested_message": self._generate_calendar_message(t),
                    "event": t.get("event")
                })
        except:
            pass

        return triggers

    def _get_anomaly_triggers(self) -> list:
        """Get triggers based on detected anomalies."""
        triggers = []

        try:
            patterns_file = STATE_PATH / "patterns.json"
            if not patterns_file.exists():
                return triggers

            patterns = json.loads(patterns_file.read_text())
            anomalies = patterns.get("anomalies", {}).get("anomalies", [])

            for anomaly in anomalies:
                severity = anomaly.get("severity", "low")
                if severity == "high":
                    confidence = 0.7
                elif severity == "medium":
                    confidence = 0.5
                else:
                    confidence = 0.3

                triggers.append({
                    "type": "anomaly",
                    "confidence": confidence,
                    "reason": anomaly.get("description", "Unusual pattern"),
                    "suggested_message": None
                })

        except:
            pass

        return triggers

    def _get_cross_temporal_triggers(self) -> list:
        """Get triggers based on cross-temporal connections."""
        triggers = []

        if not self.chroma:
            return triggers

        try:
            # Look for connections between today and past conversations
            today = datetime.now().strftime("%Y-%m-%d")
            episode_file = EPISODES_PATH / f"{today}.md"

            if not episode_file.exists():
                return triggers

            # Get today's content
            today_content = episode_file.read_text()[:1000]

            # Search for related past content
            results = self.chroma.search(today_content, n_results=5)

            # Check if there are strong connections to past days
            for result in results:
                metadata = result.get("metadata", {})
                date = metadata.get("date", "")
                distance = result.get("distance", 1.0)

                # Skip today's content
                if date == today:
                    continue

                # Strong semantic similarity (low distance)
                if distance < 0.3:
                    triggers.append({
                        "type": "cross_temporal",
                        "confidence": 0.5,  # Medium - worth noting
                        "reason": f"Today's conversation relates to {date}",
                        "suggested_message": None,
                        "related_text": result.get("text", "")[:200]
                    })

        except:
            pass

        return triggers

    def _get_location_triggers(self) -> list:
        """Get triggers based on location state."""
        if not self.location_analyzer:
            return []

        try:
            return self.location_analyzer.get_location_triggers()
        except:
            return []

    def _get_battery_triggers(self) -> list:
        """Get triggers based on battery level."""
        if not self.location_analyzer:
            return []

        try:
            return self.location_analyzer.get_battery_triggers()
        except:
            return []

    def _get_weather_triggers(self) -> list:
        """Get triggers based on weather conditions."""
        if not self.weather_helper:
            return []

        try:
            return self.weather_helper.get_weather_triggers()
        except:
            return []

    def _get_question_triggers(self) -> list:
        """Get triggers based on proactive questioning opportunities."""
        if not self.question_synthesizer:
            return []

        triggers = []
        try:
            # Build context for question generation
            context = {
                "trigger": "check_triggers",
                "hour": datetime.now().hour
            }

            # Add location context if available
            if self.location_analyzer:
                try:
                    current_place = self.location_analyzer.get_current_place()
                    if current_place:
                        context["current_place"] = current_place.get("name")
                except:
                    pass

            # Add calendar context if available
            if self.calendar_analyzer:
                try:
                    recent = self.calendar_analyzer.get_recently_ended(hours=1)
                    if recent:
                        context["recent_event"] = recent[0].get("summary")
                        context["trigger"] = "calendar_ended"
                except:
                    pass

            # Try to synthesize a question
            result = self.question_synthesizer.synthesize(context)
            if result and result.get("confidence", 0) >= 0.6:
                triggers.append({
                    "type": "question",
                    "subtype": result.get("category"),
                    "confidence": result["confidence"],
                    "reason": f"Proactive question opportunity ({result.get('category')})",
                    "suggested_message": result.get("question"),
                    "question_context": result
                })

        except Exception as e:
            pass

        return triggers

    def _generate_calendar_message(self, trigger: dict) -> Optional[str]:
        """Generate a suggested message for a calendar trigger."""
        event = trigger.get("event", "event")
        trigger_type = trigger.get("type", "")

        if trigger_type == "upcoming_event":
            minutes = trigger.get("minutes_until", 60)
            if minutes < 30:
                return f"Your {event} is coming up in about {minutes} minutes. Need any prep?"
            else:
                return f"I noticed you have {event} coming up. Want me to pull up any relevant context?"

        elif trigger_type == "recently_ended":
            return f"How did {event} go?"

        return None

    def _log_evaluation(self, triggers: list, best: dict, escalation: str):
        """Log the evaluation for later analysis."""
        log_file = STATE_PATH / "trigger-evaluations.jsonl"

        entry = {
            "timestamp": datetime.now().isoformat(),
            "trigger_count": len(triggers),
            "best_trigger": {
                "type": best.get("type"),
                "confidence": best.get("confidence"),
                "reason": best.get("reason")
            },
            "escalation": escalation
        }

        try:
            with open(log_file, "a") as f:
                f.write(json.dumps(entry) + "\n")
        except:
            pass

    def record_engagement(self):
        """Record that a proactive engagement happened (for cooldown)."""
        timestamp_file = STATE_PATH / "last-proactive-trigger.txt"
        timestamp_file.write_text(str(int(datetime.now().timestamp())))

    def get_escalation_summary(self) -> str:
        """
        Get a summary of recent trigger evaluations.

        Useful for including in dream/wake context.
        """
        log_file = STATE_PATH / "trigger-evaluations.jsonl"

        if not log_file.exists():
            return "No trigger evaluations recorded yet."

        try:
            lines = log_file.read_text().strip().split("\n")[-10:]  # Last 10
            evaluations = [json.loads(line) for line in lines if line]

            if not evaluations:
                return "No trigger evaluations recorded yet."

            # Summarize
            high_conf = sum(1 for e in evaluations
                          if e.get("best_trigger", {}).get("confidence", 0) >= 0.6)
            engaged = sum(1 for e in evaluations if e.get("escalation") == "engage")

            summary = f"Recent triggers: {len(evaluations)} evaluations, "
            summary += f"{high_conf} high-confidence, {engaged} engagements"

            return summary
        except:
            return "Error reading trigger evaluations."


def main():
    """CLI interface for trigger evaluator."""
    import sys

    if len(sys.argv) < 2:
        print("Usage: trigger_evaluator.py <command>")
        print("Commands:")
        print("  evaluate  - Run full evaluation")
        print("  safeguards - Check safeguards only")
        print("  summary   - Get escalation summary")
        sys.exit(1)

    command = sys.argv[1]
    evaluator = TriggerEvaluator()

    if command == "evaluate":
        result = evaluator.evaluate()
        print(json.dumps(result, indent=2, default=str))

    elif command == "safeguards":
        safeguards = evaluator._check_safeguards()
        print(json.dumps(safeguards, indent=2))

    elif command == "summary":
        print(evaluator.get_escalation_summary())

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
