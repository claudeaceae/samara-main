#!/usr/bin/env python3
"""
Transcript Indexer - Selective JSONL parser for Claude Code session archives

Extracts high-value content from raw session transcripts for semantic search:
- Thinking blocks (full reasoning traces)
- User messages (original intent)
- Assistant text (first 1000 chars per message)

Filters out noise:
- Tool use inputs (too verbose)
- Tool results (extreme noise - file contents, command output)
- System messages (no semantic value)
- Progress events (internal metadata)
"""

import json
import sys
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime


class Chunk:
    """Represents an indexable chunk of content from a session"""

    def __init__(self, text: str, role: str, timestamp: str, session_id: str,
                 chunk_type: str, uuid: str):
        self.text = text
        self.role = role  # 'thinking', 'user', 'assistant'
        self.timestamp = timestamp
        self.session_id = session_id
        self.chunk_type = chunk_type
        self.uuid = uuid

    def to_dict(self) -> Dict:
        return {
            'text': self.text,
            'role': self.role,
            'timestamp': self.timestamp,
            'session_id': self.session_id,
            'chunk_type': self.chunk_type,
            'uuid': self.uuid
        }


class TranscriptIndexer:
    """Parses Claude Code JSONL session transcripts and extracts indexable content"""

    # Maximum length for assistant text chunks (to avoid indexing entire files)
    MAX_ASSISTANT_TEXT_LENGTH = 1000

    @staticmethod
    def extract_indexable_content(jsonl_path: Path) -> List[Chunk]:
        """
        Parse a JSONL session file and extract high-value content.

        Args:
            jsonl_path: Path to .jsonl session transcript

        Returns:
            List of Chunk objects ready for indexing
        """
        chunks = []

        if not jsonl_path.exists():
            print(f"Warning: Session file not found: {jsonl_path}", file=sys.stderr)
            return chunks

        session_id = jsonl_path.stem

        try:
            with open(jsonl_path, 'r') as f:
                for line_num, line in enumerate(f, 1):
                    try:
                        entry = json.loads(line.strip())
                        extracted = TranscriptIndexer._extract_from_entry(
                            entry, session_id
                        )
                        chunks.extend(extracted)
                    except json.JSONDecodeError as e:
                        print(f"Warning: Invalid JSON at {jsonl_path}:{line_num}: {e}",
                              file=sys.stderr)
                        continue
                    except Exception as e:
                        print(f"Warning: Error processing {jsonl_path}:{line_num}: {e}",
                              file=sys.stderr)
                        continue
        except Exception as e:
            print(f"Error reading {jsonl_path}: {e}", file=sys.stderr)
            return []

        return chunks

    @staticmethod
    def _extract_from_entry(entry: Dict, session_id: str) -> List[Chunk]:
        """Extract indexable chunks from a single JSONL entry"""
        chunks = []

        entry_type = entry.get('type')
        timestamp = entry.get('timestamp', '')
        uuid = entry.get('uuid', '')

        # Skip non-message types
        if entry_type not in ['user', 'assistant']:
            return chunks

        message = entry.get('message', {})

        # Extract user messages
        if entry_type == 'user':
            content = message.get('content', '')
            if isinstance(content, str) and content.strip():
                chunks.append(Chunk(
                    text=content,
                    role='user',
                    timestamp=timestamp,
                    session_id=session_id,
                    chunk_type='user_message',
                    uuid=uuid
                ))

        # Extract assistant content
        elif entry_type == 'assistant':
            content_blocks = message.get('content', [])
            if not isinstance(content_blocks, list):
                return chunks

            for block in content_blocks:
                if not isinstance(block, dict):
                    continue

                block_type = block.get('type')

                # Extract thinking blocks (full content - highest value)
                if block_type == 'thinking':
                    thinking_text = block.get('thinking', '')
                    if thinking_text.strip():
                        chunks.append(Chunk(
                            text=thinking_text,
                            role='thinking',
                            timestamp=timestamp,
                            session_id=session_id,
                            chunk_type='thinking_block',
                            uuid=uuid
                        ))

                # Extract text blocks (truncated to avoid indexing file contents)
                elif block_type == 'text':
                    text_content = block.get('text', '')
                    if text_content.strip():
                        # Truncate long text (likely contains tool output)
                        truncated = text_content[:TranscriptIndexer.MAX_ASSISTANT_TEXT_LENGTH]
                        chunks.append(Chunk(
                            text=truncated,
                            role='assistant',
                            timestamp=timestamp,
                            session_id=session_id,
                            chunk_type='assistant_text',
                            uuid=uuid
                        ))

                # Skip tool_use (too verbose, low signal)
                # Skip tool_result (extreme noise - file contents, command output)

        return chunks

    @staticmethod
    def get_session_date(jsonl_path: Path) -> Optional[datetime]:
        """Extract the session date from the first entry's timestamp"""
        try:
            with open(jsonl_path, 'r') as f:
                first_line = f.readline()
                if first_line:
                    entry = json.loads(first_line.strip())
                    timestamp_str = entry.get('timestamp', '')
                    if timestamp_str:
                        # Parse ISO 8601 timestamp
                        return datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
        except Exception as e:
            print(f"Warning: Could not extract date from {jsonl_path}: {e}",
                  file=sys.stderr)

        return None

    @staticmethod
    def filter_by_date_range(
        sessions: List[Path],
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> List[Path]:
        """Filter session files by date range"""
        filtered = []

        for session_path in sessions:
            session_date = TranscriptIndexer.get_session_date(session_path)
            if session_date is None:
                continue

            # Make sure both datetimes are timezone-aware or both naive
            if start_date:
                # If start_date is naive, make session_date naive too
                if start_date.tzinfo is None and session_date.tzinfo is not None:
                    session_date = session_date.replace(tzinfo=None)
                # If start_date is aware, make session_date aware too
                elif start_date.tzinfo is not None and session_date.tzinfo is None:
                    from datetime import timezone
                    session_date = session_date.replace(tzinfo=timezone.utc)

                if session_date < start_date:
                    continue

            if end_date:
                # Same timezone handling for end_date
                session_date_for_end = TranscriptIndexer.get_session_date(session_path)
                if session_date_for_end is None:
                    continue

                if end_date.tzinfo is None and session_date_for_end.tzinfo is not None:
                    session_date_for_end = session_date_for_end.replace(tzinfo=None)
                elif end_date.tzinfo is not None and session_date_for_end.tzinfo is None:
                    from datetime import timezone
                    session_date_for_end = session_date_for_end.replace(tzinfo=timezone.utc)

                if session_date_for_end > end_date:
                    continue

            filtered.append(session_path)

        return filtered


def main():
    """CLI for testing the indexer"""
    import argparse

    parser = argparse.ArgumentParser(description='Extract indexable content from session transcripts')
    parser.add_argument('session_file', type=Path, help='Path to .jsonl session file')
    parser.add_argument('--stats', action='store_true', help='Show statistics instead of content')

    args = parser.parse_args()

    chunks = TranscriptIndexer.extract_indexable_content(args.session_file)

    if args.stats:
        thinking_count = sum(1 for c in chunks if c.role == 'thinking')
        user_count = sum(1 for c in chunks if c.role == 'user')
        assistant_count = sum(1 for c in chunks if c.role == 'assistant')
        total_chars = sum(len(c.text) for c in chunks)

        print(f"Session: {args.session_file.stem}")
        print(f"Total chunks: {len(chunks)}")
        print(f"  Thinking blocks: {thinking_count}")
        print(f"  User messages: {user_count}")
        print(f"  Assistant text: {assistant_count}")
        print(f"Total characters: {total_chars:,}")
    else:
        for chunk in chunks:
            print(f"\n{'='*80}")
            print(f"Role: {chunk.role} | Type: {chunk.chunk_type}")
            print(f"Time: {chunk.timestamp}")
            print(f"UUID: {chunk.uuid}")
            print(f"{'-'*80}")
            print(chunk.text[:500])  # Preview first 500 chars
            if len(chunk.text) > 500:
                print(f"\n[...{len(chunk.text) - 500} more characters]")


if __name__ == '__main__':
    main()
