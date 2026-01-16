#!/usr/bin/env python3
"""
Archive Index CLI - Command-line interface for transcript archive

This is the Python implementation called by the archive-index bash wrapper.
"""

import sys
import json
import argparse
from pathlib import Path

# Import from the same directory
from chroma_helper import TranscriptIndex


def cmd_rebuild(args):
    """Rebuild the entire transcript index."""
    print(f"Rebuilding transcript archive (last {args.days} days)...")

    index = TranscriptIndex()
    stats = index.rebuild(days=args.days, project=args.project)

    if "error" in stats:
        print(f"Error: {stats['error']}", file=sys.stderr)
        sys.exit(1)

    print("\nRebuild complete!")
    print(json.dumps(stats, indent=2))


def cmd_sync_recent(args):
    """Incrementally sync recent sessions."""
    print(f"Syncing recent sessions (last {args.days} days)...")

    index = TranscriptIndex()
    stats = index.sync_recent(days=args.days, project=args.project)

    if "error" in stats:
        print(f"Error: {stats['error']}", file=sys.stderr)
        sys.exit(1)

    if stats["sessions_indexed"] == 0:
        print("No new sessions to index.")
    else:
        print(f"\nIndexed {stats['sessions_indexed']} new sessions:")
        print(json.dumps(stats, indent=2))


def cmd_search(args):
    """Search the transcript archive."""
    index = TranscriptIndex()
    results = index.search(args.query, n_results=args.n, role_filter=args.role)

    if not results:
        print(f"No results found for: {args.query}")
        return

    print(f"Found {len(results)} results:\n")

    for i, result in enumerate(results):
        distance = result.get('distance', 0)
        metadata = result.get('metadata', {})
        role = metadata.get('role', 'unknown')
        session_id = metadata.get('session_id', 'unknown')
        timestamp = metadata.get('timestamp', 'unknown')[:19]  # Trim timezone

        print(f"{'='*80}")
        print(f"Result {i+1} | Distance: {distance:.3f} | Role: {role}")
        print(f"Session: {session_id} | Time: {timestamp}")
        print(f"{'-'*80}")

        # Show preview
        text = result.get('text', '')
        preview_length = 500
        print(text[:preview_length])
        if len(text) > preview_length:
            print(f"\n[...{len(text) - preview_length} more characters]")
        print()


def cmd_stats(args):
    """Show index statistics."""
    index = TranscriptIndex()
    stats = index.get_stats()

    print("Transcript Archive Statistics:")
    print(json.dumps(stats, indent=2))


def cmd_sample(args):
    """Show sample content from the index."""
    index = TranscriptIndex()
    samples = index.sample_content(session_id=args.session_id, n=args.n)

    if not samples:
        print("No samples found.")
        return

    print(f"Sample content ({len(samples)} chunks):\n")

    for i, sample in enumerate(samples):
        if "error" in sample:
            print(f"Error: {sample['error']}", file=sys.stderr)
            continue

        print(f"{'='*80}")
        print(f"Sample {i+1}")
        print(f"Role: {sample.get('role')} | Session: {sample.get('session_id')}")
        print(f"Time: {sample.get('timestamp', 'unknown')[:19]}")
        print(f"{'-'*80}")
        print(sample.get('text', ''))
        print()


def main():
    parser = argparse.ArgumentParser(
        description="Manage the Claude Code transcript archive index",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    subparsers = parser.add_subparsers(dest='command', help='Command to execute')

    # rebuild command
    rebuild_parser = subparsers.add_parser('rebuild', help='Full rebuild of index')
    rebuild_parser.add_argument('--days', type=int, default=90,
                                help='Index sessions from last N days (default: 90)')
    rebuild_parser.add_argument('--project', type=str, default='samara-main',
                                help='Project to index (default: samara-main)')

    # sync-recent command
    sync_parser = subparsers.add_parser('sync-recent', help='Incremental sync of recent sessions')
    sync_parser.add_argument('--days', type=int, default=7,
                             help='Sync sessions from last N days (default: 7)')
    sync_parser.add_argument('--project', type=str, default='samara-main',
                             help='Project to index (default: samara-main)')

    # search command
    search_parser = subparsers.add_parser('search', help='Search transcript archive')
    search_parser.add_argument('query', type=str, help='Search query')
    search_parser.add_argument('--n', type=int, default=5,
                               help='Number of results (default: 5)')
    search_parser.add_argument('--role', type=str, choices=['thinking', 'user', 'assistant'],
                               help='Filter by role')

    # stats command
    stats_parser = subparsers.add_parser('stats', help='Show index statistics')

    # sample command
    sample_parser = subparsers.add_parser('sample', help='Show sample content')
    sample_parser.add_argument('--session-id', type=str,
                               help='Session ID to sample from')
    sample_parser.add_argument('--n', type=int, default=3,
                               help='Number of samples (default: 3)')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    try:
        if args.command == 'rebuild':
            cmd_rebuild(args)
        elif args.command == 'sync-recent':
            cmd_sync_recent(args)
        elif args.command == 'search':
            cmd_search(args)
        elif args.command == 'stats':
            cmd_stats(args)
        elif args.command == 'sample':
            cmd_sample(args)
        else:
            parser.print_help()
            sys.exit(1)
    except KeyboardInterrupt:
        print("\nInterrupted by user", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
