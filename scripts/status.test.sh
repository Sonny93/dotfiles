#!/usr/bin/env bash
# Tests of the quiet-step helpers of status.sh (run_quiet_step, run_visible_step, warn, report_line, print_report_summary).
# Usage: status.test.sh
#   prints `ok <name>` or `FAIL <name>: <detail>` per test and a summary line; exits 1 when a test failed
# Isolation: logs and reports live in a mktemp -d sandbox removed on exit; nothing touches the system or the network.

set -uo pipefail

SCRIPT_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
SANDBOX="$(mktemp -d)"
readonly SANDBOX
trap 'rm -rf "$SANDBOX"' EXIT

# shellcheck source=status.sh
# shellcheck source-path=SCRIPTDIR
source "$SCRIPT_DIRECTORY/status.sh"

passed_count=0
failed_count=0

report() {
    local name="$1" detail="$2"
    if [[ -z "$detail" ]]; then
        echo "ok $name"
        passed_count=$((passed_count + 1))
        return
    fi
    echo "FAIL $name: $detail"
    failed_count=$((failed_count + 1))
}

reset_files() {
    : >"$SANDBOX/run.log"
    : >"$SANDBOX/run.report"
    export UPDATE_LOG="$SANDBOX/run.log" UPDATE_REPORT="$SANDBOX/run.report"
    unset UPDATE_STEP_TIMEOUT
}

test_quiet_step_success() {
    local detail="" output step_status=0
    reset_files
    output="$(run_quiet_step "Build" sh -c 'echo compiling; echo "warning: noisy"' 2>&1)" || step_status=$?
    [[ "$step_status" == 0 ]] || detail="status $step_status"
    [[ "$output" == "✓ Build" ]] || detail="$detail output [$output]"
    grep -q '^==== Build ====$' "$UPDATE_LOG" || detail="$detail header missing"
    grep -q '^compiling$' "$UPDATE_LOG" || detail="$detail output not logged"
    [[ ! -s "$UPDATE_REPORT" ]] || detail="$detail report [$(cat "$UPDATE_REPORT")]"
    report "should print one check line and log the output when a quiet step succeeds" "$detail"
}

test_quiet_step_failure() {
    local detail="" output step_status=0
    reset_files
    output="$(run_quiet_step "Install" sh -c 'echo harmless; echo "fatal: disk full"; exit 3' 2>&1)" || step_status=$?
    [[ "$step_status" == 3 ]] || detail="status $step_status"
    [[ "$output" == "✗ Install"* ]] || detail="$detail output [$output]"
    [[ "$output" == *"fatal: disk full"* ]] || detail="$detail reason missing"
    [[ "$output" != *"harmless"* ]] || detail="$detail unrelated line shown"
    [[ "$output" == *"log: $UPDATE_LOG"* ]] || detail="$detail log path missing"
    [[ "$(cat "$UPDATE_REPORT")" == "ERROR Install" ]] || detail="$detail report [$(cat "$UPDATE_REPORT")]"
    report "should print the failure reason, the log path and report an ERROR when a quiet step fails" "$detail"
}

test_quiet_step_failure_without_match_shows_tail() {
    local detail="" output
    reset_files
    output="$(run_quiet_step "Plain" sh -c 'echo first; echo last; exit 1' 2>&1)" || true
    [[ "$output" == *"last"* ]] || detail="output [$output]"
    report "should show the last output lines when no line looks like an error" "$detail"
}

test_quiet_step_only_shows_its_own_output() {
    local detail="" output
    reset_files
    echo "error: from an earlier step" >>"$UPDATE_LOG"
    output="$(run_quiet_step "Later" sh -c 'echo oops; exit 1' 2>&1)" || true
    [[ "$output" != *"earlier step"* ]] || detail="output [$output]"
    report "should not show output of earlier steps in a failure excerpt" "$detail"
}

test_quiet_step_closes_stdin() {
    local detail=""
    reset_files
    run_quiet_step "Prompt" sh -c 'if read -r answer; then echo "got $answer"; else echo "end of input"; fi' <<<"typed" >/dev/null 2>&1
    grep -q '^end of input$' "$UPDATE_LOG" || detail="log [$(cat "$UPDATE_LOG")]"
    report "should run a quiet step with stdin closed so nothing waits for input" "$detail"
}

test_quiet_step_times_out() {
    local detail="" step_status=0
    reset_files
    UPDATE_STEP_TIMEOUT=1 run_quiet_step "Slow" sleep 5 >/dev/null 2>&1 || step_status=$?
    [[ "$step_status" == 124 ]] || detail="status $step_status"
    report "should stop a quiet step that exceeds UPDATE_STEP_TIMEOUT" "$detail"
}

test_quiet_step_without_log_runs_verbose() {
    local detail="" output step_status=0
    reset_files
    unset UPDATE_LOG
    output="$(run_quiet_step "Plain" sh -c 'echo visible; exit 4' 2>&1)" || step_status=$?
    [[ "$step_status" == 4 ]] || detail="status $step_status"
    [[ "$output" == *"Plain"* && "$output" == *"visible"* ]] || detail="$detail output [$output]"
    [[ "$(cat "$UPDATE_REPORT")" == "ERROR Plain" ]] || detail="$detail report [$(cat "$UPDATE_REPORT")]"
    report "should print the header and the command output when UPDATE_LOG is unset" "$detail"
}

test_visible_step_reports_failure() {
    local detail="" output step_status=0
    reset_files
    output="$(run_visible_step "Ask" sh -c 'echo asked; exit 2' 2>&1)" || step_status=$?
    [[ "$step_status" == 2 ]] || detail="status $step_status"
    [[ "$output" == *"asked"* && "$output" == *"✗ Ask"* ]] || detail="$detail output [$output]"
    [[ "$(cat "$UPDATE_REPORT")" == "ERROR Ask" ]] || detail="$detail report [$(cat "$UPDATE_REPORT")]"
    grep -q '^==== Ask ====$' "$UPDATE_LOG" || detail="$detail header missing from the log"
    report "should run a visible step on the terminal and report an ERROR when it fails" "$detail"
}

test_warn_appends_to_report() {
    local detail=""
    reset_files
    warn "something odd" >/dev/null
    [[ "$(cat "$UPDATE_REPORT")" == "WARN something odd" ]] || detail="report [$(cat "$UPDATE_REPORT")]"
    report "should append a WARN line to the report when UPDATE_REPORT is set" "$detail"
}

test_warn_without_report_prints_only() {
    local detail="" output
    reset_files
    unset UPDATE_REPORT
    output="$(warn "something odd")"
    [[ "$output" == *"WARN: something odd"* ]] || detail="output [$output]"
    [[ ! -s "$SANDBOX/run.report" ]] || detail="$detail report written"
    report "should only print the warning when UPDATE_REPORT is unset" "$detail"
}

test_report_line_without_report_is_noop() {
    local detail="" line_status=0
    reset_files
    unset UPDATE_REPORT
    report_line REBOOT "kernel" || line_status=$?
    [[ "$line_status" == 0 ]] || detail="status $line_status"
    report "should do nothing and succeed when report_line runs without UPDATE_REPORT" "$detail"
}

test_summary_with_error_fails() {
    local detail="" output summary_status=0
    reset_files
    printf 'WARN a pacnew\nERROR Install\nREBOOT kernel\n' >"$UPDATE_REPORT"
    output="$(print_report_summary)" || summary_status=$?
    [[ "$summary_status" == 1 ]] || detail="status $summary_status"
    [[ "$output" == *"1 WARN, 1 ERROR, 1 REBOOT"* ]] || detail="$detail counts [$output]"
    [[ "$output" == *"ERROR Install"* && "$output" == *"log: $UPDATE_LOG"* ]] || detail="$detail lines [$output]"
    report "should list the report lines and fail when the report holds an ERROR" "$detail"
}

test_summary_clean_report_is_silent() {
    local detail="" output summary_status=0
    reset_files
    output="$(print_report_summary)" || summary_status=$?
    [[ "$summary_status" == 0 && -z "$output" ]] || detail="status $summary_status output [$output]"
    printf 'WARN only a warning\n' >"$UPDATE_REPORT"
    print_report_summary >/dev/null || detail="$detail warning alone failed"
    report "should print nothing for an empty report and succeed with only warnings" "$detail"
}

test_quiet_step_has_no_controlling_session() {
    local detail="" own_session step_session
    reset_files
    own_session="$(ps -o sid= -p $$ | tr -d ' ')"
    run_quiet_step "Session" sh -c 'ps -o sid= -p $$' >/dev/null 2>&1
    step_session="$(tr -d ' \n' <"$UPDATE_LOG" | sed 's/^====Session====//')"
    [[ -n "$step_session" && "$step_session" != "$own_session" ]] || detail="own [$own_session] step [$step_session]"
    report "should run a quiet step in its own session so the tty sudo ticket is unusable" "$detail"
}

test_quiet_root_step_keeps_the_session() {
    local detail="" own_session step_session output step_status=0
    reset_files
    own_session="$(ps -o sid= -p $$ | tr -d ' ')"
    output="$(run_quiet_root_step "Root" sh -c 'ps -o sid= -p $$' 2>&1)" || step_status=$?
    step_session="$(tr -d ' \n' <"$UPDATE_LOG" | sed 's/^====Root====//')"
    [[ "$step_session" == "$own_session" ]] || detail="own [$own_session] step [$step_session]"
    [[ "$output" == "✓ Root" && "$step_status" == 0 ]] || detail="$detail output [$output]"
    report "should keep the session of a quiet root step so sudo can use its cached ticket" "$detail"
}

test_quiet_root_step_failure_is_reported() {
    local detail="" output step_status=0
    reset_files
    output="$(run_quiet_root_step "Root" sh -c 'echo "error: nope"; exit 5' 2>&1)" || step_status=$?
    [[ "$step_status" == 5 && "$output" == "✗ Root"* && "$output" == *"error: nope"* ]] || detail="status $step_status output [$output]"
    [[ "$(cat "$UPDATE_REPORT")" == "ERROR Root" ]] || detail="$detail report [$(cat "$UPDATE_REPORT")]"
    report "should report an ERROR when a quiet root step fails" "$detail"
}

test_step_timeout_override_order() {
    local detail=""
    reset_files
    [[ "$(resolve_step_timeout)" == 600 ]] || detail="default [$(resolve_step_timeout)]"
    [[ "$(STEP_TIMEOUT_SECONDS=1800 resolve_step_timeout)" == 1800 ]] || detail="$detail per call"
    [[ "$(UPDATE_STEP_TIMEOUT=5 STEP_TIMEOUT_SECONDS=1800 resolve_step_timeout)" == 5 ]] || detail="$detail env override"
    report "should use 600 seconds, a per-call value, and let UPDATE_STEP_TIMEOUT win" "$detail"
}

wait_for_file() {
    local path="$1"
    for _ in $(seq 50); do
        [[ -s "$path" ]] && return 0
        sleep 0.1
    done
    return 1
}

test_interrupt_kills_the_step_group() {
    local detail="" signal runner_pid group_id step_status
    for signal in TERM HUP; do
        reset_files
        rm -f "$SANDBOX/group" "$SANDBOX/status"
        (
            run_quiet_step "Sleepy" sh -c 'ps -o pgid= -p $$ >"$1"; sleep 30' sh "$SANDBOX/group" >/dev/null 2>&1
            echo $? >"$SANDBOX/status"
        ) &
        runner_pid=$!
        wait_for_file "$SANDBOX/group" || detail="$detail $signal: step did not start"
        group_id="$(tr -d ' \n' <"$SANDBOX/group")"
        kill -s "$signal" "$runner_pid"
        wait "$runner_pid" 2>/dev/null
        step_status="$(cat "$SANDBOX/status" 2>/dev/null)"
        [[ -n "$step_status" && "$step_status" != 0 ]] || detail="$detail $signal: status [$step_status]"
        ! kill -0 -- "-$group_id" 2>/dev/null || detail="$detail $signal: group $group_id still alive"
        [[ "$(cat "$UPDATE_REPORT")" == "ERROR Sleepy" ]] || detail="$detail $signal: report [$(cat "$UPDATE_REPORT")]"
    done
    report "should kill the step's process group and fail when the runner gets TERM or HUP" "$detail"
}

reset_progress() {
    reset_files
    export UPDATE_PROGRESS_FILE="$SANDBOX/run.progress"
    unset UPDATE_STEP_TOTAL
    : >"$UPDATE_PROGRESS_FILE"
}

clear_progress() {
    unset UPDATE_PROGRESS_FILE UPDATE_STEP_TOTAL
}

test_plan_lists_steps_and_numbers_them() {
    local detail="" plan_output step_output skipped_output visible_output
    reset_progress
    plan_output="$(print_step_plan "record-role dev" system doctor-dev)"
    export UPDATE_STEP_TOTAL=3
    step_output="$(run_quiet_step "record-role dev" true 2>&1)"
    skipped_output="$(report_skipped_step system)"
    visible_output="$(run_visible_step doctor-dev true 2>&1)"
    clear_progress
    [[ "$plan_output" == "Étapes (3) : record-role dev · system · doctor-dev" ]] || detail="plan [$plan_output]"
    [[ "$step_output" == "✓ [1/3] record-role dev" ]] || detail="$detail step [$step_output]"
    [[ "$skipped_output" == "– [2/3] system (ignoré)" ]] || detail="$detail skipped [$skipped_output]"
    [[ "$visible_output" == $'==> [3/3] doctor-dev\n✓ [3/3] doctor-dev' ]] || detail="$detail visible [$visible_output]"
    grep -q '^==== record-role dev ====$' "$UPDATE_LOG" || detail="$detail log header should stay unnumbered"
    report "should print the plan and number quiet, skipped and visible steps" "$detail"
}

test_failed_step_keeps_its_number() {
    local detail="" step_output
    reset_progress
    print_step_plan one two >/dev/null
    step_output="$(run_quiet_step one sh -c 'echo "fatal: no"; exit 1' 2>&1)" || true
    clear_progress
    [[ "$step_output" == "✗ [1/2] one"* ]] || detail="output [$step_output]"
    [[ "$(cat "$UPDATE_REPORT")" == "ERROR one" ]] || detail="$detail report [$(cat "$UPDATE_REPORT")]"
    report "should number a failed step and keep its label unnumbered in the report" "$detail"
}

test_container_and_nested_steps_are_not_counted() {
    local detail="" container_output
    reset_progress
    print_step_plan one two >/dev/null
    container_output="$(run_container_step hook true 2>&1)"
    run_uncounted_root_step nested true >/dev/null 2>&1
    clear_progress
    [[ "$container_output" == $'==> hook\n✓ hook' ]] || detail="container [$container_output]"
    [[ "$(cat "$SANDBOX/run.progress")" == "" ]] || detail="$detail counter [$(cat "$SANDBOX/run.progress")]"
    report "should not advance the counter for a container step or a nested root step" "$detail"
}

test_without_progress_file_output_is_unchanged() {
    local detail="" plan_output skipped_output
    reset_files
    clear_progress
    plan_output="$(print_step_plan one two)"
    skipped_output="$(report_skipped_step one)"
    [[ -z "$plan_output" && -z "$skipped_output" ]] || detail="plan [$plan_output] skipped [$skipped_output]"
    report "should print no plan and no skipped line without UPDATE_PROGRESS_FILE" "$detail"
}

test_quiet_step_success
test_plan_lists_steps_and_numbers_them
test_failed_step_keeps_its_number
test_container_and_nested_steps_are_not_counted
test_without_progress_file_output_is_unchanged
test_interrupt_kills_the_step_group
test_quiet_step_has_no_controlling_session
test_quiet_root_step_keeps_the_session
test_quiet_root_step_failure_is_reported
test_step_timeout_override_order
test_quiet_step_failure
test_quiet_step_failure_without_match_shows_tail
test_quiet_step_only_shows_its_own_output
test_quiet_step_closes_stdin
test_quiet_step_times_out
test_quiet_step_without_log_runs_verbose
test_visible_step_reports_failure
test_warn_appends_to_report
test_warn_without_report_prints_only
test_report_line_without_report_is_noop
test_summary_with_error_fails
test_summary_clean_report_is_silent

echo "$passed_count passed, $failed_count failed"
[[ "$failed_count" == 0 ]]
