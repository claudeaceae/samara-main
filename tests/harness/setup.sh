#!/bin/bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Please source this script: source tests/harness/setup.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="$SCRIPT_DIR/../fixtures/claude-mind"

export SAMARA_REAL_HOME="${SAMARA_REAL_HOME:-$HOME}"
export SAMARA_REAL_PATH="${SAMARA_REAL_PATH:-$PATH}"

export SAMARA_TEST_ROOT="${SAMARA_TEST_ROOT:-$(mktemp -d -t samara-test)}"
export HOME="$SAMARA_TEST_ROOT"
export SAMARA_MIND_PATH="${SAMARA_MIND_PATH:-$SAMARA_TEST_ROOT/.claude-mind}"
export MIND_PATH="$SAMARA_MIND_PATH"
export SAMARA_TEST_LOG_DIR="${SAMARA_TEST_LOG_DIR:-$SAMARA_TEST_ROOT/logs}"
export SAMARA_STUB_LOG_FILE="${SAMARA_STUB_LOG_FILE:-$SAMARA_TEST_LOG_DIR/stub-commands.log}"
export SAMARA_TEST_MODE=1
export CLAUDE_PATH="${CLAUDE_PATH:-$SCRIPT_DIR/stubs/claude}"

export PATH="$SCRIPT_DIR/stubs:$PATH"

mkdir -p "$SAMARA_TEST_LOG_DIR"
mkdir -p "$SAMARA_MIND_PATH"

if [[ -d "$FIXTURE_DIR" ]]; then
  cp -R "$FIXTURE_DIR/." "$SAMARA_MIND_PATH/"
fi

if [[ ! -e "$SAMARA_MIND_PATH/system/bin" ]]; then
  ln -s "$SCRIPT_DIR/../../scripts" "$SAMARA_MIND_PATH/system/bin"
fi

if [[ ! -e "$SAMARA_MIND_PATH/lib" ]]; then
  ln -s "$SCRIPT_DIR/../../lib" "$SAMARA_MIND_PATH/lib"
fi

echo "SAMARA_TEST_ROOT=$SAMARA_TEST_ROOT"
echo "SAMARA_MIND_PATH=$SAMARA_MIND_PATH"
echo "SAMARA_STUB_LOG_FILE=$SAMARA_STUB_LOG_FILE"
