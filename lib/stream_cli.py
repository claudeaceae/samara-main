#!/usr/bin/env python3
"""
Unified Event Stream CLI

Commands:
    stream write --surface cli --type interaction --direction inbound --summary "..."
    stream query [--hours 12] [--surface cli] [--include-distilled]
    stream mark-distilled <event_id> [<event_id>...]
    stream archive [--days 30]
    stream stats
    stream validate
    stream rebuild-distilled-index
    stream migrate-daily

Usage:
    ./stream_cli.py write --surface cli --type interaction --direction inbound --summary "User asked..."
    ./stream_cli.py query --hours 12 --format json
    ./stream_cli.py mark-distilled evt_123_abc evt_456_def
    ./stream_cli.py archive --days 30
    ./stream_cli.py rebuild-distilled-index
    ./stream_cli.py migrate-daily
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

# Add parent dir to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.stream_writer import (
    StreamWriter,
    Surface,
    EventType,
    Direction,
)
from lib.stream_validator import validate_stream_file

def sort_events(events: list[dict[str, object]]) -> list[dict[str, object]]:
    """Sort events by timestamp (ascending) with ID as a tie-breaker."""
    return sorted(
        events,
        key=lambda e: (e.get("timestamp", ""), e.get("id", "")),
    )


def cmd_write(args: argparse.Namespace) -> int:
    """Write an event to the stream."""
    try:
        surface = Surface(args.surface)
    except ValueError:
        print(f"Error: Invalid surface '{args.surface}'", file=sys.stderr)
        print(f"Valid surfaces: {[s.value for s in Surface]}", file=sys.stderr)
        return 1

    try:
        event_type = EventType(args.type)
    except ValueError:
        print(f"Error: Invalid type '{args.type}'", file=sys.stderr)
        print(f"Valid types: {[t.value for t in EventType]}", file=sys.stderr)
        return 1

    try:
        direction = Direction(args.direction)
    except ValueError:
        print(f"Error: Invalid direction '{args.direction}'", file=sys.stderr)
        print(f"Valid directions: {[d.value for d in Direction]}", file=sys.stderr)
        return 1

    # Parse metadata if provided
    metadata = {}
    if args.metadata:
        try:
            metadata = json.loads(args.metadata)
        except json.JSONDecodeError:
            print(f"Error: Invalid JSON for metadata: {args.metadata}", file=sys.stderr)
            return 1

    writer = StreamWriter()
    event = writer.create_event(
        surface=surface,
        event_type=event_type,
        direction=direction,
        summary=args.summary,
        session_id=args.session_id,
        content=args.content,
        metadata=metadata,
    )
    writer.write(event)

    if args.format == "json":
        print(json.dumps({"id": event.id, "timestamp": event.timestamp}))
    else:
        print(f"Event written: {event.id}")

    return 0


def cmd_query(args: argparse.Namespace) -> int:
    """Query events from the stream."""
    writer = StreamWriter()

    surface = None
    if args.surface:
        try:
            surface = Surface(args.surface)
        except ValueError:
            print(f"Error: Invalid surface '{args.surface}'", file=sys.stderr)
            return 1

    event_type = None
    if args.type:
        try:
            event_type = EventType(args.type)
        except ValueError:
            print(f"Error: Invalid type '{args.type}'", file=sys.stderr)
            return 1

    results = writer.query(
        hours=args.hours,
        surface=surface,
        include_distilled=args.include_distilled,
        event_type=event_type,
    )
    results = sort_events(results)

    if args.format == "json":
        print(json.dumps(results, indent=2))
    else:
        if not results:
            print("No events found")
            return 0

        for event in results:
            ts = event["timestamp"][:19].replace("T", " ")
            surface = event["surface"]
            summary = event["summary"][:80]
            distilled = " [distilled]" if event.get("distilled") else ""
            print(f"[{ts}] ({surface}) {summary}{distilled}")

    return 0


def cmd_mark_distilled(args: argparse.Namespace) -> int:
    """Mark events as distilled."""
    writer = StreamWriter()

    # Support --before flag for batch marking by date
    if args.before:
        count = writer.mark_distilled_before_date(args.before)
    elif args.event_ids:
        count = writer.mark_distilled(args.event_ids)
    else:
        print("Error: Provide event IDs or --before date", file=sys.stderr)
        return 1

    if args.format == "json":
        print(json.dumps({"marked": count}))
    else:
        print(f"Marked {count} event(s) as distilled")

    return 0


def cmd_archive(args: argparse.Namespace) -> int:
    """Archive old events."""
    writer = StreamWriter()
    count = writer.archive(days_old=args.days)

    if args.format == "json":
        print(json.dumps({"archived": count}))
    else:
        print(f"Archived {count} event(s)")

    return 0


def cmd_stats(args: argparse.Namespace) -> int:
    """Show stream statistics."""
    writer = StreamWriter()

    # Query all events
    all_events = writer.query(include_distilled=True)
    undistilled = writer.query(include_distilled=False)

    # Count by surface
    by_surface: dict[str, int] = {}
    for event in all_events:
        surface = event["surface"]
        by_surface[surface] = by_surface.get(surface, 0) + 1

    # Count by type
    by_type: dict[str, int] = {}
    for event in all_events:
        etype = event["type"]
        by_type[etype] = by_type.get(etype, 0) + 1

    # Get time range
    if all_events:
        timestamps = [e["timestamp"] for e in all_events]
        oldest = min(timestamps)
        newest = max(timestamps)
    else:
        oldest = newest = None

    stats = {
        "total_events": len(all_events),
        "undistilled": len(undistilled),
        "distilled": len(all_events) - len(undistilled),
        "by_surface": by_surface,
        "by_type": by_type,
        "oldest_event": oldest,
        "newest_event": newest,
    }

    if args.format == "json":
        print(json.dumps(stats, indent=2))
    else:
        print(f"Total events: {stats['total_events']}")
        print(f"Undistilled: {stats['undistilled']}")
        print(f"Distilled: {stats['distilled']}")
        print()
        print("By surface:")
        for surface, count in sorted(by_surface.items()):
            print(f"  {surface}: {count}")
        print()
        print("By type:")
        for etype, count in sorted(by_type.items()):
            print(f"  {etype}: {count}")
        if oldest:
            print()
            print(f"Oldest: {oldest}")
            print(f"Newest: {newest}")

    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    """Validate stream events against schema."""
    writer = StreamWriter()
    errors: list[dict[str, object]] = []
    total = 0
    stream_files = writer.list_stream_files()

    if not stream_files:
        errors, total = [], 0
    else:
        for stream_file in stream_files:
            file_errors, file_total = validate_stream_file(stream_file)
            for error in file_errors:
                error["file"] = str(stream_file)
            errors.extend(file_errors)
            total += file_total

    result = {
        "valid": len(errors) == 0,
        "total_events": total,
        "error_count": len(errors),
        "errors": errors,
    }

    if args.format == "json":
        print(json.dumps(result, indent=2))
    else:
        if result["valid"]:
            print(f"Stream valid ({total} events)")
        else:
            print(f"Stream invalid ({len(errors)} issues across {total} events)")
            for error in errors[:10]:
                line = error.get("line")
                event_id = error.get("id", "unknown")
                detail = "; ".join(error.get("errors", []))
                print(f"  line {line} [{event_id}]: {detail}")

    return 0


def cmd_rebuild_distilled_index(args: argparse.Namespace) -> int:
    """Rebuild distilled sidecar index from stream file."""
    writer = StreamWriter()
    count = writer.rebuild_distilled_index()

    if args.format == "json":
        print(json.dumps({"rebuilt": count}))
    else:
        print(f"Rebuilt distilled index ({count} event(s))")

    return 0


def cmd_migrate_daily(args: argparse.Namespace) -> int:
    """Migrate legacy stream file into daily shards."""
    writer = StreamWriter()
    count = writer.migrate_legacy_to_daily(archive_legacy=not args.keep_legacy)

    if args.format == "json":
        print(json.dumps({"migrated": count}))
    else:
        print(f"Migrated {count} event(s) to daily shards")

    return 0


def cmd_undistilled(args: argparse.Namespace) -> int:
    """Show undistilled events (for dream cycle)."""
    writer = StreamWriter()
    results = writer.query_undistilled(date=args.date, before_date=args.before)
    results = sort_events(results)

    if args.format == "json":
        print(json.dumps(results, indent=2))
    else:
        if not results:
            print("No undistilled events")
            return 0

        for event in results:
            ts = event["timestamp"][:19].replace("T", " ")
            surface = event["surface"]
            summary = event["summary"]
            print(f"[{ts}] ({surface}) {summary}")
            if event.get("content"):
                # Show first 200 chars of content
                content = event["content"][:200]
                if len(event["content"]) > 200:
                    content += "..."
                print(f"  Content: {content}")
            print()

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Unified Event Stream CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="Output format (default: text)",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    # write command
    write_parser = subparsers.add_parser("write", help="Write an event")
    write_parser.add_argument(
        "--surface",
        required=True,
        help=f"Event surface: {[s.value for s in Surface]}",
    )
    write_parser.add_argument(
        "--type",
        required=True,
        help=f"Event type: {[t.value for t in EventType]}",
    )
    write_parser.add_argument(
        "--direction",
        required=True,
        help=f"Direction: {[d.value for d in Direction]}",
    )
    write_parser.add_argument("--summary", required=True, help="Event summary")
    write_parser.add_argument("--session-id", help="Optional session ID")
    write_parser.add_argument("--content", help="Optional full content")
    write_parser.add_argument("--metadata", help="Optional metadata as JSON")
    write_parser.set_defaults(func=cmd_write)

    # query command
    query_parser = subparsers.add_parser("query", help="Query events")
    query_parser.add_argument("--hours", type=int, help="Only events from last N hours")
    query_parser.add_argument("--surface", help="Filter by surface")
    query_parser.add_argument("--type", help="Filter by type")
    query_parser.add_argument(
        "--include-distilled",
        action="store_true",
        help="Include distilled events",
    )
    query_parser.set_defaults(func=cmd_query)

    # mark-distilled command
    mark_parser = subparsers.add_parser("mark-distilled", help="Mark events as distilled")
    mark_parser.add_argument("event_ids", nargs="*", help="Event IDs to mark")
    mark_parser.add_argument(
        "--before",
        help="Mark all undistilled events before this date (YYYY-MM-DD)",
    )
    mark_parser.set_defaults(func=cmd_mark_distilled)

    # archive command
    archive_parser = subparsers.add_parser("archive", help="Archive old events")
    archive_parser.add_argument(
        "--days",
        type=int,
        default=30,
        help="Archive events older than N days (default: 30)",
    )
    archive_parser.set_defaults(func=cmd_archive)

    # stats command
    stats_parser = subparsers.add_parser("stats", help="Show stream statistics")
    stats_parser.set_defaults(func=cmd_stats)

    # validate command
    validate_parser = subparsers.add_parser("validate", help="Validate stream schema")
    validate_parser.set_defaults(func=cmd_validate)

    rebuild_parser = subparsers.add_parser(
        "rebuild-distilled-index",
        help="Rebuild distilled index from stream file",
    )
    rebuild_parser.set_defaults(func=cmd_rebuild_distilled_index)

    migrate_parser = subparsers.add_parser(
        "migrate-daily",
        help="Migrate legacy events.jsonl into daily shards",
    )
    migrate_parser.add_argument(
        "--keep-legacy",
        action="store_true",
        help="Keep events.jsonl after migration",
    )
    migrate_parser.set_defaults(func=cmd_migrate_daily)

    # undistilled command
    undistilled_parser = subparsers.add_parser(
        "undistilled",
        help="Show undistilled events",
    )
    undistilled_parser.add_argument("--date", help="Filter by exact date (YYYY-MM-DD)")
    undistilled_parser.add_argument(
        "--before",
        help="Show events before this date (YYYY-MM-DD)",
    )
    undistilled_parser.set_defaults(func=cmd_undistilled)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
