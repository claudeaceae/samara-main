#!/bin/bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Please source this script: source tests/harness/teardown.sh" >&2
  exit 1
fi

if [[ -n "${SAMARA_REAL_HOME:-}" ]]; then
  export HOME="$SAMARA_REAL_HOME"
  unset SAMARA_REAL_HOME
fi

if [[ -n "${SAMARA_REAL_PATH:-}" ]]; then
  export PATH="$SAMARA_REAL_PATH"
  unset SAMARA_REAL_PATH
fi

if [[ -n "${SAMARA_TEST_ROOT:-}" ]]; then
  case "$SAMARA_TEST_ROOT" in
    /tmp/samara-test*|/var/folders/*/*/T/samara-test*|/var/folders/*/*/samara-test*)
      rm -rf "$SAMARA_TEST_ROOT"
      ;;
    *)
      echo "Refusing to remove non-temp SAMARA_TEST_ROOT: $SAMARA_TEST_ROOT" >&2
      ;;
  esac
fi

unset SAMARA_TEST_ROOT SAMARA_MIND_PATH MIND_PATH SAMARA_TEST_LOG_DIR SAMARA_STUB_LOG_FILE
unset SAMARA_TEST_MODE CLAUDE_PATH
