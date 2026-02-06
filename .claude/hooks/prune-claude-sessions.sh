#!/bin/bash
# Prune and compact Claude Code session files to prevent startup hangs.
# Runs in background (non-blocking) from SessionEnd hook.

MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
HOOK_INPUT=$(cat)

CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty')
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // empty')

# If no cwd, exit quickly
if [ -z "$CWD" ]; then
  echo '{"ok": true}'
  exit 0
fi

PROJECT_KEY="${CWD//\//-}"
PROJECT_DIR="$HOME/.claude/projects/$PROJECT_KEY"
ARCHIVE_ROOT="$HOME/.claude/projects-archive/$PROJECT_KEY"
ARCHIVE_DIR="$ARCHIVE_ROOT/$(date +%Y-%m)"
STAMP_FILE="$ARCHIVE_ROOT/.last-prune"
LOCK_DIR="$HOME/.claude/projects-archive/_locks/prune-${PROJECT_KEY}.lock"

# Defaults (tuned for minimal startup overhead)
export MAX_SESSIONS="${MAX_SESSIONS:-50}"
export MAX_DIR_MB="${MAX_DIR_MB:-80}"
export MAX_SESSION_MB="${MAX_SESSION_MB:-5}"
export MIN_INTERVAL_SEC="${MIN_INTERVAL_SEC:-21600}" # 6h

# Return immediately to Claude Code
echo '{"ok": true}'

(
  mkdir -p "$(dirname "$LOCK_DIR")"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
  fi
  trap 'rmdir "$LOCK_DIR"' EXIT

  [ -d "$PROJECT_DIR" ] || exit 0
  mkdir -p "$ARCHIVE_DIR"

  PROJECT_DIR="$PROJECT_DIR" \
  ARCHIVE_DIR="$ARCHIVE_DIR" \
  TRANSCRIPT_PATH="$TRANSCRIPT_PATH" \
  STAMP_FILE="$STAMP_FILE" \
  MAX_SESSIONS="$MAX_SESSIONS" \
  MAX_DIR_MB="$MAX_DIR_MB" \
  MAX_SESSION_MB="$MAX_SESSION_MB" \
  MIN_INTERVAL_SEC="$MIN_INTERVAL_SEC" \
  python3 - <<'PY'
import json
import os
import shutil
import time
from pathlib import Path

project_dir = Path(os.environ['PROJECT_DIR'])
archive_dir = Path(os.environ['ARCHIVE_DIR'])
transcript_path = os.environ.get('TRANSCRIPT_PATH')
stamp_file = Path(os.environ['STAMP_FILE'])
max_sessions = int(os.environ.get('MAX_SESSIONS', '50'))
max_dir_mb = int(os.environ.get('MAX_DIR_MB', '80'))
max_session_mb = int(os.environ.get('MAX_SESSION_MB', '5'))
min_interval_sec = int(os.environ.get('MIN_INTERVAL_SEC', '21600'))

DROP_TYPES = {'progress', 'file-history-snapshot', 'queue-operation'}
MAX_DEFAULT = 2000
MAX_STDOUT = 1000
STDOUT_KEYS = {'stdout', 'stderr', 'fulloutput', 'output'}


def truncate(s: str, max_len: int):
    if len(s) <= max_len:
        return s, False
    marker = f"\n...[TRUNCATED {len(s)-max_len} chars]...\n"
    keep = max_len - len(marker)
    if keep < 0:
        return s[:max_len], True
    head = keep // 2
    tail = keep - head
    return s[:head] + marker + s[-tail:], True


def compact_file(path: Path):
    # Skip tiny files
    try:
        if path.stat().st_size < 200_000:
            return
    except FileNotFoundError:
        return

    out_lines = []
    changed = False
    with path.open('r', encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
            except Exception:
                out_lines.append(line)
                continue
            t = obj.get('type')
            if t in DROP_TYPES:
                changed = True
                continue

            def walk(val, key=None):
                if isinstance(val, dict):
                    for k, v in list(val.items()):
                        val[k] = walk(v, k)
                    return val
                if isinstance(val, list):
                    return [walk(v, key) for v in val]
                if isinstance(val, str):
                    k = (key or '').lower()
                    max_len = MAX_STDOUT if k in STDOUT_KEYS else MAX_DEFAULT
                    new_val, did = truncate(val, max_len)
                    if did:
                        nonlocal_changed[0] = True
                    return new_val
                return val

            nonlocal_changed = [False]
            obj = walk(obj)
            if nonlocal_changed[0]:
                changed = True
            out_lines.append(json.dumps(obj, ensure_ascii=False) + '\n')

    if changed:
        tmp_path = path.with_suffix(path.suffix + '.tmp')
        with tmp_path.open('w', encoding='utf-8') as f:
            f.writelines(out_lines)
        tmp_path.replace(path)


# 1) Compact current transcript (cheap, only one file)
if transcript_path:
    p = Path(transcript_path)
    if p.exists():
        compact_file(p)


# 2) Decide whether to prune
session_files = [p for p in project_dir.iterdir() if p.is_file() and p.suffix == '.jsonl']
if not session_files:
    stamp_file.parent.mkdir(parents=True, exist_ok=True)
    stamp_file.touch()
    raise SystemExit(0)

now = time.time()
last = stamp_file.stat().st_mtime if stamp_file.exists() else 0
recent = (now - last) < min_interval_sec

sizes = [p.stat().st_size for p in session_files]
count = len(session_files)
total_mb = sum(sizes) / (1024 * 1024)
large_files = [p for p in session_files if p.stat().st_size > max_session_mb * 1024 * 1024]

if recent and count <= max_sessions and total_mb <= max_dir_mb and not large_files:
    raise SystemExit(0)

archive_dir.mkdir(parents=True, exist_ok=True)

# Move sessions-index if present
index_path = project_dir / 'sessions-index.json'
if index_path.exists():
    ts = time.strftime('%Y%m%d-%H%M%S')
    shutil.move(str(index_path), str(archive_dir / f'sessions-index.json.bak-{ts}'))

# First, move large sessions
for p in large_files:
    shutil.move(str(p), str(archive_dir / p.name))
    side_dir = project_dir / p.stem
    if side_dir.exists() and side_dir.is_dir():
        shutil.move(str(side_dir), str(archive_dir / side_dir.name))

# Recompute after moving large ones
session_files = [p for p in project_dir.iterdir() if p.is_file() and p.suffix == '.jsonl']

# Then enforce max_sessions by mtime (newest kept)
if len(session_files) > max_sessions:
    session_files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    keep = set(session_files[:max_sessions])
    for p in session_files[max_sessions:]:
        if p in keep:
            continue
        shutil.move(str(p), str(archive_dir / p.name))
        side_dir = project_dir / p.stem
        if side_dir.exists() and side_dir.is_dir():
            shutil.move(str(side_dir), str(archive_dir / side_dir.name))

stamp_file.parent.mkdir(parents=True, exist_ok=True)
stamp_file.touch()
PY
) >/dev/null 2>&1 &
