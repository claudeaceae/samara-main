#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/tests/harness/setup.sh"

failures=0

run_test() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name" >&2
    failures=$((failures + 1))
  fi
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if [[ ! -f "$file" ]]; then
    echo "Expected file missing: $file" >&2
    return 1
  fi
  if ! grep -q "$pattern" "$file"; then
    echo "Pattern not found: $pattern" >&2
    return 1
  fi
  return 0
}

assert_output_contains() {
  local output="$1"
  local pattern="$2"
  if [[ "$output" != *"$pattern"* ]]; then
    echo "Output missing pattern: $pattern" >&2
    return 1
  fi
  return 0
}

run_command_capture() {
  local output
  local status
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
  RUN_OUTPUT="$output"
  RUN_STATUS=$status
}

run_message_test() {
  local message="Hello from test"
  OSASCRIPT_BIN=osascript "$REPO_ROOT/scripts/message" "$message"
  assert_file_contains "$SAMARA_MIND_PATH/system/logs/messages-sent.log" "Sent: $message"
}

run_send_attachment_test() {
  local temp_file="$SAMARA_TEST_ROOT/sample.txt"
  echo "fixture" > "$temp_file"

  "$REPO_ROOT/scripts/send-attachment" "$temp_file" "+15555550123"

  assert_file_contains "$SAMARA_MIND_PATH/system/logs/messages-sent.log" "Sent attachment to +15555550123"

  local attachment_dir="$HOME/Pictures/.imessage-send"
  if [[ -d "$attachment_dir" ]]; then
    local remaining
    remaining=$(ls -A "$attachment_dir" | wc -l | tr -d ' ')
    if [[ "$remaining" -ne 0 ]]; then
      echo "Expected attachment dir to be empty, found $remaining files" >&2
      return 1
    fi
  fi
}

run_send_image_test() {
  local temp_file="$SAMARA_TEST_ROOT/image.png"
  echo "fake" > "$temp_file"

  "$REPO_ROOT/scripts/send-image" "$temp_file"

  assert_file_contains "$SAMARA_MIND_PATH/system/logs/messages-sent.log" "Sent attachment to +15555550123"
}

run_scratchpad_first_run_test() {
  local temp_bin="$SAMARA_TEST_ROOT/osascript-bin"
  mkdir -p "$temp_bin"
  cat > "$temp_bin/osascript" <<'EOF'
#!/bin/bash
printf '%s' '<p>Scratchpad content</p>'
EOF
  chmod +x "$temp_bin/osascript"
  local original_path="$PATH"
  PATH="$temp_bin:$PATH"
  rm -f "$SAMARA_MIND_PATH/state/scratchpad-hash.txt"

  run_command_capture "$REPO_ROOT/scripts/check-scratchpad-changed"

  PATH="$original_path"

  if [[ "$RUN_STATUS" -ne 0 ]]; then
    echo "Expected exit 0, got $RUN_STATUS" >&2
    return 1
  fi

  assert_output_contains "$RUN_OUTPUT" "First run - no baseline hash"
  assert_output_contains "$RUN_OUTPUT" "Scratchpad content"
}

run_scratchpad_no_change_test() {
  local temp_bin="$SAMARA_TEST_ROOT/osascript-bin"
  mkdir -p "$temp_bin"
  cat > "$temp_bin/osascript" <<'EOF'
#!/bin/bash
printf '%s' '<p>Scratchpad content</p>'
EOF
  chmod +x "$temp_bin/osascript"
  local original_path="$PATH"
  PATH="$temp_bin:$PATH"
  local content="Scratchpad content"
  local hash
  hash=$(echo "$content" | shasum -a 256 | cut -d' ' -f1)
  echo "$hash" > "$SAMARA_MIND_PATH/state/scratchpad-hash.txt"

  run_command_capture "$REPO_ROOT/scripts/check-scratchpad-changed"

  PATH="$original_path"

  if [[ "$RUN_STATUS" -ne 1 ]]; then
    echo "Expected exit 1, got $RUN_STATUS" >&2
    return 1
  fi

  assert_output_contains "$RUN_OUTPUT" "No external changes detected"
}

run_message_watchdog_check_test() {
  run_command_capture "$REPO_ROOT/scripts/message-watchdog" check

  if [[ "$RUN_STATUS" -ne 0 ]]; then
    echo "Expected exit 0, got $RUN_STATUS" >&2
    return 1
  fi

  assert_file_contains "$SAMARA_MIND_PATH/cache/messages-status.txt" "messages_read=OK"
  assert_file_contains "$SAMARA_MIND_PATH/cache/messages-status.txt" "messages_send=OK"
}

run_check_triggers_blocked_test() {
  mkdir -p "$SAMARA_MIND_PATH/.venv/bin"
  cat > "$SAMARA_MIND_PATH/.venv/bin/activate" <<'EOF'
# test venv stub
EOF
  chmod +x "$SAMARA_MIND_PATH/.venv/bin/activate"

  mkdir -p "$SAMARA_MIND_PATH/state"
  date +%s > "$SAMARA_MIND_PATH/state/last-proactive-trigger.txt"

  run_command_capture "$REPO_ROOT/scripts/check-triggers"

  if [[ "$RUN_STATUS" -ne 0 ]]; then
    echo "Expected exit 0, got $RUN_STATUS" >&2
    return 1
  fi

  assert_file_contains "$SAMARA_MIND_PATH/state/last-evaluation.json" "\"escalation_level\""
  assert_file_contains "$SAMARA_MIND_PATH/system/logs/triggers.log" "Engagement blocked by safeguards"
}

run_proactive_engage_test() {
  mkdir -p "$SAMARA_MIND_PATH/.venv/bin"
  cat > "$SAMARA_MIND_PATH/.venv/bin/activate" <<'EOF'
# test venv stub
EOF
  chmod +x "$SAMARA_MIND_PATH/.venv/bin/activate"

  local message_bin="$SAMARA_MIND_PATH/system/bin/message-e"
  local temp_bin="$SAMARA_TEST_ROOT/claude-bin"
  mkdir -p "$SAMARA_MIND_PATH/system/bin" "$temp_bin"
  cat > "$message_bin" <<'EOF'
#!/bin/bash
set -euo pipefail
MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
mkdir -p "$MIND_PATH/system/logs"
echo "Sent: $*" >> "$MIND_PATH/system/logs/messages-sent.log"
EOF
  chmod +x "$message_bin"
  cat > "$temp_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' 'Proactive run' '---MESSAGE---' 'Hello from proactive'
EOF
  chmod +x "$temp_bin/claude"

  local original_claude="${CLAUDE_PATH-}"
  export CLAUDE_PATH="$temp_bin/claude"
  trap "export CLAUDE_PATH=\"$original_claude\"; rm -f \"$message_bin\" \"$temp_bin/claude\"" RETURN

  run_command_capture "$REPO_ROOT/scripts/proactive-engage" calendar "Meeting soon"

  if [[ "$RUN_STATUS" -ne 0 ]]; then
    echo "Expected exit 0, got $RUN_STATUS" >&2
    return 1
  fi

  assert_file_contains "$SAMARA_MIND_PATH/system/logs/messages-sent.log" "Sent: Hello from proactive"
  assert_file_contains "$SAMARA_MIND_PATH/system/logs/proactive.log" "Message sent successfully"

  local episode_file
  episode_file="$SAMARA_MIND_PATH/memory/episodes/$(date +%Y-%m-%d).md"
  assert_file_contains "$episode_file" "Proactive - calendar"
}

run_test "scripts/message logs" run_message_test
run_test "scripts/send-attachment logs and cleans up" run_send_attachment_test
run_test "scripts/send-image delegates" run_send_image_test
run_test "scripts/check-scratchpad-changed first run" run_scratchpad_first_run_test
run_test "scripts/check-scratchpad-changed no change" run_scratchpad_no_change_test
run_test "scripts/message-watchdog check" run_message_watchdog_check_test
run_test "scripts/check-triggers blocked" run_check_triggers_blocked_test
run_test "scripts/proactive-engage sends message" run_proactive_engage_test

source "$REPO_ROOT/tests/harness/teardown.sh"

if [[ $failures -ne 0 ]]; then
  exit 1
fi
