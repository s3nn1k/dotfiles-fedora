#!/usr/bin/env bash
set -euo pipefail

script_under_test="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/herdr-ws.sh"

usage_line="usage: herdr-ws <focus|move-ws|move-tab|new-tab> [number]"
failures=0

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fixtures="$tmpdir/fixtures"
call_log="$tmpdir/call.log"
run_stdout="$tmpdir/run.stdout"
run_stderr="$tmpdir/run.stderr"
run_exit_code=unset
mkdir -p "$fixtures"
: >"$call_log"

export HERDR_WS_TEST_FIXTURES="$fixtures"
export HERDR_WS_TEST_CALL_LOG="$call_log"

cat >"$tmpdir/herdr" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  "pane list") cat "$HERDR_WS_TEST_FIXTURES/panes.json" ;;
  "tab list") cat "$HERDR_WS_TEST_FIXTURES/tabs.json" ;;
  "workspace list") cat "$HERDR_WS_TEST_FIXTURES/workspaces.json" ;;
  *)
    printf '%s
' "$*" >>"$HERDR_WS_TEST_CALL_LOG"
    ;;
esac
STUB
chmod +x "$tmpdir/herdr"

cat >"$fixtures/workspaces.json" <<'JSON'
{"result":{"workspaces":[{"workspace_id":"ws-alpha","number":1,"label":"alpha"},{"workspace_id":"ws-beta","number":2,"label":"beta"}]}}
JSON

cat >"$fixtures/tabs.json" <<'JSON'
{"result":{"tabs":[{"tab_id":"ws-alpha:t1","workspace_id":"ws-alpha","number":1},{"tab_id":"ws-beta:t2","workspace_id":"ws-beta","number":2},{"tab_id":"ws-alpha:t6","workspace_id":"ws-alpha","number":6},{"tab_id":"ws-alpha:t4","workspace_id":"ws-alpha","number":4}]}}
JSON

write_panes_fixture() {
  printf '{"result":{"panes":[{"pane_id":"ws-alpha:p1","focused":%s,"tab_id":"ws-alpha:t1","workspace_id":"ws-alpha"}]}}
' "$1" >"$fixtures/panes.json"
}

run_herdr_ws() {
  : >"$call_log"
  set +e
  PATH="$tmpdir:$PATH" "$script_under_test" "$@" >"$run_stdout" 2>"$run_stderr"
  run_exit_code=$?
  set -e
}

assert_equals() {
  local expected="$1" actual="$2" description="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf 'ok: %s
' "$description"
  else
    printf 'FAIL: %s
  expected: [%s]
  actual:   [%s]
' "$description" "$expected" "$actual" >&2
    failures=$((failures + 1))
  fi
}

assert_file_empty() {
  local path="$1" description="$2"
  if [[ -s "$path" ]]; then
    printf 'FAIL: %s: expected empty file, got [%s]
' "$description" "$(cat "$path")" >&2
    failures=$((failures + 1))
  else
    printf 'ok: %s
' "$description"
  fi
}

assert_call_log() {
  assert_equals "$1" "$(cat "$call_log")" "$2"
}

assert_usage_rejection() {
  local description="$1"
  shift
  run_herdr_ws "$@"
  assert_equals "2" "$run_exit_code" "$description: exit 2"
  assert_equals "$usage_line" "$(cat "$run_stderr")" "$description: usage written to stderr"
}

assert_quiet_success() {
  assert_equals "0" "$run_exit_code" "$1: exit 0"
  assert_file_empty "$call_log" "$1: no herdr state calls"
  assert_file_empty "$run_stdout" "$1: stdout silent"
  assert_file_empty "$run_stderr" "$1: stderr silent"
}

write_panes_fixture true

assert_usage_rejection "no arguments"
assert_usage_rejection "move-ws without number" move-ws
assert_usage_rejection "move-ws abc" move-ws abc
assert_usage_rejection "move-ws 0" move-ws 0
assert_usage_rejection "move-ws 007" move-ws 007
assert_usage_rejection "new-tab with stray number" new-tab 1
assert_usage_rejection "focus with extra argument" focus 1 2

run_herdr_ws focus 2
assert_equals "0" "$run_exit_code" "focus 2: exit 0"
assert_call_log "workspace focus ws-beta" "focus 2: focuses workspace at second position"

run_herdr_ws focus 9
assert_quiet_success "focus 9 beyond workspaces"

run_herdr_ws move-ws 1
assert_equals "0" "$run_exit_code" "move-ws 1: exit 0"
assert_call_log "pane move ws-alpha:p1 --workspace ws-alpha --focus" "move-ws 1: moves focused pane to first-position workspace"

run_herdr_ws move-ws 5
assert_equals "0" "$run_exit_code" "move-ws 5 beyond workspaces: exit 0"
assert_call_log "pane move ws-alpha:p1 --new-workspace --focus" "move-ws 5 beyond workspaces: moves pane into new workspace at tail"

run_herdr_ws move-tab 3
assert_equals "0" "$run_exit_code" "move-tab 3: exit 0"
assert_call_log "pane move ws-alpha:p1 --tab ws-alpha:t6 --focus" "move-tab 3: moves focused pane to third-position tab sorted by number"

run_herdr_ws move-tab 9
assert_equals "0" "$run_exit_code" "move-tab 9 beyond tabs: exit 0"
assert_call_log "pane move ws-alpha:p1 --new-tab --focus" "move-tab 9 beyond tabs: moves pane into new tab"

run_herdr_ws new-tab
assert_equals "0" "$run_exit_code" "new-tab: exit 0"
assert_call_log "pane move ws-alpha:p1 --new-tab --focus" "new-tab: moves focused pane into new tab"

write_panes_fixture false
run_herdr_ws move-tab 1
assert_quiet_success "move-tab without focused pane"

if (( failures > 0 )); then
  printf '%d assertion(s) failed
' "$failures" >&2
  exit 1
fi
printf 'all herdr-ws tests passed
'
