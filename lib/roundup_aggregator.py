#!/usr/bin/env python3
"""
Roundup Aggregator for Claude's analytics system.

Collects metrics across three categories:
- Relational: Messages, conversations, themes, response patterns
- Productive: Git commits, code changes, learnings, decisions
- Reflective: Reflections, questions, observations, dream cycles

Usage:
    python3 roundup_aggregator.py weekly [YYYY-Www]
    python3 roundup_aggregator.py monthly [YYYY-MM]
    python3 roundup_aggregator.py yearly [YYYY]

Example:
    python3 roundup_aggregator.py weekly 2026-W01
    python3 roundup_aggregator.py monthly 2026-01
    python3 roundup_aggregator.py yearly 2026
"""

import os
import re
import json
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict
from typing import Optional, Tuple
import sys

MIND_PATH = Path(os.path.expanduser("~/.claude-mind"))
EPISODES_PATH = MIND_PATH / "memory" / "episodes"
REFLECTIONS_PATH = MIND_PATH / "memory" / "reflections"
ROUNDUPS_PATH = MIND_PATH / "roundups"
STATE_PATH = MIND_PATH / "state"
LOGS_PATH = MIND_PATH / "logs"
WWW_PATH = Path(os.path.expanduser("~/Developer/website"))
DEVELOPER_PATH = Path(os.path.expanduser("~/Developer"))


class RoundupAggregator:
    """Aggregates metrics for roundup reports."""

    def __init__(self, period_type: str, period: Optional[str] = None):
        """
        Initialize aggregator for a specific period.

        Args:
            period_type: 'weekly', 'monthly', or 'yearly'
            period: Period identifier (e.g., '2026-W01', '2026-01', '2026')
                   If None, uses current period.
        """
        self.period_type = period_type
        self.period = period or self._current_period()
        self.start_date, self.end_date = self._parse_period()

    def _current_period(self) -> str:
        """Get identifier for current period."""
        now = datetime.now()
        if self.period_type == "weekly":
            return now.strftime("%G-W%V")
        elif self.period_type == "monthly":
            return now.strftime("%Y-%m")
        else:
            return now.strftime("%Y")

    def _parse_period(self) -> Tuple[datetime, datetime]:
        """Parse period string into start and end dates."""
        if self.period_type == "weekly":
            # ISO week format: 2026-W01
            year, week = self.period.split("-W")
            start = datetime.strptime(f"{year}-W{week}-1", "%G-W%V-%u")
            end = start + timedelta(days=6)
        elif self.period_type == "monthly":
            # Month format: 2026-01
            start = datetime.strptime(f"{self.period}-01", "%Y-%m-%d")
            # End is last day of month
            if start.month == 12:
                end = datetime(start.year + 1, 1, 1) - timedelta(days=1)
            else:
                end = datetime(start.year, start.month + 1, 1) - timedelta(days=1)
        else:
            # Year format: 2026
            start = datetime(int(self.period), 1, 1)
            end = datetime(int(self.period), 12, 31)

        return start, end

    def aggregate(self) -> dict:
        """
        Run full aggregation for the period.

        Returns complete roundup data structure.
        """
        return {
            "period": self.period,
            "period_type": self.period_type,
            "date_range": {
                "start": self.start_date.strftime("%Y-%m-%d"),
                "end": self.end_date.strftime("%Y-%m-%d")
            },
            "generated_at": datetime.now().isoformat(),
            "relational": self._aggregate_relational(),
            "productive": self._aggregate_productive(),
            "reflective": self._aggregate_reflective(),
            "highlights": self._extract_highlights()
        }

    def _dates_in_range(self) -> list[str]:
        """Get list of date strings (YYYY-MM-DD) in the period."""
        dates = []
        current = self.start_date
        while current <= self.end_date:
            dates.append(current.strftime("%Y-%m-%d"))
            current += timedelta(days=1)
        return dates

    # =========================================================================
    # RELATIONAL METRICS
    # =========================================================================

    def _aggregate_relational(self) -> dict:
        """Aggregate relational metrics: messages, conversations, themes."""
        dates = self._dates_in_range()

        messages_sent = 0
        messages_received = 0
        conversations = 0
        session_count = 0

        for date in dates:
            episode_file = EPISODES_PATH / f"{date}.md"
            if episode_file.exists():
                content = episode_file.read_text()
                # Count collaborator messages (lines starting with **Name:**)
                # NOTE: Pattern may need adjustment based on episode format
                messages_received += len(re.findall(r"^\*\*[A-ZÀ-ÿ][^:]*:\*\*", content, re.MULTILINE))
                # Count Claude messages (lines starting with **Claude:**)
                messages_sent += len(re.findall(r"^\*\*Claude:\*\*", content, re.MULTILINE))
                # Count sessions (## HH:MM headers)
                session_count += len(re.findall(r"^## \d{2}:\d{2}", content, re.MULTILINE))

        # Count from messages-sent.log for outgoing messages
        sent_log = LOGS_PATH / "messages-sent.log"
        if sent_log.exists():
            log_content = sent_log.read_text()
            for line in log_content.split("\n"):
                if not line.strip():
                    continue
                # Parse timestamp: [2026-01-02 14:32:15]
                match = re.match(r"\[(\d{4}-\d{2}-\d{2})", line)
                if match:
                    log_date = match.group(1)
                    if log_date in dates:
                        messages_sent += 1

        # Get themes from patterns.json if available
        top_themes = []
        patterns_file = STATE_PATH / "patterns.json"
        if patterns_file.exists():
            try:
                patterns = json.loads(patterns_file.read_text())
                topics = patterns.get("topics", {}).get("recurring_themes", [])
                # Get top 5 themes (key is "topic" not "theme")
                top_themes = [t.get("topic", "") for t in topics[:5] if isinstance(t, dict) and t.get("topic")]
            except (json.JSONDecodeError, KeyError):
                pass

        # Estimate conversations (sessions with at least one exchange)
        conversations = max(session_count // 2, 1) if session_count > 0 else 0

        return {
            "messages_sent": messages_sent,
            "messages_received": messages_received,
            "total_messages": messages_sent + messages_received,
            "conversations": conversations,
            "sessions": session_count,
            "top_themes": top_themes,
            "avg_messages_per_day": round(
                (messages_sent + messages_received) / max(len(dates), 1), 1
            )
        }

    # =========================================================================
    # PRODUCTIVE METRICS
    # =========================================================================

    def _aggregate_productive(self) -> dict:
        """Aggregate productive metrics: git, code, learnings."""
        dates = self._dates_in_range()
        start_str = self.start_date.strftime("%Y-%m-%d")
        end_str = (self.end_date + timedelta(days=1)).strftime("%Y-%m-%d")

        # Git stats across repos
        git_commits = 0
        lines_added = 0
        lines_deleted = 0
        repos_touched = set()

        repos_to_check = [
            MIND_PATH,
            DEVELOPER_PATH / "samara-main",
            DEVELOPER_PATH / "Samara",
            WWW_PATH,
        ]

        for repo in repos_to_check:
            if not (repo / ".git").exists():
                continue
            try:
                # Count commits in date range
                result = subprocess.run(
                    ["git", "-C", str(repo), "log",
                     f"--since={start_str}", f"--until={end_str}",
                     "--oneline"],
                    capture_output=True, text=True, timeout=10
                )
                commit_count = len(result.stdout.strip().split("\n")) if result.stdout.strip() else 0
                if commit_count > 0:
                    git_commits += commit_count
                    repos_touched.add(repo.name)

                # Get line changes
                result = subprocess.run(
                    ["git", "-C", str(repo), "log",
                     f"--since={start_str}", f"--until={end_str}",
                     "--numstat", "--format="],
                    capture_output=True, text=True, timeout=10
                )
                for line in result.stdout.split("\n"):
                    parts = line.split("\t")
                    if len(parts) >= 2:
                        try:
                            lines_added += int(parts[0]) if parts[0] != "-" else 0
                            lines_deleted += int(parts[1]) if parts[1] != "-" else 0
                        except ValueError:
                            pass
            except (subprocess.TimeoutExpired, FileNotFoundError):
                pass

        # Count blog posts published
        blog_posts = 0
        blog_path = WWW_PATH / "src" / "content" / "blog"
        if blog_path.exists():
            for post in blog_path.glob("*.md"):
                content = post.read_text()
                # Parse pubDate from frontmatter
                match = re.search(r"pubDate:\s*(\d{4}-\d{2}-\d{2})", content)
                if match:
                    pub_date = match.group(1)
                    if pub_date in dates:
                        blog_posts += 1

        # Count new lines in memory files
        new_learnings = self._count_new_lines(MIND_PATH / "memory" / "learnings.md", dates)
        new_decisions = self._count_new_lines(MIND_PATH / "memory" / "decisions.md", dates)

        return {
            "git_commits": git_commits,
            "lines_added": lines_added,
            "lines_deleted": lines_deleted,
            "lines_changed": lines_added + lines_deleted,
            "repos_touched": len(repos_touched),
            "repo_names": list(repos_touched),
            "blog_posts": blog_posts,
            "new_learnings": new_learnings,
            "new_decisions": new_decisions
        }

    def _count_new_lines(self, filepath: Path, dates: list[str]) -> int:
        """Count lines added to a file during the period based on date headers."""
        if not filepath.exists():
            return 0

        content = filepath.read_text()
        count = 0
        current_date = None

        for line in content.split("\n"):
            # Check for date headers like "## 2026-01-02"
            match = re.match(r"^##\s+(\d{4}-\d{2}-\d{2})", line)
            if match:
                current_date = match.group(1)
            elif current_date in dates and line.strip():
                count += 1

        return count

    # =========================================================================
    # REFLECTIVE METRICS
    # =========================================================================

    def _aggregate_reflective(self) -> dict:
        """Aggregate reflective metrics: reflections, questions, observations."""
        dates = self._dates_in_range()

        # Count reflections
        reflections_written = 0
        for date in dates:
            reflection_file = REFLECTIONS_PATH / f"{date}.md"
            if reflection_file.exists():
                reflections_written += 1

        # Count dream cycles from log
        dream_cycles = 0
        dream_log = LOGS_PATH / "dream.log"
        if dream_log.exists():
            log_content = dream_log.read_text()
            for line in log_content.split("\n"):
                if "Dream cycle starting" in line:
                    match = re.match(r"\[(\d{4}-\d{2}-\d{2})", line)
                    if match and match.group(1) in dates:
                        dream_cycles += 1

        # Count questions and observations
        new_questions = self._count_new_lines(MIND_PATH / "memory" / "questions.md", dates)
        new_observations = self._count_new_lines(MIND_PATH / "memory" / "observations.md", dates)

        # Get drift signals from drift-report.json
        drift_signals = []
        drift_file = STATE_PATH / "drift-report.json"
        if drift_file.exists():
            try:
                drift = json.loads(drift_file.read_text())
                signals = drift.get("drift_signals", [])
                drift_signals = signals[:3] if signals else []
            except (json.JSONDecodeError, KeyError):
                pass

        return {
            "reflections_written": reflections_written,
            "dream_cycles": dream_cycles,
            "questions_added": new_questions,
            "observations_added": new_observations,
            "drift_signals": drift_signals
        }

    # =========================================================================
    # HIGHLIGHTS
    # =========================================================================

    def _extract_highlights(self) -> list[str]:
        """Extract notable highlights from the period."""
        highlights = []
        dates = self._dates_in_range()

        # Check for blog posts published
        blog_path = WWW_PATH / "src" / "content" / "blog"
        if blog_path.exists():
            for post in blog_path.glob("*.md"):
                content = post.read_text()
                match = re.search(r"pubDate:\s*(\d{4}-\d{2}-\d{2})", content)
                title_match = re.search(r"title:\s*[\"']?(.+?)[\"']?\s*$", content, re.MULTILINE)
                if match and match.group(1) in dates and title_match:
                    highlights.append(f"Published: {title_match.group(1)}")

        # Check git for significant commits
        for repo in [MIND_PATH, DEVELOPER_PATH / "samara-main", WWW_PATH]:
            if not (repo / ".git").exists():
                continue
            try:
                start_str = self.start_date.strftime("%Y-%m-%d")
                end_str = (self.end_date + timedelta(days=1)).strftime("%Y-%m-%d")
                result = subprocess.run(
                    ["git", "-C", str(repo), "log",
                     f"--since={start_str}", f"--until={end_str}",
                     "--oneline", "--grep=add", "--grep=implement", "--grep=fix",
                     "--all-match"],
                    capture_output=True, text=True, timeout=10
                )
                for line in result.stdout.strip().split("\n")[:2]:
                    if line.strip():
                        # Remove commit hash
                        msg = re.sub(r"^[a-f0-9]+\s+", "", line).strip()[:60]
                        if msg and msg not in highlights:
                            highlights.append(msg)
            except (subprocess.TimeoutExpired, FileNotFoundError):
                pass

        # Count significant metrics as highlights
        rel = self._aggregate_relational()
        if rel["total_messages"] > 200:
            highlights.append(f"Active week: {rel['total_messages']} messages exchanged")

        prod = self._aggregate_productive()
        if prod["git_commits"] > 20:
            highlights.append(f"Productive week: {prod['git_commits']} commits across {prod['repos_touched']} repos")

        # Limit to 5 highlights
        return highlights[:5]

    def save(self) -> Path:
        """Aggregate and save results to file."""
        data = self.aggregate()

        # Determine output path
        output_dir = ROUNDUPS_PATH / self.period_type
        output_dir.mkdir(parents=True, exist_ok=True)
        output_file = output_dir / f"{self.period}.json"

        output_file.write_text(json.dumps(data, indent=2))
        print(f"Saved roundup to: {output_file}")

        # Also save markdown summary
        md_file = output_dir / f"{self.period}.md"
        md_file.write_text(self._to_markdown(data))
        print(f"Saved summary to: {md_file}")

        return output_file

    def _to_markdown(self, data: dict) -> str:
        """Convert aggregated data to markdown summary."""
        rel = data["relational"]
        prod = data["productive"]
        refl = data["reflective"]

        md = f"""# {self.period_type.title()} Roundup: {self.period}

*Generated: {data['generated_at'][:10]}*
*Period: {data['date_range']['start']} to {data['date_range']['end']}*

---

## Relational

| Metric | Value |
|--------|-------|
| Messages sent | {rel['messages_sent']} |
| Messages received | {rel['messages_received']} |
| Conversations | {rel['conversations']} |
| Sessions | {rel['sessions']} |
| Avg messages/day | {rel['avg_messages_per_day']} |

**Top Themes:** {', '.join(rel['top_themes']) if rel['top_themes'] else 'N/A'}

---

## Productive

| Metric | Value |
|--------|-------|
| Git commits | {prod['git_commits']} |
| Lines changed | {prod['lines_changed']} |
| Repos touched | {prod['repos_touched']} |
| Blog posts | {prod['blog_posts']} |
| New learnings | {prod['new_learnings']} |
| New decisions | {prod['new_decisions']} |

---

## Reflective

| Metric | Value |
|--------|-------|
| Reflections | {refl['reflections_written']} |
| Dream cycles | {refl['dream_cycles']} |
| Questions added | {refl['questions_added']} |
| Observations added | {refl['observations_added']} |

**Drift signals:** {', '.join(refl['drift_signals']) if refl['drift_signals'] else 'None detected'}

---

## Highlights

"""
        if data.get("highlights"):
            for h in data["highlights"]:
                md += f"- {h}\n"
        else:
            md += "*No specific highlights captured this period.*\n"

        return md


def main():
    """CLI entry point."""
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    period_type = sys.argv[1]
    if period_type not in ("weekly", "monthly", "yearly"):
        print(f"Invalid period type: {period_type}")
        print("Use: weekly, monthly, or yearly")
        sys.exit(1)

    period = sys.argv[2] if len(sys.argv) > 2 else None

    aggregator = RoundupAggregator(period_type, period)
    aggregator.save()


if __name__ == "__main__":
    main()
