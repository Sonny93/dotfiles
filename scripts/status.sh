# shellcheck shell=bash
# Status helpers (ok, warn, info, check_link) for doctor recipes and quiet update steps (run_quiet_step, run_visible_step, report_line); meant to be sourced.
#   run_quiet_step runs in a new session (setsid, no controlling terminal: the tty-bound sudo ticket is unusable there);
#   an INT, TERM or HUP received while it runs kills the step's process group and the step returns 130.
#   run_quiet_root_step keeps the terminal for steps that call sudo with the cached ticket.
#   Timeout: UPDATE_STEP_TIMEOUT overrides everything, else STEP_TIMEOUT_SECONDS set for one call, else 600 seconds.
#   UPDATE_LOG (run log) and UPDATE_REPORT (WARN/ERROR/REBOOT lines) are set by update.sh; both unset means plain verbose behavior.
readonly COLOR_RED=$'\033[31m'
readonly COLOR_GREEN=$'\033[32m'
readonly COLOR_YELLOW=$'\033[33m'
readonly COLOR_BLUE=$'\033[34m'
readonly COLOR_RESET=$'\033[0m'

print_status() {
    local color="$1" label="$2"
    shift 2
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        printf '%s●%s %s: %s\n' "$color" "$COLOR_RESET" "$label" "$*"
    else
        printf '● %s: %s\n' "$label" "$*"
    fi
}

ok() { print_status "$COLOR_GREEN" OK "$*"; }
warn() {
    print_status "$COLOR_YELLOW" WARN "$*"
    report_line WARN "$*"
}
info() { print_status "$COLOR_BLUE" INFO "$*"; }

check_link() {
    local link="$1" target="$2" recipe="$3"
    if [ "$(readlink "$link")" = "$target" ]; then
        ok "$link -> $target"
    else
        warn "$link is not a symlink to $target, run 'just $recipe'"
    fi
}

readonly DEFAULT_STEP_TIMEOUT_SECONDS=600
readonly KILL_GRACE_SECONDS=30
readonly INTERRUPTED_STATUS=130
readonly FAILURE_EXCERPT_LINES=15
readonly FAILURE_PATTERN='error|fatal|conflict|failed'

report_line() {
    local kind="$1"
    shift
    [ -n "${UPDATE_REPORT:-}" ] || return 0
    printf '%s %s\n' "$kind" "$*" >>"$UPDATE_REPORT"
}

print_marked_line() {
    local color="$1" mark="$2"
    shift 2
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        printf '%s%s%s %s\n' "$color" "$mark" "$COLOR_RESET" "$*"
    else
        printf '%s %s\n' "$mark" "$*"
    fi
}

print_step_ok() { print_marked_line "$COLOR_GREEN" "✓" "$*"; }
print_step_failed() { print_marked_line "$COLOR_RED" "✗" "$*"; }

print_step_header() { printf '==> %s\n' "$*"; }

append_log_header() {
    [ -n "${UPDATE_LOG:-}" ] || return 0
    printf '==== %s ====\n' "$*" >>"$UPDATE_LOG"
}

print_failure_excerpt() {
    local log_offset="$1" step_output matching
    step_output="$(tail -c "+$((log_offset + 1))" "$UPDATE_LOG")"
    matching="$(grep -iE "$FAILURE_PATTERN" <<<"$step_output" | tail -n "$FAILURE_EXCERPT_LINES" || true)"
    if [ -z "$matching" ]; then
        matching="$(tail -n "$FAILURE_EXCERPT_LINES" <<<"$step_output")"
    fi
    [ -z "$matching" ] || sed 's/^/    /' <<<"$matching"
    echo "    log: $UPDATE_LOG"
}

resolve_step_timeout() {
    echo "${UPDATE_STEP_TIMEOUT:-${STEP_TIMEOUT_SECONDS:-$DEFAULT_STEP_TIMEOUT_SECONDS}}"
}

run_detached_command() {
    local step_pid command_status=0 was_interrupted=0 saved_traps
    saved_traps="$(trap -p INT TERM HUP)"
    env GIT_TERMINAL_PROMPT=0 LC_ALL=C setsid timeout -k "$KILL_GRACE_SECONDS" "$(resolve_step_timeout)" "$@" \
        </dev/null >>"$UPDATE_LOG" 2>&1 &
    step_pid=$!
    trap 'was_interrupted=1; kill -TERM -- -"$step_pid" 2>/dev/null' INT TERM HUP
    wait "$step_pid" || command_status=$?
    if [ "$was_interrupted" -eq 1 ]; then
        wait "$step_pid" 2>/dev/null || true
        command_status="$INTERRUPTED_STATUS"
    fi
    trap - INT TERM HUP
    [ -z "$saved_traps" ] || eval "$saved_traps"
    return "$command_status"
}

run_attached_command() {
    env GIT_TERMINAL_PROMPT=0 LC_ALL=C timeout --foreground -k "$KILL_GRACE_SECONDS" "$(resolve_step_timeout)" "$@" \
        </dev/null >>"$UPDATE_LOG" 2>&1
}

begin_step_progress() {
    [ -t 1 ] && [ -z "${NO_COLOR:-}" ] || return 0
    printf '… %s' "$*"
}

end_step_progress() {
    [ -t 1 ] && [ -z "${NO_COLOR:-}" ] || return 0
    printf '\r\033[K'
}

run_logged_step() {
    local runner="$1" label="$2" log_offset command_status=0
    shift 2
    if [ -z "${UPDATE_LOG:-}" ]; then
        print_step_header "$label"
        "$@" || command_status=$?
        [ "$command_status" -eq 0 ] || report_line ERROR "$label"
        return "$command_status"
    fi
    append_log_header "$label"
    log_offset="$(stat -c %s "$UPDATE_LOG")"
    begin_step_progress "$label"
    "$runner" "$@" || command_status=$?
    end_step_progress
    if [ "$command_status" -eq 0 ]; then
        print_step_ok "$label"
        return 0
    fi
    print_step_failed "$label"
    print_failure_excerpt "$log_offset"
    report_line ERROR "$label"
    return "$command_status"
}

run_quiet_step() { run_logged_step run_detached_command "$@"; }

run_quiet_root_step() { run_logged_step run_attached_command "$@"; }

run_visible_step() {
    local label="$1" command_status=0
    shift
    print_step_header "$label"
    append_log_header "$label"
    "$@" || command_status=$?
    if [ "$command_status" -ne 0 ]; then
        print_step_failed "$label"
        report_line ERROR "$label"
        return "$command_status"
    fi
    print_step_ok "$label"
}

print_report_summary() {
    local report="${UPDATE_REPORT:-}" warning_count error_count reboot_count
    [ -s "$report" ] || return 0
    warning_count="$(grep -c '^WARN ' "$report" || true)"
    error_count="$(grep -c '^ERROR ' "$report" || true)"
    reboot_count="$(grep -c '^REBOOT ' "$report" || true)"
    printf 'Summary: %s WARN, %s ERROR, %s REBOOT\n' "$warning_count" "$error_count" "$reboot_count"
    sed 's/^/  /' "$report"
    [ -z "${UPDATE_LOG:-}" ] || echo "  log: $UPDATE_LOG"
    [ "$error_count" -eq 0 ]
}
