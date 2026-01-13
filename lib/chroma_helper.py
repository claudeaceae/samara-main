#!/usr/bin/env python3
"""
Chroma helper for Claude's temporal awareness system.

This module provides semantic search over Claude's memory files.
Chroma is a DERIVED index - markdown files remain source of truth.

Usage:
    from chroma_helper import MemoryIndex

    index = MemoryIndex()
    index.rebuild()  # Full rebuild from markdown
    results = index.search("coffee shops")  # Semantic search
"""

import os
import re
import json
import uuid
from datetime import datetime
from pathlib import Path
from mind_paths import get_mind_path
from typing import Optional

import chromadb
from chromadb.config import Settings

MIND_PATH = get_mind_path()
CHROMA_PATH = MIND_PATH / "chroma"
COLLECTION_NAME = "memories"


class MemoryIndex:
    """Semantic index over Claude's memory files."""

    def __init__(self):
        self.client = chromadb.PersistentClient(
            path=str(CHROMA_PATH),
            settings=Settings(anonymized_telemetry=False)
        )
        self.collection = self.client.get_or_create_collection(
            name=COLLECTION_NAME,
            metadata={"description": "Claude's memory index"}
        )

    def rebuild(self) -> dict:
        """
        Full rebuild of the index from markdown files.

        Returns dict with stats about what was indexed.
        """
        # Clear existing collection
        self.client.delete_collection(COLLECTION_NAME)
        self.collection = self.client.create_collection(
            name=COLLECTION_NAME,
            metadata={"description": "Claude's memory index"}
        )

        stats = {
            "episodes": 0,
            "reflections": 0,
            "learnings": 0,
            "observations": 0,
            "decisions": 0,
            "people": 0,
            "total": 0
        }

        # Index episodes
        episodes_dir = MIND_PATH / "memory" / "episodes"
        if episodes_dir.exists():
            for episode_file in episodes_dir.glob("*.md"):
                date = episode_file.stem  # e.g., "2025-12-22"
                docs = self._parse_episode(episode_file, date)
                self._add_documents(docs)
                stats["episodes"] += len(docs)

        # Index reflections
        reflections_dir = MIND_PATH / "memory" / "reflections"
        if reflections_dir.exists():
            for reflection_file in reflections_dir.glob("*.md"):
                if reflection_file.stem.startswith("weekly-"):
                    continue  # Skip weekly syntheses for now
                date = reflection_file.stem
                docs = self._parse_reflection(reflection_file, date)
                self._add_documents(docs)
                stats["reflections"] += len(docs)

        # Index learnings
        learnings_file = MIND_PATH / "memory" / "learnings.md"
        if learnings_file.exists():
            docs = self._parse_dated_sections(learnings_file, "learning")
            self._add_documents(docs)
            stats["learnings"] += len(docs)

        # Index observations
        observations_file = MIND_PATH / "memory" / "observations.md"
        if observations_file.exists():
            docs = self._parse_dated_sections(observations_file, "observation")
            self._add_documents(docs)
            stats["observations"] += len(docs)

        # Index decisions
        decisions_file = MIND_PATH / "memory" / "decisions.md"
        if decisions_file.exists():
            docs = self._parse_decisions(decisions_file)
            self._add_documents(docs)
            stats["decisions"] += len(docs)

        # Index person profiles
        people_dir = MIND_PATH / "memory" / "people"
        if people_dir.exists():
            for person_dir in people_dir.iterdir():
                if person_dir.is_dir():
                    profile_file = person_dir / "profile.md"
                    if profile_file.exists():
                        person_name = person_dir.name
                        docs = self._parse_person_profile(profile_file, person_name)
                        self._add_documents(docs)
                        stats["people"] += len(docs)

        stats["total"] = sum(v for v in stats.values() if isinstance(v, int))
        return stats

    def sync(self) -> dict:
        """
        Incremental sync - only update changed files.

        Uses file modification times to detect changes.
        Returns dict with stats about what was synced.
        """
        # For now, just do a full rebuild
        # TODO: Implement incremental sync based on mtime
        return self.rebuild()

    def index_single_file(self, filepath: Path) -> dict:
        """
        Re-index a single file without full rebuild.

        Useful for updating the index after profile updates from meeting debriefs.
        Automatically detects file type based on path.

        Args:
            filepath: Path to the file to index

        Returns:
            Dict with {success, documents_added, file_type}
        """
        filepath = Path(filepath)
        if not filepath.exists():
            return {"success": False, "error": "File not found", "documents_added": 0}

        # Determine file type based on path
        path_str = str(filepath)
        docs = []
        file_type = "unknown"

        if "/memory/people/" in path_str and filepath.name == "profile.md":
            # Person profile
            person_name = filepath.parent.name
            docs = self._parse_person_profile(filepath, person_name)
            file_type = "person_profile"
        elif "/memory/episodes/" in path_str:
            # Episode file
            date = filepath.stem
            docs = self._parse_episode(filepath, date)
            file_type = "episode"
        elif "/memory/reflections/" in path_str:
            # Reflection file
            date = filepath.stem
            docs = self._parse_reflection(filepath, date)
            file_type = "reflection"
        elif filepath.name == "learnings.md":
            docs = self._parse_dated_sections(filepath, "learning")
            file_type = "learnings"
        elif filepath.name == "observations.md":
            docs = self._parse_dated_sections(filepath, "observation")
            file_type = "observations"
        elif filepath.name == "decisions.md":
            docs = self._parse_decisions(filepath)
            file_type = "decisions"
        else:
            return {"success": False, "error": f"Unknown file type: {filepath.name}", "documents_added": 0}

        # Delete existing documents for this file
        self._delete_documents_for_file(filepath, file_type)

        # Add new documents
        if docs:
            self._add_documents(docs)

        return {
            "success": True,
            "file_type": file_type,
            "documents_added": len(docs),
            "filepath": str(filepath)
        }

    def _delete_documents_for_file(self, filepath: Path, file_type: str):
        """Delete existing documents for a file before re-indexing."""
        # Build a where filter based on file type
        where = {}

        if file_type == "person_profile":
            person_name = filepath.parent.name
            where = {"$and": [{"source": "person"}, {"person": person_name}]}
        elif file_type == "episode":
            date = filepath.stem
            where = {"$and": [{"source": "episode"}, {"date": date}]}
        elif file_type == "reflection":
            date = filepath.stem
            where = {"$and": [{"source": "reflection"}, {"date": date}]}
        else:
            # For learnings/observations/decisions, just use source type
            source_map = {
                "learnings": "learning",
                "observations": "observation",
                "decisions": "decision"
            }
            if file_type in source_map:
                where = {"source": source_map[file_type]}

        if where:
            try:
                # Get IDs to delete
                results = self.collection.get(where=where, include=[])
                if results["ids"]:
                    self.collection.delete(ids=results["ids"])
            except Exception:
                # If delete fails, continue anyway - duplicates will just add noise
                pass

    def search(self, query: str, n_results: int = 5,
               source_filter: Optional[str] = None,
               date_filter: Optional[str] = None) -> list:
        """
        Semantic search over memories.

        Args:
            query: Search text
            n_results: Max results to return
            source_filter: Filter by source type (episode, reflection, learning, etc.)
            date_filter: Filter by date (YYYY-MM-DD)

        Returns:
            List of dicts with {text, metadata, distance}
        """
        where = {}
        if source_filter:
            where["source"] = source_filter
        if date_filter:
            where["date"] = date_filter

        results = self.collection.query(
            query_texts=[query],
            n_results=n_results,
            where=where if where else None,
            include=["documents", "metadatas", "distances"]
        )

        # Flatten results
        output = []
        if results["documents"] and results["documents"][0]:
            for i, doc in enumerate(results["documents"][0]):
                output.append({
                    "text": doc,
                    "metadata": results["metadatas"][0][i] if results["metadatas"] else {},
                    "distance": results["distances"][0][i] if results["distances"] else None
                })

        return output

    def get_stats(self) -> dict:
        """Get current index stats."""
        return {
            "total_documents": self.collection.count(),
            "collection_name": COLLECTION_NAME,
            "chroma_path": str(CHROMA_PATH)
        }

    def _add_documents(self, docs: list):
        """Add documents to the collection."""
        if not docs:
            return

        self.collection.add(
            ids=[d["id"] for d in docs],
            documents=[d["text"] for d in docs],
            metadatas=[d["metadata"] for d in docs]
        )

    def _parse_episode(self, filepath: Path, date: str) -> list:
        """Parse an episode file into indexable documents."""
        content = filepath.read_text()
        docs = []

        # Split by timestamp headers (## HH:MM)
        sections = re.split(r'^## (\d{2}:\d{2})', content, flags=re.MULTILINE)

        # First element is header, then alternating time/content
        section_count = {}  # Track count per time to handle duplicates
        for i in range(1, len(sections), 2):
            if i + 1 < len(sections):
                time = sections[i]
                text = sections[i + 1].strip()

                if len(text) < 50:  # Skip very short sections
                    continue

                # Extract source tag if present
                source_match = re.search(r'\[(iMessage|Email|Autonomous|Direct)\]', text[:200])
                source_tag = source_match.group(1) if source_match else "unknown"

                # Handle multiple sections with same time by incrementing counter
                key = f"{date}-{time}"
                section_count[key] = section_count.get(key, 0) + 1

                # Use content hash for unique ID
                doc_id = self._make_id(f"episode-{date}-{time}-{section_count[key]}-{text[:50]}")
                docs.append({
                    "id": doc_id,
                    "text": text[:2000],  # Limit text size
                    "metadata": {
                        "source": "episode",
                        "date": date,
                        "time": time,
                        "channel": source_tag.lower()
                    }
                })

        return docs

    def _parse_reflection(self, filepath: Path, date: str) -> list:
        """Parse a reflection file into a single document."""
        content = filepath.read_text()

        # Remove the header line
        content = re.sub(r'^# Reflection:.*\n', '', content)

        if len(content.strip()) < 50:
            return []

        doc_id = self._make_id(f"reflection-{date}")
        return [{
            "id": doc_id,
            "text": content.strip()[:3000],
            "metadata": {
                "source": "reflection",
                "date": date
            }
        }]

    def _parse_dated_sections(self, filepath: Path, source_type: str) -> list:
        """Parse a file with dated sections (learnings, observations)."""
        content = filepath.read_text()
        docs = []

        # Split by date headers (## YYYY-MM-DD or ## 2025-12-22) or ## Date (Source)
        sections = re.split(r'^## (\d{4}-\d{2}-\d{2}[^\n]*)', content, flags=re.MULTILINE)

        for i in range(1, len(sections), 2):
            if i + 1 < len(sections):
                date_header = sections[i]
                text = sections[i + 1].strip()

                if len(text) < 20:
                    continue

                # Extract just the date
                date_match = re.match(r'(\d{4}-\d{2}-\d{2})', date_header)
                date = date_match.group(1) if date_match else "unknown"

                # Use full content for unique ID
                doc_id = self._make_id(f"{source_type}-{date}-{i}-{text}")
                docs.append({
                    "id": doc_id,
                    "text": text[:2000],
                    "metadata": {
                        "source": source_type,
                        "date": date
                    }
                })

        return docs

    def _parse_person_profile(self, filepath: Path, person_name: str) -> list:
        """Parse a person profile into indexable documents."""
        content = filepath.read_text()
        docs = []

        # Split by dated section headers (## YYYY-MM-DD)
        sections = re.split(r'^## (\d{4}-\d{2}-\d{2}[^\n]*)', content, flags=re.MULTILINE)

        # First section is the header/intro - index as overview
        if sections[0].strip():
            intro_text = sections[0].strip()
            if len(intro_text) > 50:
                doc_id = self._make_id(f"person-{person_name}-overview-{intro_text[:100]}")
                docs.append({
                    "id": doc_id,
                    "text": intro_text[:2000],
                    "metadata": {
                        "source": "person",
                        "person": person_name,
                        "section": "overview"
                    }
                })

        # Index each dated section separately for granular search
        for i in range(1, len(sections), 2):
            if i + 1 < len(sections):
                date_header = sections[i]
                text = sections[i + 1].strip()

                if len(text) < 20:
                    continue

                # Extract just the date
                date_match = re.match(r'(\d{4}-\d{2}-\d{2})', date_header)
                date = date_match.group(1) if date_match else "unknown"

                # Extract context if present (e.g., "From Weekly Sync")
                context_match = re.search(r'From (.+)', date_header)
                context = context_match.group(1).strip() if context_match else None

                doc_id = self._make_id(f"person-{person_name}-{date}-{i}-{text[:50]}")
                metadata = {
                    "source": "person",
                    "person": person_name,
                    "date": date,
                    "section": "observation"
                }
                if context:
                    metadata["context"] = context

                docs.append({
                    "id": doc_id,
                    "text": f"About {person_name}: {text}"[:2000],
                    "metadata": metadata
                })

        return docs

    def _parse_decisions(self, filepath: Path) -> list:
        """Parse the decisions file into documents."""
        content = filepath.read_text()
        docs = []

        # Split by decision headers (## YYYY-MM-DD: Title or ## Title)
        sections = re.split(r'^## (\d{4}-\d{2}-\d{2}:?.+|[A-Z].+)', content, flags=re.MULTILINE)

        decision_count = 0
        for i in range(1, len(sections), 2):
            if i + 1 < len(sections):
                title = sections[i].strip()
                text = sections[i + 1].strip()

                if len(text) < 50:
                    continue

                decision_count += 1

                # Extract date from title if present
                date_match = re.match(r'(\d{4}-\d{2}-\d{2})', title)
                date = date_match.group(1) if date_match else "unknown"

                # Use content for unique ID
                doc_id = self._make_id(f"decision-{decision_count}-{title[:30]}-{text[:30]}")
                docs.append({
                    "id": doc_id,
                    "text": f"## {title}\n{text}"[:2000],
                    "metadata": {
                        "source": "decision",
                        "date": date,
                        "title": title[:100]
                    }
                })

        return docs

    def _make_id(self, text: str) -> str:
        """Generate a unique ID. Uses UUID for uniqueness."""
        # Use uuid5 with a namespace for stability across rebuilds
        namespace = uuid.UUID('6ba7b810-9dad-11d1-80b4-00c04fd430c8')  # URL namespace
        return str(uuid.uuid5(namespace, text))


def main():
    """CLI interface for chroma_helper."""
    import sys

    if len(sys.argv) < 2:
        print("Usage: chroma_helper.py <command> [args]")
        print("Commands:")
        print("  rebuild            - Full rebuild of index")
        print("  sync               - Incremental sync")
        print("  query <text> [n]   - Search for text")
        print("  stats              - Show index stats")
        print("  index-file <path>  - Re-index a single file")
        sys.exit(1)

    command = sys.argv[1]
    index = MemoryIndex()

    if command == "rebuild":
        print("Rebuilding index...")
        stats = index.rebuild()
        print(f"Indexed: {json.dumps(stats, indent=2)}")

    elif command == "sync":
        print("Syncing index...")
        stats = index.sync()
        print(f"Synced: {json.dumps(stats, indent=2)}")

    elif command == "query":
        if len(sys.argv) < 3:
            print("Usage: chroma_helper.py query <text> [n_results]")
            sys.exit(1)
        query = sys.argv[2]
        n = int(sys.argv[3]) if len(sys.argv) > 3 else 5
        results = index.search(query, n_results=n)
        for i, r in enumerate(results):
            print(f"\n--- Result {i+1} (distance: {r['distance']:.3f}) ---")
            print(f"Source: {r['metadata'].get('source')} | Date: {r['metadata'].get('date')}")
            print(r['text'][:500] + "..." if len(r['text']) > 500 else r['text'])

    elif command == "stats":
        stats = index.get_stats()
        print(json.dumps(stats, indent=2))

    elif command == "index-file":
        if len(sys.argv) < 3:
            print("Usage: chroma_helper.py index-file <path>")
            sys.exit(1)
        filepath = Path(sys.argv[2])
        print(f"Indexing {filepath}...")
        result = index.index_single_file(filepath)
        print(json.dumps(result, indent=2))
        if not result.get("success"):
            sys.exit(1)

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
