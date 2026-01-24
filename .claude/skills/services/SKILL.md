# /services - Service Toggle System

Manage which services are active in the Samara organism. Services can be toggled on/off without deleting code - they're simply unplugged from the wake cycle, sense routing, and launchd scheduling.

## Quick Commands

```bash
# List all services with current status
~/.claude-mind/system/bin/service-toggle list

# Toggle a service
~/.claude-mind/system/bin/service-toggle <service> on|off|status
```

## Available Services

| Service | Description | launchd Agents |
|---------|-------------|----------------|
| `x` | X/Twitter mentions, replies, posting | x-watcher, x-engage |
| `bluesky` | Bluesky notifications, DMs, posting | bluesky-watcher, bluesky-engage |
| `github` | GitHub notifications | github-watcher |
| `wallet` | Crypto wallet monitoring | wallet-watcher |
| `meeting` | Calendar meeting prep/debrief | meeting-check |
| `webhook` | External webhook events | webhook-receiver |
| `location` | Location tracking | location-receiver |

## How It Works

The service toggle system has three layers:

### 1. Config (`~/.claude-mind/system/config.json`)

```json
{
  "services": {
    "x": false,
    "bluesky": false,
    "github": true,
    "wallet": true,
    "meeting": true,
    "webhook": true,
    "location": true
  }
}
```

### 2. SenseRouter (Samara.app)

When Samara starts, `SenseRouter.registerDefaultHandlers()` checks `config.servicesConfig.isEnabled()` for each service. Disabled services don't get handlers registered, so their sense events are ignored.

### 3. launchd Agents

The `service-toggle` script also manages launchd agents - when you disable a service, it unloads the corresponding agents so they stop polling/watching.

## Usage Examples

### Check current status
```bash
~/.claude-mind/system/bin/service-toggle list
```

Output:
```
Service Status:
---------------
x            config: false  launchd: unloaded
bluesky      config: false  launchd: unloaded
github       config: true   launchd: loaded
...
```

### Disable a service
```bash
~/.claude-mind/system/bin/service-toggle x off
```

This will:
1. Set `services.x = false` in config.json
2. Unload `com.claude.x-watcher` and `com.claude.x-engage` from launchd
3. Print a reminder to restart Samara.app for handler changes

### Re-enable a service
```bash
~/.claude-mind/system/bin/service-toggle bluesky on
```

This will:
1. Set `services.bluesky = true` in config.json
2. Load the bluesky launchd agents
3. Print a reminder to restart Samara.app

### Restart Samara.app (for handler changes)
```bash
pkill -x Samara && sleep 1 && open -a Samara
```

Or use the update-samara script if you also have code changes.

## Important Notes

- **Non-destructive**: Disabling a service doesn't delete any code - it just unplugs it
- **Restart required**: Samara.app reads config at startup, so restart after toggling for handler changes to take effect
- **launchd is immediate**: The launchd agents are loaded/unloaded immediately
- **Defaults to enabled**: Services not specified in config default to enabled (backward compatible)

## Files

| File | Purpose |
|------|---------|
| `~/.claude-mind/system/config.json` | Runtime config with `services` section |
| `Samara/Samara/Configuration.swift` | `ServicesConfig` struct and `isEnabled()` method |
| `Samara/Samara/Mind/SenseRouter.swift` | Checks config before registering handlers |
| `scripts/service-toggle` | CLI for toggling services |

## When to Use This

Use the service toggle system when you want to:
- **Reduce token usage** by disabling services you're not actively using
- **Pause a noisy service** temporarily without losing the capability
- **Debug** by isolating which services are active
- **Focus** by limiting which channels are monitored

The system is designed for clean plug/unplug without code changes.

---

## Implementing New Services (REQUIRED)

**All new senses and services MUST be toggleable.** This is a hard requirement for any capability that polls external services, processes sense events, contributes to memory, or consumes tokens.

### Checklist for New Services

1. **Configuration.swift** - Add to `ServicesConfig`:
   ```swift
   let myservice: Bool?

   // In isEnabled():
   case "myservice": return myservice ?? true
   ```

2. **SenseRouter.swift** - Guard the handler:
   ```swift
   if services.isEnabled("myservice") {
       handlers["myservice"] = { [weak self] event in
           self?.handleMyServiceEvent(event)
       }
   }
   ```

3. **scripts/service-toggle** - Register the service:
   ```bash
   # Add to SERVICES list:
   SERVICES="x bluesky github wallet meeting webhook location myservice"

   # Add to get_agents():
   myservice) echo "com.claude.myservice-watcher" ;;
   ```

4. **config.json** - Add default (usually `true`):
   ```json
   "services": {
     "myservice": true
   }
   ```

5. **This file** - Add to the Available Services table above

### Why This Matters

The collaborator needs the ability to cleanly disable any service without touching code. This prevents:
- Unwanted token consumption
- Noise from services that aren't actively needed
- Tight coupling that makes the system harder to manage

See existing implementations (x, bluesky, wallet, meeting) for reference patterns.
