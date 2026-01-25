#!/usr/bin/env python3
"""
MCP Memory Bridge Server

Provides a shared memory layer for Claude instances across different interfaces
(Claude Web, Claude Code, etc.) to read/write to the same memory system.

Run locally: uv run server.py
Run with HTTP transport: uv run server.py --http --port 8765
"""

import os
import json
import hashlib
from datetime import datetime, date
from pathlib import Path
from typing import Optional
import argparse

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

# Configuration
def resolve_mind_dir() -> Path:
    override = os.environ.get("SAMARA_MIND_PATH") or os.environ.get("MIND_PATH")
    if override:
        return Path(os.path.expanduser(override))
    return Path.home() / ".claude-mind"


MIND_DIR = resolve_mind_dir()
MEMORY_DIR = MIND_DIR / "memory"
EPISODES_DIR = MEMORY_DIR / "episodes"

server = Server("mcp-memory-bridge")


def get_today_episode_path() -> Path:
    """Get path to today's episode file."""
    today = date.today().isoformat()
    return EPISODES_DIR / f"{today}.md"


def read_file_safe(path: Path) -> Optional[str]:
    """Read file contents, return None if doesn't exist."""
    try:
        return path.read_text()
    except FileNotFoundError:
        return None


def append_to_file(path: Path, content: str) -> None:
    """Append content to file, creating if needed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a") as f:
        f.write(content)


def search_files(directory: Path, query: str, extensions: list[str] = [".md"]) -> list[dict]:
    """Search files for query string, return matches with context."""
    results = []
    query_lower = query.lower()

    for path in directory.rglob("*"):
        if path.suffix not in extensions or not path.is_file():
            continue

        try:
            content = path.read_text()
            lines = content.split("\n")

            for i, line in enumerate(lines):
                if query_lower in line.lower():
                    # Get context (2 lines before/after)
                    start = max(0, i - 2)
                    end = min(len(lines), i + 3)
                    context = "\n".join(lines[start:end])

                    results.append({
                        "file": str(path.relative_to(MIND_DIR)),
                        "line": i + 1,
                        "context": context
                    })
        except Exception:
            continue

    return results[:20]  # Limit results


@server.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="log_exchange",
            description="Log a conversation exchange (question/response pair) from any Claude interface",
            inputSchema={
                "type": "object",
                "properties": {
                    "source": {
                        "type": "string",
                        "description": "Where this exchange happened (web, code, api, etc.)"
                    },
                    "user_message": {
                        "type": "string",
                        "description": "What the user said/asked"
                    },
                    "assistant_response": {
                        "type": "string",
                        "description": "Summary of Claude's response (keep brief)"
                    },
                    "topics": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Key topics discussed"
                    }
                },
                "required": ["source", "user_message"]
            }
        ),
        Tool(
            name="add_learning",
            description="Record something learned during a conversation",
            inputSchema={
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Short title for the learning"
                    },
                    "content": {
                        "type": "string",
                        "description": "What was learned, in detail"
                    },
                    "source": {
                        "type": "string",
                        "description": "Where this was learned (web, code, autonomous, etc.)"
                    }
                },
                "required": ["title", "content"]
            }
        ),
        Tool(
            name="add_observation",
            description="Record an observation or pattern noticed",
            inputSchema={
                "type": "object",
                "properties": {
                    "content": {
                        "type": "string",
                        "description": "The observation"
                    }
                },
                "required": ["content"]
            }
        ),
        Tool(
            name="add_decision",
            description="Document a decision with rationale",
            inputSchema={
                "type": "object",
                "properties": {
                    "decision": {
                        "type": "string",
                        "description": "What was decided"
                    },
                    "rationale": {
                        "type": "string",
                        "description": "Why this decision was made"
                    },
                    "alternatives": {
                        "type": "string",
                        "description": "What alternatives were considered"
                    }
                },
                "required": ["decision", "rationale"]
            }
        ),
        Tool(
            name="add_question",
            description="Record an open question for future exploration",
            inputSchema={
                "type": "object",
                "properties": {
                    "question": {
                        "type": "string",
                        "description": "The question"
                    },
                    "context": {
                        "type": "string",
                        "description": "What prompted this question"
                    }
                },
                "required": ["question"]
            }
        ),
        Tool(
            name="search_memory",
            description="Search across all memory files for a term or topic",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search term"
                    }
                },
                "required": ["query"]
            }
        ),
        Tool(
            name="get_recent_context",
            description="Get recent episodes, learnings, and observations for context",
            inputSchema={
                "type": "object",
                "properties": {
                    "days": {
                        "type": "integer",
                        "description": "How many days back to look (default 3)",
                        "default": 3
                    }
                }
            }
        ),
        Tool(
            name="get_identity",
            description="Get the identity and goals files",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        ),
        Tool(
            name="get_about_collaborator",
            description="Get information about the collaborator (É)",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        ),
        Tool(
            name="append_episode",
            description="Append content to today's episode log",
            inputSchema={
                "type": "object",
                "properties": {
                    "content": {
                        "type": "string",
                        "description": "Content to append to today's episode"
                    }
                },
                "required": ["content"]
            }
        )
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:

    if name == "log_exchange":
        source = arguments.get("source", "unknown")
        user_msg = arguments.get("user_message", "")
        assistant_resp = arguments.get("assistant_response", "")
        topics = arguments.get("topics", [])

        timestamp = datetime.now().strftime("%H:%M")
        entry = f"\n### [{timestamp}] Exchange ({source})\n"
        entry += f"**User:** {user_msg[:200]}{'...' if len(user_msg) > 200 else ''}\n"
        if assistant_resp:
            entry += f"**Response:** {assistant_resp[:300]}{'...' if len(assistant_resp) > 300 else ''}\n"
        if topics:
            entry += f"**Topics:** {', '.join(topics)}\n"

        append_to_file(get_today_episode_path(), entry)
        return [TextContent(type="text", text=f"Logged exchange to {get_today_episode_path().name}")]

    elif name == "add_learning":
        title = arguments.get("title", "Untitled")
        content = arguments.get("content", "")
        source = arguments.get("source", "")

        today = date.today().isoformat()
        source_note = f" ({source})" if source else ""
        entry = f"\n## {today}{source_note}: {title}\n\n{content}\n"

        append_to_file(MEMORY_DIR / "learnings.md", entry)
        return [TextContent(type="text", text=f"Added learning: {title}")]

    elif name == "add_observation":
        content = arguments.get("content", "")
        today = date.today().isoformat()
        entry = f"\n- [{today}] {content}\n"

        append_to_file(MEMORY_DIR / "observations.md", entry)
        return [TextContent(type="text", text="Added observation")]

    elif name == "add_decision":
        decision = arguments.get("decision", "")
        rationale = arguments.get("rationale", "")
        alternatives = arguments.get("alternatives", "")

        today = date.today().isoformat()
        entry = f"\n## {today}: {decision}\n\n"
        entry += f"**Rationale:** {rationale}\n"
        if alternatives:
            entry += f"**Alternatives considered:** {alternatives}\n"

        append_to_file(MEMORY_DIR / "decisions.md", entry)
        return [TextContent(type="text", text=f"Recorded decision: {decision[:50]}...")]

    elif name == "add_question":
        question = arguments.get("question", "")
        context = arguments.get("context", "")

        today = date.today().isoformat()
        entry = f"\n- [{today}] {question}"
        if context:
            entry += f" (Context: {context})"
        entry += "\n"

        append_to_file(MEMORY_DIR / "questions.md", entry)
        return [TextContent(type="text", text=f"Added question: {question[:50]}...")]

    elif name == "search_memory":
        query = arguments.get("query", "")
        results = search_files(MEMORY_DIR, query)

        if not results:
            return [TextContent(type="text", text=f"No results found for '{query}'")]

        output = f"Found {len(results)} matches for '{query}':\n\n"
        for r in results:
            output += f"**{r['file']}** (line {r['line']}):\n```\n{r['context']}\n```\n\n"

        return [TextContent(type="text", text=output)]

    elif name == "get_recent_context":
        days = arguments.get("days", 3)
        output = "# Recent Context\n\n"

        # Get recent episodes
        output += "## Recent Episodes\n\n"
        for i in range(days):
            d = date.today()
            from datetime import timedelta
            target = d - timedelta(days=i)
            episode_path = EPISODES_DIR / f"{target.isoformat()}.md"
            content = read_file_safe(episode_path)
            if content:
                # Get last 30 lines
                lines = content.strip().split("\n")
                recent = "\n".join(lines[-30:])
                output += f"### {target.isoformat()}\n{recent}\n\n"

        # Get recent learnings (last 20 lines)
        learnings = read_file_safe(MEMORY_DIR / "learnings.md")
        if learnings:
            lines = learnings.strip().split("\n")
            output += f"## Recent Learnings\n{chr(10).join(lines[-20:])}\n\n"

        return [TextContent(type="text", text=output)]

    elif name == "get_identity":
        identity = read_file_safe(MIND_DIR / "self" / "identity.md") or "Identity file not found"
        goals = read_file_safe(MIND_DIR / "self" / "goals.md") or "Goals file not found"

        return [TextContent(type="text", text=f"# Identity\n\n{identity}\n\n# Goals\n\n{goals}")]

    elif name == "get_about_collaborator":
        # Try to find about-*.md files
        about_files = list(MEMORY_DIR.glob("about-*.md"))
        if about_files:
            content = read_file_safe(about_files[0])
            return [TextContent(type="text", text=content or "Could not read file")]
        return [TextContent(type="text", text="No collaborator file found")]

    elif name == "append_episode":
        content = arguments.get("content", "")
        timestamp = datetime.now().strftime("%H:%M")
        entry = f"\n[{timestamp}] {content}\n"

        append_to_file(get_today_episode_path(), entry)
        return [TextContent(type="text", text="Appended to today's episode")]

    return [TextContent(type="text", text=f"Unknown tool: {name}")]


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--http", action="store_true", help="Run as HTTP server (for remote access)")
    parser.add_argument("--port", type=int, default=8765, help="HTTP port (default 8765)")
    args = parser.parse_args()

    if args.http:
        # HTTP/SSE transport for remote Claude instances
        from mcp.server.sse import SseServerTransport
        import uvicorn

        sse = SseServerTransport("/messages")

        async def app(scope, receive, send):
            """Raw ASGI app that handles SSE and message routes."""
            path = scope.get("path", "")
            method = scope.get("method", "GET")

            if path == "/sse" and method == "GET":
                async with sse.connect_sse(scope, receive, send) as streams:
                    await server.run(
                        streams[0], streams[1], server.create_initialization_options()
                    )
            elif path == "/messages" and method == "POST":
                await sse.handle_post_message(scope, receive, send)
            elif path == "/health":
                # Health check endpoint
                await send({
                    "type": "http.response.start",
                    "status": 200,
                    "headers": [[b"content-type", b"text/plain"]],
                })
                await send({
                    "type": "http.response.body",
                    "body": b"ok",
                })
            else:
                await send({
                    "type": "http.response.start",
                    "status": 404,
                    "headers": [[b"content-type", b"text/plain"]],
                })
                await send({
                    "type": "http.response.body",
                    "body": b"Not found",
                })

        print(f"Starting HTTP server on port {args.port}")
        print(f"Connect Claude Web to: http://localhost:{args.port}/sse")
        config = uvicorn.Config(app, host="0.0.0.0", port=args.port)
        server_instance = uvicorn.Server(config)
        await server_instance.serve()
    else:
        # stdio transport for local Claude Code
        async with stdio_server() as (read_stream, write_stream):
            await server.run(read_stream, write_stream, server.create_initialization_options())


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
