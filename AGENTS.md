# Repository Guidelines

## Project Structure & Module Organization
- `Samara/`: Swift macOS app (Xcode project), with tests in `Samara/SamaraTests/`.
- `scripts/`: Bash automation and operational tooling (symlinked into `~/.claude-mind/bin/`).
- `services/`: Python daemons (webhook/location/etc).
- `cli/`: TypeScript Node wizard (`create-samara`).
- `lib/`: Python helpers; `templates/`: identity/memory scaffolding; `docs/`: design notes; `instructions/`: runtime prompt rules.
- `config.example.json`: config schema example.

## Architecture Overview
- Three-part system: repo "genome" (`~/Developer/samara-main/`), runtime organism state (`~/.claude-mind/`), and signed body app (`/Applications/Samara.app`).
- Core flow: iMessage → `Samara.app` → Claude Code CLI → response to iMessage; logs and memory land in `~/.claude-mind/memory/`.
- Satellite services emit sense events into `~/.claude-mind/senses/`, routed into context by the Swift app.

## Build, Test, and Development Commands
- Bootstrap runtime: `cp config.example.json my-config.json` then `./birth.sh my-config.json` (creates `~/.claude-mind/`).
- App build: open `Samara/Samara.xcodeproj`; signed installs use `~/.claude-mind/bin/update-samara`.
- CLI: `npm --prefix cli run build`, `npm --prefix cli run dev`, `npm --prefix cli start`.
- Services (example): `python3 services/location-receiver/server.py`.

## Coding Style & Naming Conventions
- Swift: 4-space indent, `UpperCamelCase` types, `lowerCamelCase` members.
- TypeScript (`cli/`): 2-space indent, ESM (`type: module`), semicolons.
- Python (`lib/`, `services/`): 4-space indent, `snake_case`.
- Scripts: bash, filenames are kebab-case or bare verbs (`wake`, `dream`); keep executable and update `scripts/README.md` when adding.

## Testing Guidelines
- Swift: `scripts/test-samara` (wraps `xcodebuild -scheme SamaraTests -destination 'platform=macOS' test`); use `--verbose` or `--quick`.
- Node CLI: `npm --prefix cli run build`, then `node --test tests/node/*.mjs`.
- Python services/scripts: `python3 -m unittest discover -s tests/python -p 'test_*.py'`.
- OS integration tests require `SAMARA_INTEGRATION_TESTS=1` plus per-surface flags; Contacts can time out if `contactsd` is stuck—open Contacts, or `tccutil reset AddressBook` then `killall contactsd`.
- HTTP integration tests may be skipped without sockets or FastAPI; enable network and deps to run `tests/python/*_http.py`.

## Commit & Pull Request Guidelines
- Commit subjects are short imperative sentences without scopes (e.g., "Add …").
- PRs should include: summary, tests run (or "not run"), and runtime impact notes (permissions, launchd changes).
- If you change user-facing messaging or templates, include a before/after snippet.

## Security & Configuration Tips
- Never commit real `~/.claude-mind/` data, secrets, or `config.json`; update `config.example.json` and templates instead.
- Runtime state lives outside the repo; `scripts/` are the source of truth for symlinked automation.

## Agent-Specific Instructions
- Read `CLAUDE.md` for operational constraints (FDA persistence, update-samara workflow, privacy guardrails) before modifying core behavior.
