# /speak - Voice Note Generation

Generate and send voice notes using text-to-speech.

## Usage

```
/speak "message text" [--send chat_id]
```

## What This Does

Converts text to speech using ElevenLabs and optionally sends it as a voice note.

## Implementation

When the user invokes /speak:

1. If text is provided, generate audio from it
2. If --send is specified, send as iMessage attachment
3. Otherwise just generate and save locally

**Script location:** `~/.claude-mind/bin/speak`

**Examples:**

```bash
# Generate voice note and send to É
~/.claude-mind/bin/speak "Good morning! How's your day going?" --send +15206099095

# Just generate audio file
~/.claude-mind/bin/speak "Test message" --output ~/Desktop/test.mp3

# List available voices
~/.claude-mind/bin/speak --list-voices
```

## Voice Configuration

Default voice can be set in `~/.claude-mind/state/voice-config.json`:

```json
{
  "default_voice_id": "21m00Tcm4TlvDq8ikWAM"
}
```

## Requirements

- ElevenLabs API key in `~/.claude-mind/credentials/elevenlabs.txt`
- Get one at: https://elevenlabs.io/api
