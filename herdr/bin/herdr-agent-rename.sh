#!/usr/bin/env bash
set -euo pipefail

name_pattern='^[a-z][a-z0-9_-]{0,31}$'

close_on_enter() {
  printf 'press Enter to close
' >&2
  read -r _discard || true
}

fail() {
  printf 'herdr-agent-rename: %s
' "$1" >&2
  close_on_enter
  exit 1
}

pane_json="$(herdr pane current 2>&1)" || fail "herdr pane current: $pane_json"
pane_id="$(printf '%s' "$pane_json" | jq -r '.result.pane.pane_id // empty')"
[ -n "$pane_id" ] || fail "no pane id in herdr pane current output"

agent_json="$(herdr agent get "$pane_id" 2>&1)" || fail "herdr agent get: $agent_json"
current_name="$(printf '%s' "$agent_json" | jq -r '.result.agent.name // empty')"

if [[ -n "$current_name" ]]; then
  printf 'agent name (current: %s, empty clears): ' "$current_name" >&2
else
  printf 'agent name (empty clears): ' >&2
fi

read -r new_name || fail "stdin is closed, run from a terminal pane"

if [[ -z "$new_name" ]]; then
  herdr agent rename "$pane_id" --clear >/dev/null || fail "herdr agent rename --clear failed"
  printf 'name cleared
' >&2
else
  [[ "$new_name" =~ $name_pattern ]] || fail "invalid name, must match $name_pattern"
  herdr agent rename "$pane_id" "$new_name" >/dev/null || fail "herdr agent rename failed"
  printf 'renamed to %s
' "$new_name" >&2
fi

close_on_enter
