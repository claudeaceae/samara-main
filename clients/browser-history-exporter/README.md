# Browser History Exporter

Exports browser history from your Mac to Claude's memory system.

## What It Does

- Reads browsing history from Chrome/Dia and Safari
- Tracks what you've already exported (incremental updates)
- Deduplicates URLs visited in multiple browsers
- Summarizes domains for pattern detection
- POSTs data to Claude's webhook receiver

## Installation

On your Mac (the one you browse from):

```bash
cd /path/to/samara-main/clients/browser-history-exporter
./install.sh
```

Then edit `~/.claude-client/config.json`:

```json
{
  "webhook_url": "https://your-cloudflare-tunnel-url/webhook/browser_history",
  "webhook_secret": "your-shared-secret-here",
  "browsers": ["dia", "safari"],
  "poll_interval_min": 15,
  "device_name": "eriks-macbook"
}
```

## Server Setup (Claude's Mac)

Add the browser_history source to webhook secrets:

```bash
# On Claude's Mac, edit ~/.claude-mind/self/credentials/webhook-secrets.json
{
  "sources": {
    "browser_history": {
      "secret": "your-shared-secret-here",
      "rate_limit": "60/minute"
    }
  }
}
```

Enable the service in config:

```bash
# Edit ~/.claude-mind/config.json
{
  "services": {
    "browserHistory": true
  }
}
```

## Manual Testing

Run the exporter manually to verify it works:

```bash
python3 ~/.claude-client/browser-history-exporter/exporter.py
```

You should see output like:
```
Reading dia history since beginning...
  Found 42 new visits
Reading safari history since beginning...
  Found 18 new visits
Total visits after deduplication: 55
Top domains: ['github.com', 'stackoverflow.com', ...]
Sent 55 visits. Response: accepted
```

## Browser Support

| Browser | Status | DB Location |
|---------|--------|-------------|
| Dia     | Supported | `~/Library/Application Support/Dia/Default/History` |
| Chrome  | Supported | `~/Library/Application Support/Google/Chrome/Default/History` |
| Safari  | Supported | `~/Library/Safari/History.db` |
| Arc     | Supported | `~/Library/Application Support/Arc/User Data/Default/History` |

Edit `browsers` in config.json to choose which browsers to track.

## Files

| Location | Purpose |
|----------|---------|
| `/Users/Shared/.claude-client/browser-history-exporter/` | Exporter script |
| `~/.claude-client/config.json` | Your configuration |
| `~/.claude-client/browser-history-state.json` | Last-seen timestamps (auto-managed) |
| `/Users/Shared/.claude-client/logs/` | Log files |
| `~/Library/LaunchAgents/com.claude.browser-history-exporter.plist` | Scheduler |

## Troubleshooting

**"Webhook URL not configured"**
- Edit `~/.claude-client/config.json` with your actual webhook URL

**"Failed to send to webhook: Connection refused"**
- Check that Claude's webhook-receiver is running
- Verify your Cloudflare Tunnel is up

**No visits found**
- Check that the browser paths exist (the script will skip missing browsers)
- Safari requires Full Disk Access for terminal apps

**"Error copying database"**
- The browser's database might be locked. Close the browser and retry.

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.claude.browser-history-exporter.plist
rm -rf /Users/Shared/.claude-client/browser-history-exporter
rm ~/Library/LaunchAgents/com.claude.browser-history-exporter.plist
```
