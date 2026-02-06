# /voice-call - FaceTime Voice Calling

Place and receive FaceTime Audio calls with live transcription and voice/text responses.

## Quick Start

```bash
# Full voice conversation (responds via FaceTime audio)
~/.claude-mind/system/bin/voice-call --voice-response

# Call with text responses (via iMessage)
~/.claude-mind/system/bin/voice-call --text-response

# Call a specific number
~/.claude-mind/system/bin/voice-call +15551234567 --voice-response
```

## Prerequisites

Run `audio-setup --check` to verify:
- **sox** — audio recording and playback
- **SwitchAudioSource** — audio device routing
- **whisper-cli** — speech-to-text transcription
- **Loopback** — virtual audio device routing (must be running)
- **Claude Mic** — virtual device for TTS → FaceTime input
- **Call Capture** — virtual device for FaceTime output → recording
- **aggregate-device** — Swift tool for creating CoreAudio aggregate devices

## Scripts

| Script | Purpose |
|--------|---------|
| `voice-call` | High-level orchestrator (setup → call → listen → respond → teardown) |
| `facetime` | FaceTime control (open/close/status/call/answer/hangup) |
| `facetime-incoming-watcher` | Polls for incoming calls, auto-answers collaborator |
| `call-record` | Aggregate device management + sox recording |
| `call-transcribe` | Whisper transcription of WAV files |
| `call-listen` | Recording + transcription + response loop |
| `call-speak` | Play TTS audio to "Claude Mic" device |
| `audio-setup` | Verify/configure audio prerequisites |
| `aggregate-device` | Create/destroy CoreAudio aggregate devices |

## Options

```
voice-call [target] [options]

  --text-response    Respond via iMessage (default)
  --voice-response   Respond with TTS through FaceTime
  --greeting TEXT    Custom greeting when call connects
  --no-greeting      Skip initial greeting
  --timeout SECS     Max call duration (default: 600)
  --answer           Answer mode (incoming call, skip dialing)
```

## How It Works

1. **Aggregate device**: Creates a CoreAudio multi-output device ("Call Monitor") combining physical speakers + Call Capture. On macOS 26, FaceTime call audio routes through the system default output — a pure virtual device receives silence, but an aggregate containing physical speakers gets call audio on ALL sub-devices.
2. **Timing**: The aggregate device MUST be set as system output BEFORE the FaceTime call connects. Audio routing is locked at connection time.
3. **Call initiation**: Uses AppleScript UI automation (New → type number → switch dropdown to Audio → Return). The `facetime-audio://` URL scheme only shows a notification on macOS 26+, not an actual call.
4. **Hangup**: Clicks NotificationCenter's "End" button. On macOS 26, calls persist as system-level calls even after quitting FaceTime.
5. **Recording**: sox `rec` with 35dB gain amplification + 0.1% silence threshold. Call audio from the aggregate device is very low amplitude; gain boost is required for silence detection.
6. **Transcription**: whisper-cpp batch mode on each WAV chunk (48kHz stereo → 16kHz mono conversion).
7. **Turn-taking**: Silence-based (1.5s threshold). Recording pauses during TTS playback to avoid self-echo.
8. **Exit detection**: Recognizes "goodbye", "hang up", "end call", "bye bye", "talk to you later".

## Lifecycle

### Outgoing Call
```
call-record setup     →  Create aggregate device, set system output
facetime call         →  UI automation dials FaceTime Audio
call-speak greeting   →  TTS greeting through Claude Mic
call-record start     →  Begin sox recording from Call Capture
  ↕ call-listen loop: record → transcribe → respond → pause/resume
call-record stop      →  Stop sox recording
call-record teardown  →  Destroy aggregate, restore audio devices
facetime hangup       →  Click NotificationCenter End button
```

### Incoming Call (auto-answer)
```
facetime-incoming-watcher  →  Polls NotificationCenter every 5s
  detect Accept/Decline    →  Incoming call found
  identify caller          →  Match against collaborator name/phone
  call-record setup        →  Create aggregate device (before accepting!)
  facetime answer          →  Click Accept + set audio devices
  voice-call --answer      →  Greeting → call-listen loop → cleanup
```

The watcher runs as a launchd service (`com.claude.facetime-incoming`). It auto-answers calls from the collaborator (~2-3s pickup) and lets unknown callers ring.

## Configuration

Stored at `~/.claude-mind/state/voice-call-config.json`:

```json
{
  "micDevice": "Claude Mic",
  "captureDevice": "Call Capture",
  "whisperModel": "~/.claude-mind/system/models/ggml-base.en.bin",
  "sampleRate": 16000,
  "silenceThreshold": 1.0,
  "silenceLevel": "0.1%",
  "callGain": 35
}
```

- `silenceThreshold` — seconds of silence before splitting chunks (default: 1.5)
- `silenceLevel` — amplitude threshold for silence detection (default: 0.1%)
- `callGain` — dB gain applied before silence detection (default: 35)

## Service Toggle

```bash
service-toggle voiceCall on|off|status
```

## Trigger Words

Use `/voice-call` or natural phrases like "call me", "FaceTime me", "let's talk on the phone".
