# Wallet Watcher

Monitors Solana, Ethereum, and Bitcoin wallet balances for changes and transactions, writing sense events when significant activity is detected.

## How It Works

- Runs every 15 minutes via launchd
- Polls public RPC endpoints (no API keys required)
- Compares current balances to previous state
- Writes sense events for significant changes:
  - Deposits > $100 → `immediate` priority
  - Any withdrawal → `immediate` priority
  - Smaller deposits → `normal` priority

## Wallets Monitored

| Chain | Address |
|-------|---------|
| Solana | `8oyD1P9Kdu4ZkC78q39uvEifAqQv26sULnjoKsHzJe6C` |
| Ethereum | `0xE74E61C5e9beE3f989824A20e138f9aAE16f41Ad` |
| Bitcoin | `bc1qu9m98ae7nf5z599ah8hev8xyuf7alr0ntskhwn` |

## Setup

### 1. Configure Wallets (Optional)

The wallet addresses are configured in `~/.claude-mind/self/credentials/wallet-apis.json`:

```json
{
  "solana": {
    "address": "YOUR_SOL_ADDRESS",
    "rpc": "https://api.mainnet-beta.solana.com"
  },
  "ethereum": {
    "address": "YOUR_ETH_ADDRESS",
    "rpc": "https://eth.llamarpc.com"
  },
  "bitcoin": {
    "address": "YOUR_BTC_ADDRESS"
  }
}
```

### 2. Test Manually

```bash
cd services/wallet-watcher
python3 server.py
```

### 3. Install launchd Service

```bash
# Check status
launchctl list | grep wallet-watcher

# Load if needed
launchctl load ~/Library/LaunchAgents/com.claude.wallet-watcher.plist
```

## Sense Events

When balance changes are detected:

```json
{
  "sense": "wallet",
  "timestamp": "2026-01-24T12:00:00Z",
  "priority": "immediate",
  "data": {
    "chain": "solana",
    "type": "deposit",
    "amount": 1.5,
    "previous_balance": 10.0,
    "new_balance": 11.5,
    "usd_estimate": 225.0
  }
}
```

## State Files

- `~/.claude-mind/state/wallet-state.json` — Tracked balances and last seen state

## Logs

- `~/.claude-mind/system/logs/wallet-watcher.log`

## Related Scripts

- `wallet-status` — Display current balances and addresses
- `solana-wallet` — Solana-specific operations

## Related Skill

- `/wallet` — Check balances, addresses, or recent history

## Current Limitations

- Read-only (no transaction signing)
- USD estimates use hardcoded prices, not live market data
- Native assets only (no token tracking)
