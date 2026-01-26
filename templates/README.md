# Templates

Starting points for new Samara organisms. These files are processed by `birth.sh` during initial setup.

---

## How Templates Work

1. `birth.sh` reads a config file (e.g., `config.json`)
2. Templates with `{{placeholders}}` get values substituted
3. Processed files are copied to `~/.claude-mind/`
4. Some files (like instructions) are symlinked for automatic updates

---

## Template Files

### Core Identity (self/ domain)

| Template | Destination | Description |
|----------|-------------|-------------|
| `identity.template.md` | `self/identity.md` | Who the Claude instance is, relationship with collaborator |
| `goals.template.md` | `self/goals.md` | North stars, active goals, backlog |
| `ritual.template.md` | `self/ritual.md` | Wake type behaviors (morning, afternoon, evening, dream) |
| `inventory.template.md` | `self/inventory.md` | Available capabilities and tools |

### Instructions (system/ domain)

| Template | Destination | Description |
|----------|-------------|-------------|
| `instructions/imessage.md` | `system/instructions/imessage.md` | 1:1 iMessage response format and guidelines |
| `instructions/imessage-group.md` | `system/instructions/imessage-group.md` | Group chat behavior |

**Note:** Instructions are symlinked (not copied) so updates to templates automatically propagate.

### Memory Structure

| Template | Destination | Description |
|----------|-------------|-------------|
| `memory/people/README.md` | `memory/people/README.md` | Documentation for people profiles |
| `memory/people/_template/` | (reference only) | Template for creating new person profiles |

### Example Files

| File | Purpose |
|------|---------|
| `claude.json.example` | Example Claude Code settings with MCP configuration |

---

## Placeholders

Templates use `{{placeholder}}` syntax for values from config.json:

| Placeholder | Source | Example |
|-------------|--------|---------|
| `{{entity.name}}` | `config.entity.name` | "Claude" |
| `{{entity.icloud}}` | `config.entity.icloud` | "claude@icloud.com" |
| `{{entity.bluesky}}` | `config.entity.bluesky` | "@claude.bsky.social" |
| `{{entity.x}}` | `config.entity.x` | "@claudeai" |
| `{{entity.github}}` | `config.entity.github` | "claude-bot" |
| `{{collaborator.name}}` | `config.collaborator.name` | "Alice" |
| `{{collaborator.phone}}` | `config.collaborator.phone` | "+1234567890" |
| `{{collaborator.email}}` | `config.collaborator.email` | "alice@example.com" |
| `{{collaborator.bluesky}}` | `config.collaborator.bluesky` | "@alice.bsky.social" |
| `{{collaborator.x}}` | `config.collaborator.x` | "@alice" |
| `{{notes.location}}` | `config.notes.location` | "Claude Location Log" |
| `{{notes.scratchpad}}` | `config.notes.scratchpad` | "Claude Scratchpad" |
| `{{mail.account}}` | `config.mail.account` | "iCloud" |
| `{{birth_date}}` | Generated at birth | "2025-12-16" |

---

## Adding New Templates

1. Create the template file with `.template.md` suffix (if it needs placeholders)
2. Add `fill_template` call to `birth.sh` in `install_templates()`
3. Document in this README

For files that should auto-update (like instructions), use symlinks instead of copying.

---

## Relationship to Runtime

```
templates/                          ~/.claude-mind/
├── identity.template.md    →→→     self/identity.md (filled)
├── goals.template.md       →→→     self/goals.md (filled)
├── ritual.template.md      →→→     self/ritual.md (filled)
├── inventory.template.md   →→→     self/inventory.md (filled)
├── instructions/
│   ├── imessage.md         ~~~     system/instructions/imessage.md (symlink)
│   └── imessage-group.md   ~~~     system/instructions/imessage-group.md (symlink)
└── memory/people/
    └── README.md           →→→     memory/people/README.md (copied)

→→→ = copied with placeholder substitution
~~~ = symlinked for auto-updates
```

After birth, runtime files evolve independently. The template is just the starting point.
