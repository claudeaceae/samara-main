#!/bin/bash
set -euo pipefail

cmd_name="$(basename "$0")"
cmd_key="$(echo "$cmd_name" | tr '[:lower:]' '[:upper:]')"
cmd_key="${cmd_key//-/_}"

log_file="${SAMARA_STUB_LOG_FILE:-${SAMARA_TEST_LOG_DIR:-/tmp}/stub-commands.log}"
mkdir -p "$(dirname "$log_file")"

printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$cmd_name" "$*" >> "$log_file"

stdout_var="SAMARA_STUB_STDOUT_${cmd_key}"
stderr_var="SAMARA_STUB_STDERR_${cmd_key}"
exit_var="SAMARA_STUB_EXIT_CODE_${cmd_key}"

if [[ -n "${!stdout_var:-}" ]]; then
  printf "%b" "${!stdout_var}"
fi

if [[ -n "${!stderr_var:-}" ]]; then
  printf "%b" "${!stderr_var}" >&2
fi

if [[ -n "${!exit_var:-}" ]]; then
  exit "${!exit_var}"
fi

if [[ "$cmd_name" == "pgrep" ]]; then
  exit 1
fi

exit 0
