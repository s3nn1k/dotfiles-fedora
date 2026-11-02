#!/usr/bin/env bash
set -euo pipefail

position="${1:?usage: herdr-ws-focus <position>}"
workspace_id="$(herdr workspace list | jq -r --argjson position "$position" '.result.workspaces[] | select(.number == $position) | .workspace_id')"
[ -n "$workspace_id" ] || exit 0

exec herdr workspace focus "$workspace_id"
