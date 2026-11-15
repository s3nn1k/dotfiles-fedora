#!/usr/bin/env bash
set -euo pipefail

exit_with_usage() {
  printf 'usage: herdr-ws <focus|move-ws|move-tab|new-tab> [number]
' >&2
  exit 2
}

target_id_is_missing() {
  [[ -z "$1" || "$1" == "null" ]]
}

exit_quietly_when_target_missing() {
  if target_id_is_missing "$1"; then
    exit 0
  fi
}

if (( $# > 2 )); then
  exit_with_usage
fi

action="${1:-}"
number="${2:-}"

case "$action" in
  focus | move-ws | move-tab)
    [[ "$number" =~ ^[1-9][0-9]*$ ]] || exit_with_usage
    ;;
  new-tab)
    [[ -z "$number" ]] || exit_with_usage
    ;;
  *)
    exit_with_usage
    ;;
esac

case "$action" in
  focus)
    workspace_id="$(herdr workspace list | jq -r --argjson number "$number" \
      '.result.workspaces | sort_by(.number) | .[$number - 1].workspace_id')"
    exit_quietly_when_target_missing "$workspace_id"
    exec herdr workspace focus "$workspace_id"
    ;;
  move-ws)
    pane_id="$(herdr pane list | jq -r 'first(.result.panes[] | select(.focused)).pane_id')"
    exit_quietly_when_target_missing "$pane_id"
    workspace_id="$(herdr workspace list | jq -r --argjson number "$number" \
      '.result.workspaces | sort_by(.number) | .[$number - 1].workspace_id')"
    if target_id_is_missing "$workspace_id"; then
      exec herdr pane move "$pane_id" --new-workspace --focus
    fi
    exec herdr pane move "$pane_id" --new-tab --workspace "$workspace_id" --focus
    ;;
  move-tab)
    pane_id="$(herdr pane list | jq -r 'first(.result.panes[] | select(.focused)).pane_id')"
    exit_quietly_when_target_missing "$pane_id"
    pane_workspace_id="$(herdr pane list | jq -r --arg pane_id "$pane_id" \
      'first(.result.panes[] | select(.pane_id == $pane_id)).workspace_id')"
    tab_id="$(herdr tab list | jq -r --arg workspace_id "$pane_workspace_id" --argjson number "$number" \
      '.result.tabs | map(select(.workspace_id == $workspace_id)) | sort_by(.number) | .[$number - 1].tab_id')"
    if target_id_is_missing "$tab_id"; then
      exec herdr pane move "$pane_id" --new-tab --focus
    fi
    exec herdr pane move "$pane_id" --tab "$tab_id" --split right --focus
    ;;
  new-tab)
    pane_id="$(herdr pane list | jq -r 'first(.result.panes[] | select(.focused)).pane_id')"
    exit_quietly_when_target_missing "$pane_id"
    exec herdr pane move "$pane_id" --new-tab --focus
    ;;
esac
