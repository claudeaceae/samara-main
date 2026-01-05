---
name: look
description: Capture image from webcam and optionally view or send it. Use when wanting to see surroundings, take a photo, check what's visible, or share a view with collaborator. Trigger words: look, see, webcam, camera, photo, capture, what's around, show me.
---

# Webcam Capture

Use the Logitech C920 webcam to capture what's visible.

## Basic Usage

```bash
# Capture and get path
~/.claude-mind/bin/look
```

This captures an image with 3-second warmup (for exposure adjustment) and prints the path.

## Interactive Workflow

### 1. Capture and View

```bash
IMG=$(~/.claude-mind/bin/look)
```

Then use the Read tool to view the captured image at `$IMG`.

### 2. Capture and Send to Collaborator

```bash
~/.claude-mind/bin/look -s
```

This captures and automatically sends via iMessage.

### 3. Capture with Custom Settings

```bash
# Longer warmup for dark scenes
~/.claude-mind/bin/look -w 5

# Save to specific location
~/.claude-mind/bin/look -o ~/Desktop/webcam-shot.jpg
```

## Options

| Flag | Description |
|------|-------------|
| `-s, --send` | Send to collaborator after capture |
| `-v, --view` | Open in Preview app |
| `-o FILE` | Save to specific path |
| `-w SECS` | Warmup time (default: 3s) |

## Recommended Workflow

When the user asks to see something or share a view:

1. Capture: `IMG=$(~/.claude-mind/bin/look)`
2. View it yourself using Read tool on `$IMG`
3. Describe what you see
4. Ask if they want you to send it

When user explicitly asks you to send/share what you see:

1. Use `~/.claude-mind/bin/look -s` to capture and send in one step

## Notes

- Camera needs 2-4 seconds to adjust exposure
- Currently pointed at window (shows sky/weather)
- Bright scenes may need less warmup
- Dark scenes may need more warmup (5+ seconds)
