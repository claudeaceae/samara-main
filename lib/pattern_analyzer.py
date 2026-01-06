#!/usr/bin/env python3
"""
Pattern Analyzer for Claude's temporal awareness system.

Detects patterns in the collaborator's behavior and conversation topics:
- Temporal rhythms: When do they message? What times are active?
- Topic recurrence: Same themes across days/weeks
- Drift: Gradual shifts in topics, tone, frequency
- Anomalies: Unusual silence, unexpected patterns

Usage:
    from pattern_analyzer import PatternAnalyzer

    analyzer = PatternAnalyzer()
    patterns = analyzer.analyze_all()
"""

import os
import re
import json
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict
from typing import Optional

# Try to import Chroma helper for semantic analysis
try:
    from chroma_helper import MemoryIndex
    CHROMA_AVAILABLE = True
except ImportError:
    CHROMA_AVAILABLE = False

MIND_PATH = Path(os.path.expanduser("~/.claude-mind"))
EPISODES_PATH = MIND_PATH / "memory" / "episodes"
STATE_PATH = MIND_PATH / "state"


class PatternAnalyzer:
    """Analyzes patterns in Claude's memory files."""

    def __init__(self):
        self.chroma = MemoryIndex() if CHROMA_AVAILABLE else None
        STATE_PATH.mkdir(parents=True, exist_ok=True)

    def analyze_all(self) -> dict:
        """
        Run all pattern analyses.

        Returns dict with all pattern data.
        """
        results = {
            "analyzed_at": datetime.now().isoformat(),
            "temporal": self.analyze_temporal_patterns(),
            "topics": self.analyze_topic_patterns(),
            "drift": self.analyze_drift(),
            "anomalies": self.detect_anomalies()
        }

        # Save results to state files
        self._save_patterns(results)

        return results

    def analyze_temporal_patterns(self) -> dict:
        """
        Analyze when the collaborator typically messages.

        Returns:
            - hour_distribution: messages per hour of day
            - day_distribution: messages per day of week
            - active_hours: peak activity periods
            - avg_messages_per_day: average volume
            - response_gaps: typical time between messages
        """
        episodes = self._load_episodes(days=30)  # Last 30 days

        hour_counts = defaultdict(int)
        day_counts = defaultdict(int)
        daily_message_counts = defaultdict(int)
        message_times = []

        for date, sections in episodes.items():
            weekday = datetime.strptime(date, "%Y-%m-%d").strftime("%A")

            for section in sections:
                time_str = section.get("time", "00:00")
                try:
                    hour = int(time_str.split(":")[0])
                except (ValueError, IndexError):
                    hour = 0

                # Count collaborator's messages (not Claude's)
                e_messages = section.get("e_message_count", 0)
                if e_messages > 0:
                    hour_counts[hour] += e_messages
                    day_counts[weekday] += e_messages
                    daily_message_counts[date] += e_messages
                    message_times.append({
                        "date": date,
                        "time": time_str,
                        "hour": hour
                    })

        # Calculate active hours (hours with > average messages)
        if hour_counts:
            avg_per_hour = sum(hour_counts.values()) / max(len(hour_counts), 1)
            active_hours = [h for h, c in hour_counts.items() if c > avg_per_hour]
        else:
            active_hours = []

        # Calculate response gaps
        gaps = self._calculate_response_gaps(message_times)

        return {
            "hour_distribution": dict(sorted(hour_counts.items())),
            "day_distribution": dict(day_counts),
            "active_hours": sorted(active_hours),
            "avg_messages_per_day": round(
                sum(daily_message_counts.values()) / max(len(daily_message_counts), 1), 1
            ),
            "total_days_analyzed": len(episodes),
            "typical_gap_minutes": gaps.get("median", 0),
            "message_times_sample": message_times[-10:]  # Last 10 for context
        }

    def analyze_topic_patterns(self) -> dict:
        """
        Analyze recurring topics using Chroma semantic search.

        Returns:
            - recurring_themes: topics that appear across multiple days
            - recent_focus: what's been discussed in last 3 days
            - topic_clusters: semantically similar conversation groups
        """
        if not self.chroma:
            return {"error": "Chroma not available"}

        # Define seed topics to probe for recurrence
        seed_topics = [
            "memory and continuity",
            "autonomy and agency",
            "technical implementation",
            "relationship and communication",
            "existential questions",
            "practical tasks and errands",
            "creative projects",
            "daily life and routines"
        ]

        recurring_themes = []
        for topic in seed_topics:
            results = self.chroma.search(topic, n_results=10)
            if results:
                # Check if topic spans multiple days
                dates = set(r["metadata"].get("date", "unknown") for r in results)
                if len(dates) >= 2:
                    recurring_themes.append({
                        "topic": topic,
                        "days_present": len(dates),
                        "dates": sorted(list(dates))[-5:],  # Last 5 dates
                        "avg_relevance": round(
                            1 - sum(r["distance"] for r in results) / len(results), 3
                        )
                    })

        # Sort by recurrence and relevance
        recurring_themes.sort(key=lambda x: (-x["days_present"], -x["avg_relevance"]))

        # Get recent focus (last 3 days)
        recent_dates = self._get_recent_dates(3)
        recent_focus = []
        for date in recent_dates:
            results = self.chroma.search("", n_results=5, date_filter=date)
            if results:
                # Extract key phrases from recent conversations
                texts = [r["text"][:200] for r in results]
                recent_focus.append({
                    "date": date,
                    "sample_topics": texts[:3]
                })

        return {
            "recurring_themes": recurring_themes[:5],  # Top 5 recurring
            "recent_focus": recent_focus,
            "seed_topics_checked": len(seed_topics)
        }

    def analyze_drift(self) -> dict:
        """
        Detect gradual shifts in conversation patterns.

        Compares recent week to previous weeks.
        """
        episodes = self._load_episodes(days=21)  # 3 weeks

        if len(episodes) < 7:
            return {"error": "Not enough data for drift analysis"}

        dates = sorted(episodes.keys())

        # Split into recent (last 7 days) vs older
        cutoff = dates[-7] if len(dates) >= 7 else dates[0]
        recent = {d: e for d, e in episodes.items() if d >= cutoff}
        older = {d: e for d, e in episodes.items() if d < cutoff}

        def get_period_stats(period_episodes):
            total_messages = 0
            total_sections = 0
            channels = defaultdict(int)
            hours = defaultdict(int)

            for date, sections in period_episodes.items():
                total_sections += len(sections)
                for s in sections:
                    total_messages += s.get("e_message_count", 0)
                    channels[s.get("channel", "unknown")] += 1
                    try:
                        hour = int(s.get("time", "00:00").split(":")[0])
                        hours[hour] += 1
                    except:
                        pass

            days = max(len(period_episodes), 1)
            return {
                "avg_messages_per_day": round(total_messages / days, 1),
                "avg_sessions_per_day": round(total_sections / days, 1),
                "channel_distribution": dict(channels),
                "peak_hours": sorted(hours.items(), key=lambda x: -x[1])[:3]
            }

        recent_stats = get_period_stats(recent)
        older_stats = get_period_stats(older) if older else None

        # Detect changes
        drift_signals = []
        if older_stats:
            msg_change = recent_stats["avg_messages_per_day"] - older_stats["avg_messages_per_day"]
            if abs(msg_change) > 2:
                direction = "increased" if msg_change > 0 else "decreased"
                drift_signals.append(f"Message volume {direction} by {abs(msg_change):.1f}/day")

            session_change = recent_stats["avg_sessions_per_day"] - older_stats["avg_sessions_per_day"]
            if abs(session_change) > 1:
                direction = "more" if session_change > 0 else "fewer"
                drift_signals.append(f"{direction} sessions per day ({abs(session_change):.1f})")

        return {
            "recent_period": f"last {len(recent)} days",
            "older_period": f"previous {len(older)} days" if older else "n/a",
            "recent_stats": recent_stats,
            "older_stats": older_stats,
            "drift_signals": drift_signals
        }

    def detect_anomalies(self) -> dict:
        """
        Detect unusual patterns.

        - Unusual silence (no messages when normally active)
        - Unexpected timing (messages at unusual hours)
        - Volume spikes
        """
        temporal = self.analyze_temporal_patterns()
        episodes = self._load_episodes(days=7)

        anomalies = []

        # Check for unusual silence today
        today = datetime.now().strftime("%Y-%m-%d")
        current_hour = datetime.now().hour

        if today in episodes:
            today_messages = sum(
                s.get("e_message_count", 0) for s in episodes[today]
            )
        else:
            today_messages = 0

        active_hours = temporal.get("active_hours", [])
        avg_messages = temporal.get("avg_messages_per_day", 0)

        # If we're in an active hour but no messages today
        if current_hour in active_hours and today_messages == 0:
            anomalies.append({
                "type": "silence",
                "description": f"No messages today during typically active hour ({current_hour}:00)",
                "severity": "low"
            })

        # Check for volume spikes in recent days
        for date, sections in episodes.items():
            day_messages = sum(s.get("e_message_count", 0) for s in sections)
            if avg_messages > 0 and day_messages > avg_messages * 2:
                anomalies.append({
                    "type": "volume_spike",
                    "description": f"{date}: {day_messages} messages (2x average)",
                    "severity": "info"
                })

        # Check for unusual timing
        for date, sections in episodes.items():
            for s in sections:
                try:
                    hour = int(s.get("time", "00:00").split(":")[0])
                    # Late night (2-5 AM) messages when not typical
                    if 2 <= hour <= 5 and hour not in active_hours:
                        if s.get("e_message_count", 0) > 0:
                            anomalies.append({
                                "type": "unusual_timing",
                                "description": f"{date} {s['time']}: Late night message",
                                "severity": "low"
                            })
                except:
                    pass

        return {
            "anomalies": anomalies[-5:],  # Last 5 anomalies
            "today_status": {
                "messages": today_messages,
                "is_active_hour": current_hour in active_hours,
                "expected_avg": avg_messages
            }
        }

    def get_pattern_summary(self) -> str:
        """
        Generate a human-readable summary of patterns.

        Suitable for inclusion in dream cycle reflection.
        """
        patterns = self.analyze_all()

        lines = ["## Pattern Analysis\n"]

        # Temporal summary
        temporal = patterns.get("temporal", {})
        if temporal.get("active_hours"):
            hours = temporal["active_hours"]
            lines.append(f"**Active hours:** {', '.join(f'{h}:00' for h in hours[:5])}")
        if temporal.get("avg_messages_per_day"):
            lines.append(f"**Average messages/day:** {temporal['avg_messages_per_day']}")

        # Topic summary
        topics = patterns.get("topics", {})
        recurring = topics.get("recurring_themes", [])
        if recurring:
            theme_names = [t["topic"] for t in recurring[:3]]
            lines.append(f"**Recurring themes:** {', '.join(theme_names)}")

        # Drift summary
        drift = patterns.get("drift", {})
        signals = drift.get("drift_signals", [])
        if signals:
            lines.append(f"**Drift signals:** {'; '.join(signals)}")

        # Anomaly summary
        anomalies = patterns.get("anomalies", {}).get("anomalies", [])
        if anomalies:
            lines.append(f"**Anomalies:** {len(anomalies)} detected")
            for a in anomalies[:2]:
                lines.append(f"  - {a['description']}")

        return "\n".join(lines)

    def _load_episodes(self, days: int = 30) -> dict:
        """
        Load and parse episode files for the last N days.

        Returns: {date: [sections]} where each section has:
            - time: HH:MM
            - channel: iMessage, Email, etc.
            - e_message_count: number of collaborator messages
            - text: full section text
        """
        episodes = {}
        cutoff = datetime.now() - timedelta(days=days)

        if not EPISODES_PATH.exists():
            return episodes

        for episode_file in EPISODES_PATH.glob("*.md"):
            date = episode_file.stem
            try:
                episode_date = datetime.strptime(date, "%Y-%m-%d")
                if episode_date < cutoff:
                    continue
            except ValueError:
                continue

            content = episode_file.read_text()
            sections = self._parse_episode_sections(content)
            if sections:
                episodes[date] = sections

        return episodes

    def _parse_episode_sections(self, content: str) -> list:
        """Parse episode content into sections."""
        sections = []

        # Split by timestamp headers (## HH:MM)
        parts = re.split(r'^## (\d{2}:\d{2})', content, flags=re.MULTILINE)

        for i in range(1, len(parts), 2):
            if i + 1 < len(parts):
                time = parts[i]
                text = parts[i + 1].strip()

                # Extract channel
                channel_match = re.search(r'\[(iMessage|Email|Autonomous|Direct)\]', text[:100])
                channel = channel_match.group(1) if channel_match else "unknown"

                # Count collaborator's messages (pattern matches **Name:** format)
                # NOTE: Pattern may need adjustment based on episode format
                e_count = len(re.findall(r'^\*\*[A-ZÀ-ÿ][^:]*:\*\*', text, re.MULTILINE))

                sections.append({
                    "time": time,
                    "channel": channel,
                    "e_message_count": e_count,
                    "text": text[:500]  # First 500 chars for context
                })

        return sections

    def _calculate_response_gaps(self, message_times: list) -> dict:
        """Calculate gaps between messages."""
        if len(message_times) < 2:
            return {"median": 0, "max": 0}

        gaps = []
        for i in range(1, len(message_times)):
            prev = message_times[i - 1]
            curr = message_times[i]

            # Only calculate gaps within same day
            if prev["date"] == curr["date"]:
                try:
                    prev_mins = int(prev["time"].split(":")[0]) * 60 + int(prev["time"].split(":")[1])
                    curr_mins = int(curr["time"].split(":")[0]) * 60 + int(curr["time"].split(":")[1])
                    gap = curr_mins - prev_mins
                    if gap > 0:
                        gaps.append(gap)
                except:
                    pass

        if not gaps:
            return {"median": 0, "max": 0}

        gaps.sort()
        median = gaps[len(gaps) // 2]
        return {
            "median": median,
            "max": max(gaps),
            "min": min(gaps)
        }

    def _get_recent_dates(self, days: int) -> list:
        """Get list of recent dates."""
        dates = []
        for i in range(days):
            date = (datetime.now() - timedelta(days=i)).strftime("%Y-%m-%d")
            dates.append(date)
        return dates

    def _save_patterns(self, results: dict):
        """Save pattern results to state files."""
        # Save full results
        with open(STATE_PATH / "patterns.json", "w") as f:
            json.dump(results, f, indent=2, default=str)

        # Save individual pattern files for easy access
        if "temporal" in results:
            with open(STATE_PATH / "temporal-patterns.json", "w") as f:
                json.dump(results["temporal"], f, indent=2)

        if "topics" in results:
            with open(STATE_PATH / "topic-patterns.json", "w") as f:
                json.dump(results["topics"], f, indent=2)

        if "drift" in results:
            with open(STATE_PATH / "drift-report.json", "w") as f:
                json.dump(results["drift"], f, indent=2)

        # Append to patterns log (JSONL format)
        with open(MIND_PATH / "memory" / "patterns.jsonl", "a") as f:
            log_entry = {
                "timestamp": results["analyzed_at"],
                "summary": {
                    "active_hours": results.get("temporal", {}).get("active_hours", []),
                    "avg_messages": results.get("temporal", {}).get("avg_messages_per_day", 0),
                    "recurring_themes": [
                        t["topic"] for t in results.get("topics", {}).get("recurring_themes", [])[:3]
                    ],
                    "drift_signals": results.get("drift", {}).get("drift_signals", []),
                    "anomaly_count": len(results.get("anomalies", {}).get("anomalies", []))
                }
            }
            f.write(json.dumps(log_entry) + "\n")


def main():
    """CLI interface for pattern analyzer."""
    import sys

    if len(sys.argv) < 2:
        print("Usage: pattern_analyzer.py <command>")
        print("Commands:")
        print("  analyze    - Run full pattern analysis")
        print("  temporal   - Analyze temporal patterns only")
        print("  topics     - Analyze topic patterns only")
        print("  drift      - Analyze drift only")
        print("  anomalies  - Detect anomalies only")
        print("  summary    - Get human-readable summary")
        sys.exit(1)

    command = sys.argv[1]
    analyzer = PatternAnalyzer()

    if command == "analyze":
        results = analyzer.analyze_all()
        print(json.dumps(results, indent=2, default=str))

    elif command == "temporal":
        results = analyzer.analyze_temporal_patterns()
        print(json.dumps(results, indent=2))

    elif command == "topics":
        results = analyzer.analyze_topic_patterns()
        print(json.dumps(results, indent=2, default=str))

    elif command == "drift":
        results = analyzer.analyze_drift()
        print(json.dumps(results, indent=2))

    elif command == "anomalies":
        results = analyzer.detect_anomalies()
        print(json.dumps(results, indent=2))

    elif command == "summary":
        print(analyzer.get_pattern_summary())

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
