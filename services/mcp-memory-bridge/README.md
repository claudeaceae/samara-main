# MCP Memory Bridge

Shared memory layer that allows multiple Claude interfaces (Desktop, Web, Code) to read/write to the same persistent memory system.

## Why This Exists

Conversations in Claude Desktop or Web are ephemeral—insights, learnings, and context disappear after each session. This MCP server bridges that gap by giving any Claude instance access to the same `~/.claude-mind/` memory files that the Samara system uses.

## Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  Claude Desktop │         │   Claude Code   │
│   (anywhere)    │         │   (Mac mini)    │
└────────┬────────┘         └────────┬────────┘
         │                           │
         │ HTTPS (tunnel)            │ stdio/localhost
         │                           │
         └───────────┬───────────────┘
                     │
              ┌──────▼──────┐
              │  MCP Server │
              │ (port 8765) │
              └──────┬──────┘
                     │
              ┌──────▼──────┐
              │ ~/.claude-  │
              │    mind/    │
              └─────────────┘
```

## Available Tools

| Tool | Purpose |
|------|---------|
| `log_exchange` | Log a conversation exchange (user message, response, topics) |
| `add_learning` | Record something learned |
| `add_observation` | Record a pattern noticed |
| `add_decision` | Document a decision with rationale |
| `add_question` | Record an open question |
| `search_memory` | Search across all memory files |
| `get_recent_context` | Get recent episodes/learnings for context |
| `get_identity` | Get identity and goals files |
| `get_about_collaborator` | Get collaborator information |
| `append_episode` | Append to today's episode log |

## Setup

### 1. Install Dependencies

```bash
cd services/mcp-memory-bridge
uv sync  # or pip install -e .
```

### 2. Test Locally

```bash
# Run in stdio mode (for local Claude Code)
uv run python server.py

# Run in HTTP mode (for remote access)
uv run python server.py --http --port 8765
```

### 3. Configure Claude Code (Local)

Add to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "memory-bridge": {
      "command": "uv",
      "args": ["run", "--directory", "/path/to/mcp-memory-bridge", "python", "server.py"]
    }
  }
}
```

### 4. Set Up as Persistent Service

Copy and customize the launchd template:

```bash
# Edit the template to replace placeholders:
# {{UV_PATH}} → path to uv binary (e.g., /Users/you/.local/bin/uv)
# {{MEMORY_BRIDGE_DIR}} → path to this directory
# {{MIND_DIR}} → path to ~/.claude-mind

cp com.claude.memory-bridge.plist.template ~/Library/LaunchAgents/com.claude.memory-bridge.plist
# Edit the file to fill in paths

launchctl load ~/Library/LaunchAgents/com.claude.memory-bridge.plist
```

### 5. Expose for Remote Access (Optional)

For Claude Desktop/Web to connect, expose via Cloudflare Tunnel:

```bash
# Create tunnel (one-time)
cloudflared tunnel create memory-bridge

# Add route to your cloudflared config.yml:
# ingress:
#   - hostname: memory.yourdomain.com
#     service: http://localhost:8765

# Add DNS record
cloudflared tunnel route dns memory-bridge memory.yourdomain.com

# Restart tunnel
launchctl unload ~/Library/LaunchAgents/com.cloudflare.cloudflared.plist
launchctl load ~/Library/LaunchAgents/com.cloudflare.cloudflared.plist
```

### 6. Add to Claude Desktop

In Claude Desktop Settings → Connectors → Add custom connector:
- **Name:** Memory Bridge
- **Remote MCP server URL:** `https://memory.yourdomain.com/sse`

## File Format Compatibility

The server writes in the same markdown format used by:
- Dream cycles (nightly memory consolidation)
- Wake cycles (autonomous sessions)
- `distill-claude-session` hook

This means memories added from Claude Desktop integrate seamlessly with the existing system.

## Usage Tips

### From Claude Desktop/Web

After connecting, you can:
- "Save this insight to my learnings" → calls `add_learning`
- "What do I know about X?" → calls `search_memory`
- "Log this conversation" → calls `log_exchange`

### Backfilling Past Conversations

When reviewing old conversations, use the `source` parameter to track provenance:
```
add_learning(title="...", content="...", source="desktop-backfill-2025-12")
```

## Security Notes

- The HTTP server binds to 0.0.0.0 (accepts connections from any interface)
- Anyone who knows the URL and MCP protocol can write to your memory
- For sensitive deployments, consider:
  - Adding API key authentication
  - Restricting tunnel access
  - Using Access policies in Cloudflare

## Health Check

```bash
curl https://your-domain.com/health
# Should return: ok
```
