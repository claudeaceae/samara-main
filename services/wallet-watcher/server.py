#!/usr/bin/env python3
"""
Wallet Watcher - Monitors SOL/ETH/BTC wallets for balance changes and transactions.
Writes SenseEvents when significant activity is detected.

Runs every 15 minutes via launchd. Uses public RPC endpoints (no API keys required).
Uses only standard library (no external dependencies).
"""

import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone
from typing import Dict, List, Optional, Any


# Environment configuration
def resolve_mind_dir() -> str:
    override = os.environ.get("SAMARA_MIND_PATH") or os.environ.get("MIND_PATH")
    if override:
        return os.path.expanduser(override)
    return os.path.expanduser("~/.claude-mind")


MIND_DIR = resolve_mind_dir()
CREDS_FILE = os.path.join(MIND_DIR, 'self', 'credentials', 'wallet-apis.json')
STATE_FILE = os.path.join(MIND_DIR, 'state', 'wallet-state.json')
SENSES_DIR = os.path.join(MIND_DIR, 'system', 'senses')
LOG_FILE = os.path.join(MIND_DIR, 'system', 'logs', 'wallet-watcher.log')

# Approximate USD prices for threshold calculation (rough estimates)
APPROX_PRICES_USD = {
    'solana': 150.0,    # ~$150/SOL
    'ethereum': 3100.0, # ~$3100/ETH
    'bitcoin': 92000.0  # ~$92000/BTC
}

# Minimum change thresholds (in native units) to avoid noise
MIN_CHANGE_THRESHOLDS = {
    'solana': 0.001,      # 0.001 SOL
    'ethereum': 0.0001,   # 0.0001 ETH
    'bitcoin': 0.00001,   # 0.00001 BTC (1000 sats)
}

# $100 threshold for immediate priority (in native units)
IMMEDIATE_THRESHOLD_USD = 100.0

# Request timeout in seconds
REQUEST_TIMEOUT = 30


def log(message: str):
    """Write to log file with timestamp."""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    log_line = f"[{timestamp}] {message}"
    print(log_line)

    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, 'a') as f:
            f.write(log_line + '\n')
    except Exception as e:
        print(f"Warning: Could not write to log file: {e}", file=sys.stderr)


def http_post_json(url: str, data: Dict) -> Optional[Dict]:
    """Make a JSON POST request and return parsed response."""
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(data).encode('utf-8'),
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            return json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        log(f"HTTP error {e.code}: {e.reason}")
        return None
    except urllib.error.URLError as e:
        log(f"URL error: {e.reason}")
        return None
    except Exception as e:
        log(f"Request error: {e}")
        return None


def http_get_json(url: str) -> Optional[Dict]:
    """Make a GET request and return parsed JSON response."""
    try:
        req = urllib.request.Request(url, method='GET')
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            return json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        log(f"HTTP error {e.code}: {e.reason}")
        return None
    except urllib.error.URLError as e:
        log(f"URL error: {e.reason}")
        return None
    except Exception as e:
        log(f"Request error: {e}")
        return None


def load_credentials() -> Optional[Dict]:
    """Load wallet API configuration."""
    try:
        with open(CREDS_FILE, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        log(f"Credentials file not found: {CREDS_FILE}")
        return None
    except json.JSONDecodeError as e:
        log(f"Invalid JSON in credentials file: {e}")
        return None


def load_state() -> Dict:
    """Load previous wallet state."""
    try:
        with open(STATE_FILE, 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {
            'last_check': None,
            'solana': {'balance': 0.0, 'last_signature': None},
            'ethereum': {'balance': 0.0, 'last_tx_hash': None},
            'bitcoin': {'balance': 0.0, 'last_txid': None}
        }


def save_state(state: Dict):
    """Save current wallet state."""
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    state['last_check'] = datetime.now(timezone.utc).isoformat()
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)


def fetch_solana_balance(config: Dict) -> Optional[Dict]:
    """Fetch Solana balance via public RPC."""
    rpc_url = config.get('rpc_url', 'https://api.mainnet-beta.solana.com')
    address = config.get('address')

    if not address:
        log("Solana address not configured")
        return None

    # Get balance
    data = http_post_json(rpc_url, {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'getBalance',
        'params': [address]
    })

    if not data:
        return None

    if 'error' in data:
        log(f"Solana RPC error: {data['error']}")
        return None

    lamports = data.get('result', {}).get('value', 0)
    balance_sol = lamports / 1_000_000_000  # Convert lamports to SOL

    # Get recent signatures for transaction tracking
    sig_data = http_post_json(rpc_url, {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'getSignaturesForAddress',
        'params': [address, {'limit': 5}]
    })

    signatures = []
    if sig_data and 'result' in sig_data:
        signatures = [s.get('signature') for s in sig_data.get('result', [])]

    return {
        'balance': balance_sol,
        'last_signature': signatures[0] if signatures else None,
        'recent_signatures': signatures[:5],
        'address': address
    }


def fetch_ethereum_balance(config: Dict) -> Optional[Dict]:
    """Fetch Ethereum balance via public RPC."""
    rpc_url = config.get('rpc_url', 'https://ethereum-rpc.publicnode.com')
    address = config.get('address')

    if not address:
        log("Ethereum address not configured")
        return None

    data = http_post_json(rpc_url, {
        'jsonrpc': '2.0',
        'method': 'eth_getBalance',
        'params': [address, 'latest'],
        'id': 1
    })

    if not data:
        return None

    if 'error' in data:
        log(f"Ethereum RPC error: {data['error']}")
        return None

    wei = int(data.get('result', '0x0'), 16)
    balance_eth = wei / 1_000_000_000_000_000_000  # Convert wei to ETH

    return {
        'balance': balance_eth,
        'last_tx_hash': None,  # Would need Etherscan API for tx history
        'address': address
    }


def fetch_bitcoin_balance(config: Dict) -> Optional[Dict]:
    """Fetch Bitcoin balance via Mempool.space API."""
    api_url = config.get('api_url', 'https://mempool.space/api')
    address = config.get('address')

    if not address:
        log("Bitcoin address not configured")
        return None

    data = http_get_json(f"{api_url}/address/{address}")

    if not data:
        return None

    chain_stats = data.get('chain_stats', {})
    mempool_stats = data.get('mempool_stats', {})

    # Calculate balance: funded - spent (confirmed + mempool)
    funded = chain_stats.get('funded_txo_sum', 0) + mempool_stats.get('funded_txo_sum', 0)
    spent = chain_stats.get('spent_txo_sum', 0) + mempool_stats.get('spent_txo_sum', 0)
    balance_sats = funded - spent
    balance_btc = balance_sats / 100_000_000  # Convert sats to BTC

    # Get recent transactions
    tx_data = http_get_json(f"{api_url}/address/{address}/txs")
    last_txid = None
    if tx_data and isinstance(tx_data, list) and len(tx_data) > 0:
        last_txid = tx_data[0].get('txid')

    return {
        'balance': balance_btc,
        'last_txid': last_txid,
        'tx_count': chain_stats.get('tx_count', 0),
        'address': address
    }


def detect_changes(current: Dict, previous: Dict) -> List[Dict]:
    """Compare current vs previous state, return list of significant events."""
    events = []

    for chain in ['solana', 'ethereum', 'bitcoin']:
        curr_data = current.get(chain, {})
        prev_data = previous.get(chain, {})

        if not curr_data:
            continue

        curr_bal = curr_data.get('balance', 0)
        prev_bal = prev_data.get('balance', 0)
        delta = curr_bal - prev_bal

        # Skip if below minimum threshold (noise filter)
        min_threshold = MIN_CHANGE_THRESHOLDS.get(chain, 0)
        if abs(delta) < min_threshold:
            continue

        # Calculate USD value of change
        price_usd = APPROX_PRICES_USD.get(chain, 0)
        delta_usd = abs(delta) * price_usd

        events.append({
            'type': 'balance_change',
            'chain': chain,
            'previous_balance': prev_bal,
            'current_balance': curr_bal,
            'delta': delta,
            'delta_usd': round(delta_usd, 2),
            'direction': 'deposit' if delta > 0 else 'withdrawal',
            'address': curr_data.get('address')
        })

        log(f"Detected {chain} balance change: {prev_bal:.8f} -> {curr_bal:.8f} ({'+' if delta > 0 else ''}{delta:.8f}, ~${delta_usd:.2f})")

    return events


def determine_priority(events: List[Dict]) -> str:
    """
    Determine event priority based on significance.
    - Any withdrawal: immediate (need to be aware of outflows)
    - Deposit >= $100: immediate
    - Smaller deposits: normal
    - No events: background
    """
    if not events:
        return 'background'

    for event in events:
        # Any withdrawal is immediate priority
        if event.get('direction') == 'withdrawal':
            return 'immediate'

        # Large deposits are immediate
        if event.get('delta_usd', 0) >= IMMEDIATE_THRESHOLD_USD:
            return 'immediate'

    return 'normal'


def build_prompt(events: List[Dict], wallet_data: Dict) -> str:
    """Build a contextual prompt for Claude based on wallet events."""
    if not events:
        return "Routine wallet check - no significant changes detected."

    lines = ["Wallet activity detected:"]

    for event in events:
        chain = event['chain'].capitalize()
        direction = event['direction']
        delta = event['delta']
        delta_usd = event.get('delta_usd', 0)
        current = event['current_balance']

        symbol = {'solana': 'SOL', 'ethereum': 'ETH', 'bitcoin': 'BTC'}.get(event['chain'], '')

        if direction == 'deposit':
            lines.append(f"- {chain}: Received {abs(delta):.8f} {symbol} (~${delta_usd:.2f}). New balance: {current:.8f} {symbol}")
        else:
            lines.append(f"- {chain}: Sent {abs(delta):.8f} {symbol} (~${delta_usd:.2f}). New balance: {current:.8f} {symbol}")

    lines.append("")
    lines.append("Consider: Should I notify É about this? Log to memory? Any action needed?")

    return '\n'.join(lines)


def write_sense_event(wallet_data: Dict, events: List[Dict], priority: str):
    """Write SenseEvent JSON for Samara to process."""
    os.makedirs(SENSES_DIR, exist_ok=True)

    # Build balances summary
    balances = {}
    addresses = {}
    for chain in ['solana', 'ethereum', 'bitcoin']:
        data = wallet_data.get(chain, {})
        if data:
            balances[chain] = data.get('balance', 0)
            addresses[chain] = data.get('address', '')

    event = {
        "sense": "wallet",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "priority": priority,
        "data": {
            "type": "wallet_update",
            "balances": balances,
            "events": events,
            "addresses": addresses,
            "total_usd_estimate": round(sum(
                balances.get(chain, 0) * APPROX_PRICES_USD.get(chain, 0)
                for chain in balances
            ), 2)
        },
        "context": {
            "suggested_prompt": build_prompt(events, wallet_data)
        },
        "auth": {
            "source_id": "wallet-watcher"
        }
    }

    event_file = os.path.join(SENSES_DIR, 'wallet.event.json')
    with open(event_file, 'w') as f:
        json.dump(event, f, indent=2)

    log(f"Wrote sense event to {event_file} (priority: {priority})")


def main():
    """Main entry point - fetch all chain data, detect changes, write events."""
    log("=" * 50)
    log("Starting wallet watcher...")

    # Load credentials
    creds = load_credentials()
    if not creds:
        log("ERROR: Could not load credentials, exiting")
        sys.exit(1)

    # Load previous state
    previous_state = load_state()
    log(f"Last check: {previous_state.get('last_check', 'never')}")

    # Fetch current data from all chains
    current_data = {}

    log("Fetching Solana balance...")
    sol_data = fetch_solana_balance(creds.get('solana', {}))
    if sol_data:
        current_data['solana'] = sol_data
        log(f"  SOL: {sol_data['balance']:.8f}")

    log("Fetching Ethereum balance...")
    eth_data = fetch_ethereum_balance(creds.get('ethereum', {}))
    if eth_data:
        current_data['ethereum'] = eth_data
        log(f"  ETH: {eth_data['balance']:.8f}")

    log("Fetching Bitcoin balance...")
    btc_data = fetch_bitcoin_balance(creds.get('bitcoin', {}))
    if btc_data:
        current_data['bitcoin'] = btc_data
        log(f"  BTC: {btc_data['balance']:.8f}")

    if not current_data:
        log("ERROR: Could not fetch data from any chain, exiting")
        sys.exit(1)

    # Detect changes
    events = detect_changes(current_data, previous_state)

    # Determine priority and write event if there are changes
    if events:
        priority = determine_priority(events)
        write_sense_event(current_data, events, priority)
        log(f"Detected {len(events)} significant change(s)")
    else:
        log("No significant balance changes detected")

        # Still write a background event periodically so Claude knows wallet status
        # (only if this is the first run or state is being initialized)
        if previous_state.get('last_check') is None:
            write_sense_event(current_data, [], 'background')
            log("First run - wrote initial state event")

    # Save current state
    save_state(current_data)

    # Calculate and log total portfolio value
    total_usd = sum(
        current_data.get(chain, {}).get('balance', 0) * APPROX_PRICES_USD.get(chain, 0)
        for chain in ['solana', 'ethereum', 'bitcoin']
    )
    log(f"Total estimated portfolio value: ${total_usd:,.2f}")

    log("Wallet watcher complete")
    log("=" * 50)


if __name__ == '__main__':
    main()
