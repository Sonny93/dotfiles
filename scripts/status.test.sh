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

test_quiet_step_success
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
