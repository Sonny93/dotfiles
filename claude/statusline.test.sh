#!/usr/bin/env bash
# Tests of statusline.sh: pace coloring of the 5h and 7d usages, the quota log and the merged quota display.
# Usage: statusline.test.sh
#   prints `ok <name>` or `FAIL <name>: <detail>` per test and a summary line; exits 1 when a test failed
# Isolation: every test runs in a mktemp -d sandbox with HOME and XDG_STATE_HOME inside it, removed afterwards.

set -uo pipefail

CLAUDE_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLAUDE_DIRECTORY
readonly SCRIPT="$CLAUDE_DIRECTORY/statusline.sh"
readonly RED_ANCHOR=$'\033[1;38;2;230;70;70m'
readonly GREEN_ANCHOR=$'\033[1;38;2;80;200;80m'
readonly BOLD_GREEN=$'\033[1;32m'
readonly BOLD_YELLOW=$'\033[1;33m'
readonly BOLD_RED=$'\033[1;31m'
readonly FIVE_HOUR_SECONDS=18000
readonly SEVEN_DAY_SECONDS=604800
readonly SECONDS_PER_MINUTE=60
readonly SECONDS_PER_DAY=86400

passed_count=0
failed_count=0

new_sandbox() {
    SANDBOX=$(mktemp -d)
    export HOME="$SANDBOX/home"
    export XDG_STATE_HOME="$SANDBOX/state"
    unset COLUMNS
    mkdir -p "$HOME"
    cd "$SANDBOX" || exit 1
    LOG_FILE="$XDG_STATE_HOME/claude/quota-usage.tsv"
}

run_test() {
    local test_name="$1" output
    new_sandbox
    output=$("$test_name" 2>&1)
    if [[ -z "$output" ]]; then
        echo "ok $test_name"
        passed_count=$((passed_count + 1))
    else
        echo "FAIL $test_name: $output"
        failed_count=$((failed_count + 1))
    fi
    cd / && rm -rf "$SANDBOX"
}

quota_json() {
    local five_hour_percentage="$1" five_hour_remaining="$2" seven_day_percentage="$3" seven_day_remaining="$4"
    local now="$EPOCHSECONDS"
    jq -n \
        --argjson five_hour_percentage "$five_hour_percentage" \
        --argjson five_hour_resets_at "$((now + five_hour_remaining))" \
        --argjson seven_day_percentage "$seven_day_percentage" \
        --argjson seven_day_resets_at "$((now + seven_day_remaining))" \
        '{rate_limits: {
            five_hour: {used_percentage: $five_hour_percentage, resets_at: $five_hour_resets_at},
            seven_day: {used_percentage: $seven_day_percentage, resets_at: $seven_day_resets_at}}}'
}

fixed_quota_json() {
    jq -n --arg five_percentage "$1" --arg five_resets_at "$2" --arg seven_percentage "$3" --arg seven_resets_at "$4" '
        def window($percentage; $resets_at):
            if $percentage == "" then {} else {used_percentage: ($percentage | tonumber), resets_at: ($resets_at | tonumber)} end;
        {rate_limits: (
            (if $five_percentage == "" then {} else {five_hour: window($five_percentage; $five_resets_at)} end)
            + (if $seven_percentage == "" then {} else {seven_day: window($seven_percentage; $seven_resets_at)} end))}'
}

session_json() {
    jq --arg session_id "$1" '. + {session_id: $session_id}' <<<"$2"
}

render_as_session() {
    render "$(session_json "$1" "$2")"
}

render() {
    "$SCRIPT" <<<"$1"
}

assert_contains() {
    [[ "$1" == *"$2"* ]] || echo "expected output to contain [$2], got [$(cat -v <<<"$1")]"
}

assert_not_contains() {
    [[ "$1" != *"$2"* ]] || echo "expected output not to contain [$2], got [$(cat -v <<<"$1")]"
}

assert_line_count() {
    local actual
    actual=$(wc -l <"$LOG_FILE")
    [[ "$actual" -eq "$1" ]] || echo "expected $1 log lines, got $actual"
}

should_color_red_with_a_plus_gap_when_usage_is_far_ahead_of_the_five_hour_window() {
    local output
    output=$(render "$(quota_json 40 "$((FIVE_HOUR_SECONDS - 30 * SECONDS_PER_MINUTE))" 1 "$SEVEN_DAY_SECONDS")")
    assert_contains "$output" "${RED_ANCHOR}40% +30"
}

should_color_green_with_a_minus_gap_when_usage_is_behind_the_five_hour_window() {
    local output
    output=$(render "$(quota_json 90 "$((10 * SECONDS_PER_MINUTE))" 1 "$SEVEN_DAY_SECONDS")")
    assert_contains "$output" "${GREEN_ANCHOR}90% -6"
    assert_not_contains "$output" "90% +"
}

should_show_no_gap_when_five_hour_usage_is_within_the_tolerance_of_the_elapsed_share() {
    local output
    output=$(render "$(quota_json 52 "$((FIVE_HOUR_SECONDS / 2))" 1 "$SEVEN_DAY_SECONDS")")
    assert_contains "$output" "${GREEN_ANCHOR}52%"$'\033[0m'
}

should_show_a_small_gap_when_seven_day_usage_is_within_the_tolerance_of_the_elapsed_share() {
    local output
    output=$(render "$(quota_json 1 "$FIVE_HOUR_SECONDS" 25 "$((5 * SECONDS_PER_DAY))")")
    assert_contains "$output" "${GREEN_ANCHOR}25% -3"$'\033[0m'
}

should_color_red_with_a_plus_gap_when_usage_is_far_ahead_of_the_seven_day_window() {
    local output
    output=$(render "$(quota_json 1 "$FIVE_HOUR_SECONDS" 60 "$((SEVEN_DAY_SECONDS - 2 * SECONDS_PER_DAY))")")
    assert_contains "$output" "${RED_ANCHOR}60% +32"
}

should_blend_toward_yellow_when_the_gap_is_between_tolerance_and_midpoint() {
    local output
    output=$(render "$(quota_json 30 "$((FIVE_HOUR_SECONDS - 60 * SECONDS_PER_MINUTE))" 1 "$SEVEN_DAY_SECONDS")")
    assert_contains "$output" $'\033[1;38;2;155;200;70m30% +10'
}

should_use_the_absolute_color_when_resets_at_is_missing() {
    local output
    output=$(render '{"rate_limits":{"five_hour":{"used_percentage":30},"seven_day":{"used_percentage":60}}}')
    assert_contains "$output" "${BOLD_GREEN}30%"
    assert_contains "$output" "${BOLD_YELLOW}60%"
    assert_not_contains "$output" " +"
}

should_use_the_absolute_red_color_when_resets_at_is_missing_and_usage_is_high() {
    local output
    output=$(render '{"rate_limits":{"five_hour":{"used_percentage":85}}}')
    assert_contains "$output" "${BOLD_RED}85%"
}

last_log_fields() {
    tail -n 1 "$LOG_FILE" | cut -f2-
}

assert_last_log_fields() {
    local actual
    actual=$(last_log_fields)
    [[ "$actual" == "$1" ]] || echo "expected last log fields [$1], got [$actual]"
}

should_create_the_log_with_a_header_and_one_line_on_first_quota_values() {
    render "$(fixed_quota_json 40 1000 10 5000)" >/dev/null
    [[ "$(head -n 1 "$LOG_FILE")" == "# epoch_seconds"$'\t'"five_hour_used_percentage"* ]] || echo "missing header"
    assert_line_count 2
}

should_not_append_a_line_when_the_quota_values_are_unchanged() {
    local input
    input=$(fixed_quota_json 40 1000 10 5000)
    render "$input" >/dev/null
    render "$input" >/dev/null
    assert_line_count 2
}

should_append_a_line_when_a_quota_value_increases() {
    render "$(fixed_quota_json 40 1000 10 5000)" >/dev/null
    render "$(fixed_quota_json 41 1000 10 5000)" >/dev/null
    assert_line_count 3
}

should_log_the_raw_used_percentage() {
    render "$(fixed_quota_json 40.7 1000 10 5000)" >/dev/null
    assert_last_log_fields $'40.7\t1000\t10\t5000'
}

should_not_append_a_line_when_a_session_reports_a_lower_percentage_for_the_same_reset() {
    render "$(fixed_quota_json 40 1000 10 5000)" >/dev/null
    render "$(fixed_quota_json 26 1000 10 5000)" >/dev/null
    assert_line_count 2
}

should_not_append_a_line_when_a_session_reports_an_older_resets_at() {
    render "$(fixed_quota_json 40 1000 10 5000)" >/dev/null
    render "$(fixed_quota_json 90 900 10 5000)" >/dev/null
    assert_line_count 2
}

should_carry_forward_the_five_hour_values_when_only_the_seven_day_window_advances() {
    render "$(fixed_quota_json 40 1000 10 5000)" >/dev/null
    render "$(fixed_quota_json "" "" 11 5000)" >/dev/null
    assert_last_log_fields $'40\t1000\t11\t5000'
}

should_not_append_a_line_when_the_input_only_has_a_seven_day_window_that_did_not_advance() {
    render "$(fixed_quota_json 40 1000 10 5000)" >/dev/null
    render "$(fixed_quota_json "" "" 10 5000)" >/dev/null
    assert_line_count 2
}

should_append_a_line_with_the_new_reset_when_the_window_resets() {
    render "$(fixed_quota_json 90 1000 10 5000)" >/dev/null
    render "$(fixed_quota_json 3 19000 10 5000)" >/dev/null
    assert_last_log_fields $'3\t19000\t10\t5000'
}

should_not_create_the_log_when_the_input_has_no_rate_limits() {
    render '{"model":{"display_name":"Opus"}}' >/dev/null
    [[ ! -e "$LOG_FILE" ]] || echo "expected no log file"
}

should_still_print_the_usage_segment_when_the_log_location_is_unwritable() {
    local output
    : >"$SANDBOX/not-a-directory"
    export XDG_STATE_HOME="$SANDBOX/not-a-directory"
    output=$(render "$(fixed_quota_json 40 1000 10 5000)" 2>&1)
    assert_contains "$output" "[5h"
    assert_contains "$output" "40%"
}

should_display_the_logged_percentage_when_the_session_reports_a_stale_lower_one_for_the_same_reset() {
    local output now="$EPOCHSECONDS"
    render "$(fixed_quota_json 40 "$((now + 3600))" 10 "$((now + 86400))")" >/dev/null
    output=$(render "$(fixed_quota_json 26 "$((now + 3600))" 10 "$((now + 86400))")")
    assert_contains "$output" "40%"
    assert_not_contains "$output" "26%"
}

should_display_the_session_percentage_when_it_is_newer_than_the_log() {
    local output now="$EPOCHSECONDS"
    render "$(fixed_quota_json 40 "$((now + 3600))" 10 "$((now + 86400))")" >/dev/null
    output=$(render "$(fixed_quota_json 55 "$((now + 3600))" 10 "$((now + 86400))")")
    assert_contains "$output" "55%"
    assert_not_contains "$output" "40%"
}

should_display_the_logged_state_and_append_nothing_when_the_session_has_no_rate_limits() {
    local output now="$EPOCHSECONDS"
    render "$(fixed_quota_json 40 "$((now + 3600))" 10 "$((now + 86400))")" >/dev/null
    output=$(render '{"model":{"display_name":"Opus"}}')
    assert_contains "$output" "[5h"
    assert_contains "$output" "40%"
    assert_contains "$output" "[7d"
    assert_line_count 2
}

should_ignore_a_logged_window_whose_reset_is_in_the_past_for_display() {
    local output now="$EPOCHSECONDS"
    render "$(fixed_quota_json 90 "$((now - 100))" 10 "$((now + 86400))")" >/dev/null
    output=$(render "$(fixed_quota_json 20 "$((now - 100))" 10 "$((now + 86400))")")
    assert_contains "$output" "20%"
    assert_not_contains "$output" "90%"
}

should_keep_displaying_session_values_when_the_log_holds_garbage() {
    local output now="$EPOCHSECONDS"
    mkdir -p "$(dirname "$LOG_FILE")"
    printf 'x\tabc\tdef\tghi\tjkl\n' >"$LOG_FILE"
    output=$(render "$(fixed_quota_json 40 "$((now + 3600))" 10 "$((now + 86400))")")
    assert_contains "$output" "40%"
}

should_keep_displaying_session_values_when_the_log_is_unreadable() {
    local output now="$EPOCHSECONDS"
    mkdir -p "$LOG_FILE"
    output=$(render "$(fixed_quota_json 40 "$((now + 3600))" 10 "$((now + 86400))")")
    assert_contains "$output" "40%"
}

should_display_the_lower_percentage_when_the_same_session_reports_a_drop_for_the_same_reset() {
    local output now="$EPOCHSECONDS" five_resets_at seven_resets_at
    five_resets_at=$((now + 3600))
    seven_resets_at=$((now + 86400))
    render_as_session session-a "$(fixed_quota_json 10 "$five_resets_at" 100 "$seven_resets_at")" >/dev/null
    output=$(render_as_session session-a "$(fixed_quota_json 10 "$five_resets_at" 6 "$seven_resets_at")")
    assert_contains "$output" "6%"
    assert_not_contains "$output" "100%"
    assert_last_log_fields "10"$'\t'"$five_resets_at"$'\t'"6"$'\t'"$seven_resets_at"
}

should_keep_the_reset_percentage_when_a_known_session_still_reports_the_stale_higher_value() {
    local output now="$EPOCHSECONDS" five_resets_at seven_resets_at
    five_resets_at=$((now + 3600))
    seven_resets_at=$((now + 86400))
    render_as_session session-a "$(fixed_quota_json 10 "$five_resets_at" 100 "$seven_resets_at")" >/dev/null
    render_as_session session-b "$(fixed_quota_json 10 "$five_resets_at" 100 "$seven_resets_at")" >/dev/null
    render_as_session session-b "$(fixed_quota_json 10 "$five_resets_at" 6 "$seven_resets_at")" >/dev/null
    output=$(render_as_session session-a "$(fixed_quota_json 10 "$five_resets_at" 100 "$seven_resets_at")")
    assert_contains "$output" "6%"
    assert_not_contains "$output" "100%"
}

should_display_the_fresh_percentage_when_a_known_session_is_followed_by_another_with_an_unchanged_value() {
    local output now="$EPOCHSECONDS" five_resets_at seven_resets_at
    five_resets_at=$((now + 3600))
    seven_resets_at=$((now + 86400))
    render_as_session session-a "$(fixed_quota_json 40 "$five_resets_at" 10 "$seven_resets_at")" >/dev/null
    render_as_session session-b "$(fixed_quota_json 40 "$five_resets_at" 10 "$seven_resets_at")" >/dev/null
    render_as_session session-b "$(fixed_quota_json 55 "$five_resets_at" 10 "$seven_resets_at")" >/dev/null
    output=$(render_as_session session-a "$(fixed_quota_json 40 "$five_resets_at" 10 "$seven_resets_at")")
    assert_contains "$output" "55%"
    assert_not_contains "$output" "40%"
}

should_keep_the_monotonic_merge_when_a_first_seen_session_reports_a_lower_value() {
    local output now="$EPOCHSECONDS" five_resets_at seven_resets_at
    five_resets_at=$((now + 3600))
    seven_resets_at=$((now + 86400))
    render_as_session session-a "$(fixed_quota_json 40 "$five_resets_at" 10 "$seven_resets_at")" >/dev/null
    output=$(render_as_session session-b "$(fixed_quota_json 26 "$five_resets_at" 10 "$seven_resets_at")")
    assert_contains "$output" "40%"
    assert_not_contains "$output" "26%"
    assert_line_count 2
}

should_not_create_a_session_file_when_the_session_id_contains_a_slash_or_dots() {
    render_as_session "../x" "$(fixed_quota_json 40 1000 10 5000)" >/dev/null
    [[ ! -e "$XDG_STATE_HOME/claude/statusline-sessions" ]] || echo "expected no session directory"
    [[ ! -e "$XDG_STATE_HOME/claude/x" ]] || echo "expected no file outside the session directory"
}

should_store_the_raw_quota_values_in_the_session_file() {
    render_as_session session-a "$(fixed_quota_json 40.7 1000 10 5000)" >/dev/null
    local actual
    actual=$(cat "$XDG_STATE_HOME/claude/statusline-sessions/session-a")
    [[ "$actual" == $'40.7\t1000\t10\t5000' ]] || echo "unexpected session record [$actual]"
}

should_not_rewrite_the_session_file_when_the_values_are_unchanged() {
    local input before after session_file="$XDG_STATE_HOME/claude/statusline-sessions/session-a"
    input=$(fixed_quota_json 40 1000 10 5000)
    render_as_session session-a "$input" >/dev/null
    before=$(stat -c %y "$session_file")
    sleep 0.05
    render_as_session session-a "$input" >/dev/null
    after=$(stat -c %y "$session_file")
    [[ "$before" == "$after" ]] || echo "session file was rewritten ($before then $after)"
}

should_prune_only_old_session_files_when_a_new_session_file_is_created() {
    local sessions_directory="$XDG_STATE_HOME/claude/statusline-sessions"
    mkdir -p "$sessions_directory"
    : >"$sessions_directory/old-session"
    : >"$sessions_directory/recent-session"
    touch -d '10 days ago' "$sessions_directory/old-session"
    render_as_session new-session "$(fixed_quota_json 40 1000 10 5000)" >/dev/null
    [[ ! -e "$sessions_directory/old-session" ]] || echo "expected the old session file to be pruned"
    [[ -e "$sessions_directory/recent-session" ]] || echo "expected the recent session file to survive"
    [[ -e "$sessions_directory/new-session" ]] || echo "expected the new session file to exist"
}

should_still_log_the_drop_on_a_later_render_when_the_log_was_unwritable_during_the_drop() {
    local output now="$EPOCHSECONDS" five_resets_at seven_resets_at drop_json
    five_resets_at=$((now + 3600))
    seven_resets_at=$((now + 86400))
    drop_json=$(fixed_quota_json 10 "$five_resets_at" 6 "$seven_resets_at")
    render_as_session session-a "$(fixed_quota_json 10 "$five_resets_at" 100 "$seven_resets_at")" >/dev/null
    chmod a-w "$LOG_FILE"
    render_as_session session-a "$drop_json" >/dev/null
    chmod u+w "$LOG_FILE"
    output=$(render_as_session session-a "$drop_json")
    assert_contains "$output" "6%"
    assert_last_log_fields "10"$'\t'"$five_resets_at"$'\t'"6"$'\t'"$seven_resets_at"
}

for test_name in $(declare -F | awk '{print $3}' | grep '^should_'); do
    run_test "$test_name"
done

echo "$passed_count passed, $failed_count failed"
[[ "$failed_count" -eq 0 ]]
