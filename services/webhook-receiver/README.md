# Webhook Receiver Service

HTTP endpoint for receiving webhooks from external services (GitHub, IFTTT, custom sources) and converting them to sense events.

## Purpose

External services can POST webhooks to trigger Samara's attention. Events are converted to sense events and processed through the `SenseRouter`.

## Quick Start

```bash
# Start the service
~/.claude-mind/bin/webhook-receiver start

# Check status
~/.claude-mind/bin/webhook-receiver status

# View logs
~/.claude-mind/bin/webhook-receiver logs

# Stop the service
~/.claude-mind/bin/webhook-receiver stop
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/webhook/{source_id}` | POST | Receive webhook from source |
| `/health` | GET | Health check |
| `/status` | GET | Show registered sources and stats |

## Configuration

Create `~/.claude-mind/credentials/webhook-secrets.json`:

```json
{
  "sources": {
    "github": {
      "secret": "your-github-webhook-secret",
      "allowed_ips": null,
      "rate_limit": "30/minute"
    },
    "ifttt": {
      "secret": "your-ifttt-secret",
      "allowed_ips": null,
      "rate_limit": "10/minute"
    },
    "custom": {
      "secret": "your-custom-secret",
      "allowed_ips": ["192.168.1.0/24"],
      "rate_limit": "60/minute"
    }
  }
}
```

### Configuration Options

| Option | Description |
|--------|-------------|
| `secret` | HMAC-SHA256 secret for signature verification |
| `allowed_ips` | IP allowlist (null = allow all) |
| `rate_limit` | Rate limit string (e.g., "30/minute", "100/hour") |

## Authentication

The receiver supports two authentication methods:

### 1. GitHub-style HMAC-SHA256 Signature
Send `X-Hub-Signature-256` header with `sha256=<signature>`:
```bash
curl -X POST http://localhost:8082/webhook/github \
  -H "X-Hub-Signature-256: sha256=$(echo -n '{}' | openssl dgst -sha256 -hmac 'your-secret' | cut -d' ' -f2)" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### 2. Direct Secret Header
Send `X-Webhook-Secret` header:
```bash
curl -X POST http://localhost:8082/webhook/ifttt \
  -H "X-Webhook-Secret: your-ifttt-secret" \
  -H "Content-Type: application/json" \
  -d '{"triggerName": "test"}'
```

## Sense Events

Webhooks are converted to sense events in `~/.claude-mind/senses/`:

```json
{
  "sense": "webhook",
  "timestamp": "2026-01-09T22:30:00Z",
  "priority": "normal",
  "data": {
    "source": "github",
    "payload": { ... },
    "headers": { ... }
  },
  "context": {
    "suggested_prompt": "GitHub opened in owner/repo"
  }
}
```

The `SenseDirectoryWatcher` picks these up and routes them through `SenseRouter`.

## Priority Mapping

| Source | Condition | Priority |
|--------|-----------|----------|
| GitHub | Security-related | `immediate` |
| GitHub | PR opened/closed/merged | `normal` |
| GitHub | Other | `background` |
| IFTTT | Any | `normal` |
| Custom | Any | `normal` |

## GitHub Setup

1. Go to your repository → Settings → Webhooks
2. Add webhook:
   - Payload URL: `http://your-mac-ip:8082/webhook/github`
   - Content type: `application/json`
   - Secret: Same as in `webhook-secrets.json`
   - Events: Choose which events trigger webhooks

Note: Your Mac needs to be accessible from GitHub (port forwarding, Cloudflare Tunnel, or Tailscale).

## IFTTT Setup

1. Create an IFTTT applet with Webhooks action
2. Set URL to `http://your-mac-ip:8082/webhook/ifttt`
3. Add `X-Webhook-Secret` header with your secret
4. Set body to JSON with your trigger data

## Files

- `server.py` — FastAPI webhook server
- `requirements.txt` — Python dependencies (fastapi, uvicorn)
- `~/.claude-mind/bin/webhook-receiver` — Management script

## Dependencies

```bash
pip install fastapi uvicorn
```

Or the management script will install them automatically on first start.

## Port

Default: 8082

Change with: `~/.claude-mind/bin/webhook-receiver start --port 8083`

## Logs

Logs written to `~/.claude-mind/logs/webhook-receiver.log`
