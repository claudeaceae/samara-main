#!/usr/bin/env python3
"""
Thread Manager for Claude's Knowledge Threads system.

Knowledge Threads are persistent topics that accumulate items over time,
enabling sustained knowledge accumulation with cross-referencing and synthesis.

Usage:
    from thread_manager import ThreadManager

    tm = ThreadManager()
    thread_id = tm.create_thread("Walkable Cities")
    tm.add_item(thread_id, "url", {"url": "...", "title": "..."})
    connections = tm.find_connections("urban design patterns")
    tm.synthesize(thread_id)
"""

import os
import json
import uuid
import re
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, List, Dict, Any, Tuple
from dataclasses import dataclass, asdict, field

from mind_paths import get_mind_path

MIND_PATH = get_mind_path()
THREADS_PATH = MIND_PATH / "memory" / "threads"
INDEX_PATH = THREADS_PATH / "index.json"
ARCHIVE_PATH = THREADS_PATH / "archive"


@dataclass
class ThreadItem:
    """A single item in a knowledge thread."""
    id: str
    timestamp: str
    source: str  # share | browser | conversation | observation | connection
    type: str    # url | text | observation | connection | insight
    content: Dict[str, Any]
    connections: List[str] = field(default_factory=list)  # Item or episode IDs
    chewed: bool = False

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> 'ThreadItem':
        return cls(
            id=data['id'],
            timestamp=data['timestamp'],
            source=data['source'],
            type=data['type'],
            content=data['content'],
            connections=data.get('connections', []),
            chewed=data.get('chewed', False)
        )


@dataclass
class ThreadManifest:
    """Metadata for a knowledge thread."""
    id: str
    title: str
    status: str  # active | dormant | archived
    created: str
    updated: str
    item_count: int = 0
    last_synthesis: Optional[str] = None
    tags: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> 'ThreadManifest':
        return cls(
            id=data['id'],
            title=data['title'],
            status=data.get('status', 'active'),
            created=data['created'],
            updated=data['updated'],
            item_count=data.get('item_count', 0),
            last_synthesis=data.get('last_synthesis'),
            tags=data.get('tags', [])
        )


class ThreadManager:
    """Manages knowledge threads for sustained knowledge accumulation."""

    def __init__(self):
        self._ensure_structure()
        self._chroma = None  # Lazy load

    def _ensure_structure(self):
        """Ensure thread directories exist."""
        THREADS_PATH.mkdir(parents=True, exist_ok=True)
        ARCHIVE_PATH.mkdir(exist_ok=True)

        if not INDEX_PATH.exists():
            self._save_index({"threads": [], "created": self._now()})

    def _now(self) -> str:
        """Current UTC timestamp in ISO format."""
        return datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

    def _load_index(self) -> dict:
        """Load the threads index."""
        try:
            with open(INDEX_PATH) as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return {"threads": [], "created": self._now()}

    def _save_index(self, index: dict):
        """Save the threads index."""
        with open(INDEX_PATH, 'w') as f:
            json.dump(index, f, indent=2)

    def _thread_path(self, thread_id: str) -> Path:
        """Get path to a thread directory."""
        return THREADS_PATH / thread_id

    def _manifest_path(self, thread_id: str) -> Path:
        """Get path to a thread's manifest."""
        return self._thread_path(thread_id) / "manifest.json"

    def _items_path(self, thread_id: str) -> Path:
        """Get path to a thread's items file."""
        return self._thread_path(thread_id) / "items.jsonl"

    def _connections_path(self, thread_id: str) -> Path:
        """Get path to a thread's connections file."""
        return self._thread_path(thread_id) / "connections.jsonl"

    def _insights_path(self, thread_id: str) -> Path:
        """Get path to a thread's insights file."""
        return self._thread_path(thread_id) / "insights.md"

    # === Thread CRUD ===

    def create_thread(self, title: str, tags: List[str] = None) -> str:
        """
        Create a new knowledge thread.

        Args:
            title: Thread title (e.g., "Walkable Cities")
            tags: Optional list of tags

        Returns:
            Thread ID
        """
        thread_id = str(uuid.uuid4())[:8]
        now = self._now()

        manifest = ThreadManifest(
            id=thread_id,
            title=title,
            status='active',
            created=now,
            updated=now,
            item_count=0,
            tags=tags or []
        )

        # Create thread directory
        thread_path = self._thread_path(thread_id)
        thread_path.mkdir(exist_ok=True)

        # Save manifest
        with open(self._manifest_path(thread_id), 'w') as f:
            json.dump(manifest.to_dict(), f, indent=2)

        # Initialize empty files
        self._items_path(thread_id).touch()
        self._connections_path(thread_id).touch()

        # Update index
        index = self._load_index()
        index['threads'].append({
            'id': thread_id,
            'title': title,
            'status': 'active',
            'created': now
        })
        self._save_index(index)

        return thread_id

    def get_thread(self, thread_id: str) -> Optional[ThreadManifest]:
        """Get a thread's manifest by ID."""
        manifest_path = self._manifest_path(thread_id)
        if not manifest_path.exists():
            return None

        with open(manifest_path) as f:
            return ThreadManifest.from_dict(json.load(f))

    def list_threads(self, status: str = None, include_archived: bool = False) -> List[ThreadManifest]:
        """
        List all threads.

        Args:
            status: Filter by status ('active', 'dormant')
            include_archived: Include archived threads
        """
        index = self._load_index()
        threads = []

        for entry in index['threads']:
            if status and entry.get('status') != status:
                continue
            if not include_archived and entry.get('status') == 'archived':
                continue

            manifest = self.get_thread(entry['id'])
            if manifest:
                threads.append(manifest)

        return sorted(threads, key=lambda t: t.updated, reverse=True)

    def update_manifest(self, thread_id: str, **updates):
        """Update a thread's manifest fields."""
        manifest = self.get_thread(thread_id)
        if not manifest:
            raise ValueError(f"Thread not found: {thread_id}")

        for key, value in updates.items():
            if hasattr(manifest, key):
                setattr(manifest, key, value)

        manifest.updated = self._now()

        with open(self._manifest_path(thread_id), 'w') as f:
            json.dump(manifest.to_dict(), f, indent=2)

        # Update index status if changed
        if 'status' in updates:
            index = self._load_index()
            for entry in index['threads']:
                if entry['id'] == thread_id:
                    entry['status'] = updates['status']
                    break
            self._save_index(index)

    def archive_thread(self, thread_id: str, reason: str = None):
        """Move a thread to the archive."""
        thread_path = self._thread_path(thread_id)
        if not thread_path.exists():
            raise ValueError(f"Thread not found: {thread_id}")

        self.update_manifest(thread_id, status='archived')

        # Move to archive directory
        archive_dest = ARCHIVE_PATH / thread_id
        thread_path.rename(archive_dest)

    # === Item Management ===

    def add_item(self, thread_id: str, source: str, item_type: str,
                 content: Dict[str, Any], connections: List[str] = None) -> str:
        """
        Add an item to a thread.

        Args:
            thread_id: Thread to add to
            source: Where item came from (share, browser, conversation, etc.)
            item_type: Type of item (url, text, observation, connection)
            content: Item content (url, title, note, etc.)
            connections: Pre-identified connections

        Returns:
            Item ID
        """
        manifest = self.get_thread(thread_id)
        if not manifest:
            raise ValueError(f"Thread not found: {thread_id}")

        item = ThreadItem(
            id=str(uuid.uuid4())[:8],
            timestamp=self._now(),
            source=source,
            type=item_type,
            content=content,
            connections=connections or [],
            chewed=False
        )

        # Append to items file
        with open(self._items_path(thread_id), 'a') as f:
            f.write(json.dumps(item.to_dict()) + '\n')

        # Update manifest
        self.update_manifest(thread_id, item_count=manifest.item_count + 1)

        return item.id

    def get_items(self, thread_id: str, unchewed_only: bool = False) -> List[ThreadItem]:
        """Get all items in a thread."""
        items_path = self._items_path(thread_id)
        if not items_path.exists():
            return []

        items = []
        with open(items_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    item = ThreadItem.from_dict(json.loads(line))
                    if unchewed_only and item.chewed:
                        continue
                    items.append(item)
                except (json.JSONDecodeError, KeyError):
                    continue

        return items

    def mark_chewed(self, thread_id: str, item_ids: List[str] = None):
        """
        Mark items as chewed (processed during rumination).

        Args:
            thread_id: Thread ID
            item_ids: Specific items to mark, or None for all
        """
        items = self.get_items(thread_id)
        updated_items = []

        for item in items:
            if item_ids is None or item.id in item_ids:
                item.chewed = True
            updated_items.append(item)

        # Rewrite items file
        with open(self._items_path(thread_id), 'w') as f:
            for item in updated_items:
                f.write(json.dumps(item.to_dict()) + '\n')

    def add_connection(self, thread_id: str, from_id: str, to_id: str,
                       connection_type: str, description: str = None):
        """
        Record a connection between items or to external resources.

        Args:
            thread_id: Thread ID
            from_id: Source item ID
            to_id: Target item ID (or episode ID like "episode-2026-01-20")
            connection_type: Type of connection (semantic, temporal, causal, etc.)
            description: Optional description of the connection
        """
        connection = {
            'timestamp': self._now(),
            'from_id': from_id,
            'to_id': to_id,
            'type': connection_type,
            'description': description
        }

        with open(self._connections_path(thread_id), 'a') as f:
            f.write(json.dumps(connection) + '\n')

    def get_connections(self, thread_id: str) -> List[dict]:
        """Get all connections for a thread."""
        conn_path = self._connections_path(thread_id)
        if not conn_path.exists():
            return []

        connections = []
        with open(conn_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    connections.append(json.loads(line))
                except json.JSONDecodeError:
                    continue

        return connections

    # === Semantic Search & Matching ===

    def _get_chroma(self):
        """Lazy load Chroma index."""
        if self._chroma is None:
            try:
                from chroma_helper import MemoryIndex
                self._chroma = MemoryIndex()
            except ImportError:
                return None
        return self._chroma

    def find_matching_thread(self, text: str, threshold: float = 0.7) -> Optional[Tuple[str, float]]:
        """
        Find a thread that semantically matches the given text.

        Args:
            text: Text to match against thread titles and recent items
            threshold: Minimum similarity score (0-1, where 1 is identical)

        Returns:
            Tuple of (thread_id, similarity_score) or None
        """
        chroma = self._get_chroma()
        if not chroma:
            # Fallback to simple keyword matching
            return self._simple_thread_match(text)

        # Get all active threads
        threads = self.list_threads(status='active')
        if not threads:
            return None

        # Build a pseudo-document for each thread from title + recent items
        best_match = None
        best_score = 0.0

        for thread in threads:
            # Build thread representation
            items = self.get_items(thread.id)
            thread_text = thread.title

            # Add recent item titles/text
            for item in items[-5:]:  # Last 5 items
                if 'title' in item.content:
                    thread_text += " " + item.content['title']
                if 'text' in item.content:
                    thread_text += " " + item.content['text'][:200]

            # Simple cosine similarity via Chroma query
            # Query the thread text against the input text
            # This is a bit of a hack - we're using Chroma's embedding
            try:
                # Add temporary doc, query, remove
                temp_id = f"temp-{uuid.uuid4()}"
                chroma.collection.add(
                    ids=[temp_id],
                    documents=[thread_text],
                    metadatas=[{"source": "temp"}]
                )

                results = chroma.collection.query(
                    query_texts=[text],
                    n_results=1,
                    where={"source": "temp"}
                )

                chroma.collection.delete(ids=[temp_id])

                if results['distances'] and results['distances'][0]:
                    # Convert L2 distance to similarity (approximate)
                    distance = results['distances'][0][0]
                    similarity = max(0, 1 - (distance / 2))  # Rough conversion

                    if similarity > best_score:
                        best_score = similarity
                        best_match = thread.id

            except Exception:
                continue

        if best_match and best_score >= threshold:
            return (best_match, best_score)

        return None

    def _simple_thread_match(self, text: str) -> Optional[Tuple[str, float]]:
        """Simple keyword-based thread matching as fallback."""
        text_lower = text.lower()
        threads = self.list_threads(status='active')

        best_match = None
        best_score = 0.0

        for thread in threads:
            title_words = set(thread.title.lower().split())
            text_words = set(re.findall(r'\b\w+\b', text_lower))

            # Jaccard similarity
            if title_words and text_words:
                intersection = len(title_words & text_words)
                union = len(title_words | text_words)
                score = intersection / union if union > 0 else 0

                if score > best_score:
                    best_score = score
                    best_match = thread.id

        if best_match and best_score >= 0.3:  # Lower threshold for keyword matching
            return (best_match, best_score)

        return None

    def find_semantic_connections(self, text: str, n_results: int = 5) -> List[dict]:
        """
        Find semantically related content from Chroma.

        Args:
            text: Text to find connections for
            n_results: Max results to return

        Returns:
            List of related items with metadata
        """
        chroma = self._get_chroma()
        if not chroma:
            return []

        try:
            results = chroma.search(text, n_results=n_results)
            return results
        except Exception:
            return []

    # === Synthesis ===

    def get_synthesis_context(self, thread_id: str) -> dict:
        """
        Build context for synthesis generation.

        Returns dict with:
        - thread: ThreadManifest
        - items: All items
        - unchewed_items: Items not yet processed
        - connections: All recorded connections
        - related_memories: Semantically related content from Chroma
        """
        manifest = self.get_thread(thread_id)
        if not manifest:
            raise ValueError(f"Thread not found: {thread_id}")

        items = self.get_items(thread_id)
        unchewed = [i for i in items if not i.chewed]
        connections = self.get_connections(thread_id)

        # Find related memories
        # Build query from thread title + recent items
        query_text = manifest.title
        for item in items[-3:]:
            if 'title' in item.content:
                query_text += " " + item.content['title']

        related = self.find_semantic_connections(query_text, n_results=5)

        return {
            'thread': manifest,
            'items': items,
            'unchewed_items': unchewed,
            'connections': connections,
            'related_memories': related
        }

    def save_synthesis(self, thread_id: str, synthesis: str):
        """
        Save a synthesis artifact to the thread.

        Args:
            thread_id: Thread ID
            synthesis: Synthesis text (markdown)
        """
        insights_path = self._insights_path(thread_id)

        # Append with timestamp header
        header = f"\n\n## {datetime.utcnow().strftime('%Y-%m-%d')}\n\n"

        with open(insights_path, 'a') as f:
            f.write(header + synthesis)

        self.update_manifest(thread_id, last_synthesis=self._now())

    def get_synthesis(self, thread_id: str) -> Optional[str]:
        """Get the accumulated synthesis for a thread."""
        insights_path = self._insights_path(thread_id)
        if not insights_path.exists():
            return None

        return insights_path.read_text()

    # === Dormancy Detection ===

    def check_dormancy(self, days_threshold: int = 30) -> List[str]:
        """
        Find threads that should be marked dormant.

        Args:
            days_threshold: Days without new items before dormancy

        Returns:
            List of thread IDs marked dormant
        """
        cutoff = datetime.utcnow() - timedelta(days=days_threshold)
        cutoff_str = cutoff.strftime('%Y-%m-%dT%H:%M:%SZ')

        dormant = []
        for thread in self.list_threads(status='active'):
            if thread.updated < cutoff_str:
                self.update_manifest(thread.id, status='dormant')
                dormant.append(thread.id)

        return dormant

    # === Thread Statistics ===

    def get_threads_needing_synthesis(self, item_threshold: int = 10,
                                       days_threshold: int = 7) -> List[ThreadManifest]:
        """
        Find threads that should have synthesis generated.

        Triggers:
        - Thread has >= item_threshold items
        - Last synthesis was >= days_threshold days ago
        """
        now = datetime.utcnow()
        days_cutoff = (now - timedelta(days=days_threshold)).strftime('%Y-%m-%dT%H:%M:%SZ')

        candidates = []

        for thread in self.list_threads(status='active'):
            # Check item count
            if thread.item_count >= item_threshold:
                candidates.append(thread)
                continue

            # Check synthesis age
            if thread.last_synthesis and thread.last_synthesis < days_cutoff:
                candidates.append(thread)
                continue

            # No synthesis and thread is old enough
            if not thread.last_synthesis and thread.created < days_cutoff:
                candidates.append(thread)

        return candidates

    def get_threads_with_unchewed(self, limit: int = 3) -> List[Tuple[ThreadManifest, int]]:
        """
        Get threads with unchewed items, sorted by unchewed count.

        Args:
            limit: Max threads to return

        Returns:
            List of (manifest, unchewed_count) tuples
        """
        threads_with_counts = []

        for thread in self.list_threads(status='active'):
            unchewed = self.get_items(thread.id, unchewed_only=True)
            if unchewed:
                threads_with_counts.append((thread, len(unchewed)))

        # Sort by unchewed count descending
        threads_with_counts.sort(key=lambda x: x[1], reverse=True)

        return threads_with_counts[:limit]


# === Migration Helper ===

def migrate_research_queue():
    """
    Migrate pending research-queue items to knowledge threads.
    """
    queue_path = MIND_PATH / "state" / "research-queue" / "queue.jsonl"
    if not queue_path.exists():
        return {"migrated": 0, "threads_created": 0}

    tm = ThreadManager()
    migrated = 0
    threads_created = set()

    with open(queue_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            try:
                item = json.loads(line)
                if item.get('status') != 'pending':
                    continue

                # Create a thread for each item (could be smarter about grouping)
                title = item.get('title', 'Untitled Share')[:50]
                thread_id = tm.create_thread(title)
                threads_created.add(thread_id)

                # Add the item
                content = {
                    'url': item.get('url'),
                    'title': item.get('title'),
                    'notes': item.get('notes')
                }

                tm.add_item(
                    thread_id=thread_id,
                    source='share',
                    item_type='url' if item.get('url') else 'text',
                    content=content
                )

                migrated += 1

            except (json.JSONDecodeError, KeyError):
                continue

    return {
        "migrated": migrated,
        "threads_created": len(threads_created)
    }


def main():
    """CLI interface for thread_manager."""
    import sys

    if len(sys.argv) < 2:
        print("Usage: thread_manager.py <command> [args]")
        print("Commands:")
        print("  create <title>      - Create new thread")
        print("  list                - List all active threads")
        print("  view <thread_id>    - View thread details")
        print("  add <thread_id>     - Add item (reads from stdin)")
        print("  unchewed            - List threads with unchewed items")
        print("  synthesize          - List threads needing synthesis")
        print("  migrate             - Migrate research-queue items")
        sys.exit(1)

    command = sys.argv[1]
    tm = ThreadManager()

    if command == "create":
        if len(sys.argv) < 3:
            print("Usage: thread_manager.py create <title>")
            sys.exit(1)
        title = " ".join(sys.argv[2:])
        thread_id = tm.create_thread(title)
        print(f"Created thread: {thread_id}")
        print(f"Title: {title}")

    elif command == "list":
        threads = tm.list_threads()
        if not threads:
            print("No active threads.")
        else:
            for t in threads:
                print(f"[{t.id}] {t.title} ({t.item_count} items, {t.status})")

    elif command == "view":
        if len(sys.argv) < 3:
            print("Usage: thread_manager.py view <thread_id>")
            sys.exit(1)
        thread_id = sys.argv[2]
        manifest = tm.get_thread(thread_id)
        if not manifest:
            print(f"Thread not found: {thread_id}")
            sys.exit(1)

        print(f"Thread: {manifest.title}")
        print(f"ID: {manifest.id}")
        print(f"Status: {manifest.status}")
        print(f"Created: {manifest.created}")
        print(f"Updated: {manifest.updated}")
        print(f"Items: {manifest.item_count}")
        print(f"Tags: {', '.join(manifest.tags) if manifest.tags else 'none'}")
        print(f"Last synthesis: {manifest.last_synthesis or 'never'}")
        print("\nItems:")
        for item in tm.get_items(thread_id):
            chewed = "[x]" if item.chewed else "[ ]"
            content_preview = str(item.content)[:60]
            print(f"  {chewed} [{item.id}] ({item.type}) {content_preview}")

    elif command == "unchewed":
        threads = tm.get_threads_with_unchewed()
        if not threads:
            print("No threads with unchewed items.")
        else:
            for manifest, count in threads:
                print(f"[{manifest.id}] {manifest.title}: {count} unchewed")

    elif command == "synthesize":
        threads = tm.get_threads_needing_synthesis()
        if not threads:
            print("No threads need synthesis.")
        else:
            for t in threads:
                reason = f"{t.item_count} items" if t.item_count >= 10 else "time"
                print(f"[{t.id}] {t.title} (reason: {reason})")

    elif command == "migrate":
        result = migrate_research_queue()
        print(f"Migrated {result['migrated']} items to {result['threads_created']} threads")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
