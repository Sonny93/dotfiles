#!/usr/bin/env bash
# Tests of ring-bell.sh: pipes hook JSON into the script and asserts on its stdout.
# Usage: ring-bell.test.sh
#   prints `ok <name>` or `FAIL <name>: <detail>` per test and a summary line; exits 1 when a test failed

set -uo pipefail

HOOKS_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOOKS_DIRECTORY
readonly RING_BELL_SCRIPT="$HOOKS_DIRECTORY/ring-bell.sh"
readonly BELL=$'\a'

passed_count=0
failed_count=0

run_hook() {
    bash "$RING_BELL_SCRIPT" <<<"$1"
}

expect_ring() {
    local output sequence
    output=$(run_hook "$1") || { echo "script failed"; return; }
    sequence=$(jq -j '.terminalSequence' <<<"$output" 2>/dev/null; echo x)
    [[ "$sequence" == "${BELL}x" ]] || echo "expected a single BEL, got [$output]"
}

expect_silence() {
    local output
    output=$(run_hook "$1") || { echo "script failed"; return; }
    [[ -z "$output" ]] || echo "expected no output, got [$output]"
}

should_ring_when_stop_has_no_pending_fields() {
    expect_ring '{"hook_event_name":"Stop"}'
}

should_ring_when_stop_has_empty_arrays() {
    expect_ring '{"hook_event_name":"Stop","background_tasks":[],"session_crons":[]}'
}

should_stay_silent_when_stop_has_a_running_shell_task() {
    expect_silence '{"hook_event_name":"Stop","background_tasks":[{"type":"shell","id":"b1"}],"session_crons":[]}'
}

should_stay_silent_when_stop_has_a_session_cron() {
    expect_silence '{"hook_event_name":"Stop","background_tasks":[],"session_crons":[{"id":"c1"}]}'
}

should_ring_when_stop_failure() {
    expect_ring '{"hook_event_name":"StopFailure"}'
}

should_ring_when_notification_is_a_permission_prompt() {
    expect_ring '{"hook_event_name":"Notification","notification_type":"permission_prompt"}'
}

should_stay_silent_when_notification_is_idle_prompt() {
    expect_silence '{"hook_event_name":"Notification","notification_type":"idle_prompt"}'
}

should_stay_silent_when_event_is_unrelated() {
    expect_silence '{"hook_event_name":"PreToolUse"}'
}

run_test() {
    local test_name="$1" failure
    failure=$("$test_name")
    if [[ -n "$failure" ]]; then
        echo "FAIL $test_name: $failure"
        failed_count=$((failed_count + 1))
        return
    fi
    echo "ok $test_name"
    passed_count=$((passed_count + 1))
}

main() {
    local test_name
    while IFS= read -r test_name; do
        run_test "$test_name"
    done < <(declare -F | awk '$3 ~ /^should_/ { print $3 }')
    echo "$passed_count passed, $failed_count failed"
    [[ "$failed_count" -eq 0 ]]
}

main
