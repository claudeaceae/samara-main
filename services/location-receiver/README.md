# Location Receiver

A simple HTTP server that receives GPS data from [Overland](https://overland.p3k.app/), a background location tracking app for iOS.

## Why Overland?

Overland handles the hard parts of location tracking:
- Background location updates on iOS
- Battery optimization
- Batching and reliable delivery
- Works even when the phone is locked

This server just receives the data and stores it.

## Data Storage

- **Latest location**: `~/.claude-mind/state/location.json`
- **History**: `~/.claude-mind/state/location-history.jsonl`

## Setup

### 1. Start the server

The server runs on port 8081. You can run it directly:

```bash
python3 server.py
```

Or install as a launchd service (recommended):

```bash
# Copy the template plist
cp co.organelle.location-receiver.plist ~/Library/LaunchAgents/

# Edit to fix the path to server.py
# Then load it:
launchctl load ~/Library/LaunchAgents/co.organelle.location-receiver.plist
```

### 2. Configure Overland

1. Install Overland on your iOS device
2. Open Settings in Overland
3. Set the receiver URL to: `http://<your-mac-ip>:8081`
4. Enable tracking

### 3. Network Access

The Mac must be reachable from your phone. Options:
- Same WiFi network (use local IP like `192.168.x.x`)
- Tailscale or similar VPN (recommended for reliability)
- Port forwarding (not recommended for security)

## Data Format

Overland sends GeoJSON. The server extracts:
- `lat`, `lon` - coordinates
- `altitude` - meters
- `speed` - meters/second
- `battery` - battery level (0-1)
- `wifi` - connected SSID
- `motion` - detected motion types

## Reading Location Data

```bash
# Latest location
cat ~/.claude-mind/state/location.json

# Or use the helper script
~/.claude-mind/bin/get-e-location
```
