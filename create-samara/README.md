# create-samara CLI

Interactive setup wizard for birthing a new Samara organism.

---

## Overview

This CLI guides you through the complete setup process:

1. **Welcome** — Introduction and prerequisites check
2. **Identity** — Configure Claude's name, iCloud, social handles
3. **Collaborator** — Configure your contact info
4. **Integrations** — Optional services (Bluesky, GitHub, wallet, etc.)
5. **Birth** — Run birth.sh to create ~/.claude-mind
6. **App** — Build and install Samara.app
7. **Permissions** — Grant Full Disk Access, Automation
8. **Launchd** — Install wake/dream cycles
9. **Credentials** — Set up API keys and tokens
10. **Launch** — Start Samara.app
11. **Summary** — Verify everything is working

---

## Usage

### From the repo (recommended)

```bash
cd ~/Developer/samara-main/create-samara
npm install
npm run build
node dist/index.js
```

Or run directly if already built:

```bash
node ~/Developer/samara-main/create-samara/dist/index.js
```

### Via npx (once published)

```bash
npx create-samara
```

> **Note:** The package is not yet published to npm. Use the local method above.

---

## Features

- **Resumable** — Progress is saved; restart anytime to continue
- **Validation** — Inputs are validated before proceeding
- **Prerequisites** — Checks for Xcode, Homebrew, jq, etc.
- **Guided permissions** — Walks through FDA, Automation grants

---

## Development

```bash
# Install dependencies
npm install

# Build
npm run build

# Watch mode
npm run dev

# Run locally
npm start
```

---

## State

Setup state is saved to allow resuming:

- Location: `~/.config/create-samara/config.json`
- Contains: Completed steps, configuration values

To start fresh, delete the config file or decline resume when prompted.

---

## Publishing (for maintainers)

```bash
cd create-samara
npm run build
npm publish
```

After publishing, users can run:
```bash
npx create-samara
```
