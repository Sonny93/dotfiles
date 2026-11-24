#!/usr/bin/env bash
# Tests of update.sh against a temporary origin, clone, config and state directory, with stubbed just, tmux, sudo and gh.
# Usage: update.test.sh
#   prints `ok <name>` or `FAIL <name>: <detail>` per test and a summary line; exits 1 when a test failed
# Isolation: everything lives in a mktemp -d sandbox removed on exit; the real repo, config and git config are never touched.

set -uo pipefail

SCRIPT_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
readonly UPDATE_SCRIPT="$SCRIPT_DIRECTORY/update.sh"
SANDBOX="$(mktemp -d)"
readonly SANDBOX
trap 'rm -rf "$SANDBOX"' EXIT

export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

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

write_stubs() {
    mkdir -p "$SANDBOX/bin"
    cat >"$SANDBOX/bin/just" <<STUB
#!/usr/bin/env bash
case "\$*" in
    *--dump*) cat "$SANDBOX/dump.json" ;;
    *) echo "just \$*" >>"$SANDBOX/calls" ;;
esac
STUB
    cat >"$SANDBOX/bin/sudo" <<STUB
#!/usr/bin/env bash
echo "sudo \$*" >>"$SANDBOX/sudo_calls"
[ "\$*" = "-n true" ] && [ -e "$SANDBOX/sudo_denied" ] && exit 1
[ "\$*" = "-v" ] && [ -e "$SANDBOX/sudo_login_fails" ] && exit 1
exit 0
STUB
    printf '#!/usr/bin/env bash\nexit 1\n' >"$SANDBOX/bin/tmux"
    printf '#!/usr/bin/env bash\nexit 1\n' >"$SANDBOX/bin/gh"
    chmod +x "$SANDBOX/bin/just" "$SANDBOX/bin/tmux" "$SANDBOX/bin/sudo" "$SANDBOX/bin/gh"
    printf '%s' '{"recipes":{"dev":{"dependencies":[{"recipe":"record-role","arguments":["dev"]},{"recipe":"system","arguments":[]},{"recipe":"build-deps","arguments":[]},{"recipe":"gh-auth","arguments":[]},{"recipe":"doctor-dev","arguments":[]}]}}}' >"$SANDBOX/dump.json"
}

setup_scenario() {
    rm -rf "$SANDBOX/origin.git" "$SANDBOX/clone" "$SANDBOX/peer" "$SANDBOX/config" "$SANDBOX/state" "$SANDBOX/calls" "$SANDBOX/sudo_calls" "$SANDBOX/sudo_denied" "$SANDBOX/sudo_login_fails"
    mkdir -p "$SANDBOX/config/dotfiles"
    touch "$SANDBOX/calls" "$SANDBOX/sudo_calls"
    git init -q --bare -b main "$SANDBOX/origin.git"
    git clone -q "$SANDBOX/origin.git" "$SANDBOX/clone" 2>/dev/null
    git -C "$SANDBOX/clone" checkout -q -b main
    echo "recipes" >"$SANDBOX/clone/Justfile"
    git -C "$SANDBOX/clone" add Justfile
    git -C "$SANDBOX/clone" commit -q -m "Add Justfile"
    git -C "$SANDBOX/clone" push -q -u origin main 2>/dev/null
}

push_upstream_commit() {
    git clone -q "$SANDBOX/origin.git" "$SANDBOX/peer" 2>/dev/null
    echo "more" >"$SANDBOX/peer/extra"
    git -C "$SANDBOX/peer" add extra
    git -C "$SANDBOX/peer" commit -q -m "Add extra"
    git -C "$SANDBOX/peer" push -q origin main 2>/dev/null
}

install_hook() {
    printf '#!/usr/bin/env bash\necho hook >>"%s"\n' "$SANDBOX/calls" >"$SANDBOX/config/dotfiles/update-hook"
    chmod +x "$SANDBOX/config/dotfiles/update-hook"
}

update_arguments=(--verbose)
preset_report=""

run_update() {
    stdout="$(env -u UPDATE_LOG -u UPDATE_REPORT ${preset_report:+UPDATE_REPORT="$preset_report"} \
        PATH="$SANDBOX/bin:$PATH" DOTFILES_DIRECTORY="$SANDBOX/clone" XDG_CONFIG_HOME="$SANDBOX/config" \
        XDG_STATE_HOME="$SANDBOX/state" XDG_RUNTIME_DIR="$SANDBOX/runtime" UPDATE_SUDO_REFRESH_SECONDS=1 \
        "$UPDATE_SCRIPT" "${update_arguments[@]}" 2>"$SANDBOX/stderr")"
    exit_status=$?
    stderr="$(cat "$SANDBOX/stderr")"
    calls="$(cat "$SANDBOX/calls")"
    sudo_calls="$(cat "$SANDBOX/sudo_calls")"
}

install_hook_script() {
    printf '#!/usr/bin/env bash\n%s\n' "$1" >"$SANDBOX/config/dotfiles/update-hook"
    chmod +x "$SANDBOX/config/dotfiles/update-hook"
}

test_hook_runs_and_not_just() {
    local detail=""
    setup_scenario
    install_hook
    echo server >"$SANDBOX/config/dotfiles/role"
    run_update
    [[ "$exit_status" == 0 ]] || detail="exit status $exit_status"
    [[ "$calls" == "hook" ]] || detail="$detail calls [$calls]"
    report "should run the hook and not just when an update hook exists" "$detail"
}

test_server_role_runs_just() {
    local detail=""
    setup_scenario
    echo server >"$SANDBOX/config/dotfiles/role"
    run_update
    [[ "$exit_status" == 0 ]] || detail="exit status $exit_status"
    [[ "$calls" == "just -f $SANDBOX/clone/Justfile server" ]] || detail="$detail calls [$calls]"
    report "should run the server recipe when the role is server and no hook exists" "$detail"
}

test_missing_role_fails() {
    local detail=""
    setup_scenario
    run_update
    [[ "$exit_status" == 1 ]] || detail="exit status $exit_status"
    [[ "$stderr" == *"just dev"* && "$stderr" == *"just server"* ]] || detail="$detail stderr [$stderr]"
    [[ -z "$calls" ]] || detail="$detail calls [$calls]"
    report "should fail with a hint when no role and no hook exist" "$detail"
}

test_dirty_tree_skips_merge() {
    local detail="" head_before
    setup_scenario
    echo server >"$SANDBOX/config/dotfiles/role"
    push_upstream_commit
    echo "local edit" >>"$SANDBOX/clone/Justfile"
    head_before="$(git -C "$SANDBOX/clone" rev-parse HEAD)"
    run_update
    [[ "$exit_status" == 0 ]] || detail="exit status $exit_status"
    [[ "$(git -C "$SANDBOX/clone" rev-parse HEAD)" == "$head_before" ]] || detail="$detail HEAD moved"
    [[ "$stdout" == *"WARN"*"uncommitted"* ]] || detail="$detail stdout [$stdout]"
    [[ "$calls" == "just -f $SANDBOX/clone/Justfile server" ]] || detail="$detail calls [$calls]"
    report "should not merge, warn and still apply when a tracked file is modified" "$detail"
}

test_upstream_ahead_merges_and_reexecs() {
    local detail=""
    setup_scenario
    echo server >"$SANDBOX/config/dotfiles/role"
    push_upstream_commit
    run_update
    [[ "$exit_status" == 0 ]] || detail="exit status $exit_status"
    [[ -f "$SANDBOX/clone/extra" ]] || detail="$detail commit not merged"
    [[ "$stdout" == *"running the pulled version"* ]] || detail="$detail stdout [$stdout]"
    [[ "$calls" == "just -f $SANDBOX/clone/Justfile server" ]] || detail="$detail calls [$calls]"
    report "should merge new commits and re-exec the script when upstream is ahead" "$detail"
}

test_up_to_date_does_not_reexec() {
    local detail=""
    setup_scenario
    echo server >"$SANDBOX/config/dotfiles/role"
    run_update
    [[ "$stdout" == *"Already up to date"* ]] || detail="stdout [$stdout]"
    [[ "$stdout" != *"running the pulled version"* ]] || detail="$detail unexpected re-exec"
    report "should not re-exec when the repo is already up to date" "$detail"
}

test_unknown_argument_is_rejected() {
    local detail=""
    setup_scenario
    update_arguments=(--fast)
    run_update
    update_arguments=(--verbose)
    [[ "$exit_status" == 2 ]] || detail="exit status $exit_status"
    [[ "$stderr" == *"Usage: update.sh [--verbose]"* ]] || detail="$detail stderr [$stderr]"
    [[ -z "$calls" ]] || detail="$detail calls [$calls]"
    report "should reject an unknown argument with a usage message and run nothing" "$detail"
}

test_verbose_has_no_log() {
    local detail=""
    setup_scenario
    install_hook_script "echo \"log=\${UPDATE_LOG-unset} report=\${UPDATE_REPORT-unset}\" >>\"$SANDBOX/calls\""
    run_update
    [[ "$calls" == "log=unset report=$SANDBOX/state/dotfiles/update/"*.report ]] || detail="calls [$calls]"
    [[ -z "$(ls "$SANDBOX"/state/dotfiles/update/*.log 2>/dev/null)" ]] || detail="$detail log created"
    report "should export only UPDATE_REPORT and create no log with --verbose" "$detail"
}

test_quiet_run_exports_log_and_report() {
    local detail=""
    setup_scenario
    install_hook_script "echo \"log=\$UPDATE_LOG report=\$UPDATE_REPORT\" >>\"$SANDBOX/calls\""
    update_arguments=()
    run_update
    update_arguments=(--verbose)
    [[ "$exit_status" == 0 ]] || detail="exit status $exit_status"
    [[ "$calls" == "log=$SANDBOX/state/dotfiles/update/"*".log report=$SANDBOX/state/dotfiles/update/"*".report" ]] || detail="$detail calls [$calls]"
    [[ -s "$(ls "$SANDBOX"/state/dotfiles/update/*.report)" ]] && detail="$detail report not empty"
    [[ "$(stat -c %a "$SANDBOX/state/dotfiles/update")" == 700 ]] || detail="$detail directory not 700"
    report "should export a log and an empty report in a private directory in quiet mode" "$detail"
}

test_preset_report_is_used_and_truncated() {
    local detail="" preset="$SANDBOX/outside/caller.report"
    setup_scenario
    mkdir -p "$SANDBOX/outside"
    echo "WARN stale" >"$preset"
    install_hook_script "echo 'WARN from hook' >>\"\$UPDATE_REPORT\""
    preset_report="$preset"
    update_arguments=()
    run_update
    preset_report=""
    update_arguments=(--verbose)
    [[ "$exit_status" == 0 ]] || detail="exit status $exit_status"
    [[ "$(cat "$preset")" == "WARN from hook" ]] || detail="$detail preset content [$(cat "$preset")]"
    [[ -z "$(ls "$SANDBOX"/state/dotfiles/update/*.report 2>/dev/null)" ]] || detail="$detail generated a report anyway"
    report "should use and truncate a UPDATE_REPORT preset by the caller" "$detail"
}

test_error_in_report_fails_with_summary() {
    local detail=""
    setup_scenario
    install_hook_script "echo 'ERROR boom' >>\"\$UPDATE_REPORT\""
    update_arguments=()
    run_update
    update_arguments=(--verbose)
    [[ "$exit_status" == 1 ]] || detail="exit status $exit_status"
    [[ "$stdout" == *"1 ERROR"* && "$stdout" == *"ERROR boom"* && "$stdout" == *"log: $SANDBOX/state"* ]] || detail="$detail stdout [$stdout]"
    report "should print the summary with the log path and exit 1 when the report holds an ERROR" "$detail"
}

test_failing_hook_is_reported() {
    local detail=""
    setup_scenario
    install_hook_script "exit 7"
    run_update
    [[ "$exit_status" == 1 ]] || detail="exit status $exit_status"
    [[ "$stdout" == *"ERROR update hook"* ]] || detail="$detail stdout [$stdout]"
    report "should report an ERROR and exit 1 when the update hook fails" "$detail"
}

test_old_runs_are_pruned() {
    local detail="" index
    setup_scenario
    install_hook
    mkdir -p "$SANDBOX/state/dotfiles/update"
    for index in $(seq -w 1 20); do
        touch "$SANDBOX/state/dotfiles/update/2020-01-$index""T00-00-00.log"
    done
    update_arguments=()
    run_update
    update_arguments=(--verbose)
    [[ "$(ls "$SANDBOX"/state/dotfiles/update/*.log | wc -l)" == 14 ]] || detail="log count $(ls "$SANDBOX"/state/dotfiles/update/*.log | wc -l)"
    [[ -e "$SANDBOX/state/dotfiles/update/2020-01-01T00-00-00.log" ]] && detail="$detail oldest kept"
    report "should keep only the 14 newest logs" "$detail"
}

test_sudo_session_ends_on_exit() {
    local detail=""
    setup_scenario
    install_hook
    run_update
    [[ "$sudo_calls" == *"sudo -k"* ]] || detail="sudo calls [$sudo_calls]"
    report "should invalidate the sudo timestamp when the run ends" "$detail"
}

run_quiet_dev_role() {
    setup_scenario
    echo dev >"$SANDBOX/config/dotfiles/role"
    update_arguments=()
    run_update
    update_arguments=(--verbose)
}

test_quiet_role_run_goes_step_by_step() {
    local detail="" justfile="$SANDBOX/clone/Justfile"
    run_quiet_dev_role
    [[ "$exit_status" == 0 ]] || detail="exit status $exit_status"
    [[ "$stdout" == *"✓ [1/5] record-role dev"* && "$stdout" == *"✓ [2/5] system"* && "$stdout" == *"✓ [3/5] build-deps"* ]] || detail="$detail stdout [$stdout]"
    [[ "$stdout" == *"gh not authenticated, skipped gh-auth"* ]] || detail="$detail no gh skip warning"
    [[ "$calls" == "just -f $justfile record-role dev"$'\n'"just -f $justfile system"$'\n'"just -f $justfile build-deps"$'\n'"just -f $justfile doctor-dev" ]] || detail="$detail calls [$calls]"
    report "should run the role steps one by one, skip gh-auth and run the doctor once at the end" "$detail"
}

test_quiet_role_run_numbers_every_step() {
    local detail=""
    run_quiet_dev_role
    [[ "$stdout" == *"Étapes (5) : record-role dev · system · build-deps · gh-auth · doctor-dev"* ]] || detail="plan missing [$stdout]"
    [[ "$stdout" == *"✓ [1/5] record-role dev"* && "$stdout" == *"✓ [2/5] system"* && "$stdout" == *"✓ [3/5] build-deps"* ]] || detail="$detail counters [$stdout]"
    [[ "$stdout" == *"– [4/5] gh-auth (ignoré)"* ]] || detail="$detail skipped line missing [$stdout]"
    [[ "$stdout" == *"✓ [5/5] doctor-dev"* ]] || detail="$detail doctor not counted [$stdout]"
    [[ "$stdout" == *"==> [2/5] system"* ]] || detail="$detail visible header not numbered [$stdout]"
    report "should print the plan once and number every step up to N, skipped steps included" "$detail"
}

test_failed_sudo_login_counts_skipped_root_steps() {
    local detail=""
    setup_scenario
    touch "$SANDBOX/sudo_denied" "$SANDBOX/sudo_login_fails"
    echo dev >"$SANDBOX/config/dotfiles/role"
    update_arguments=()
    run_update
    update_arguments=(--verbose)
    [[ "$stdout" == *"– [3/5] build-deps (ignoré)"* && "$stdout" == *"✓ [5/5] doctor-dev"* ]] || detail="stdout [$stdout]"
    report "should advance the counter for a root step skipped without a sudo ticket" "$detail"
}

test_hook_step_is_not_counted() {
    local detail=""
    setup_scenario
    install_hook
    echo dev >"$SANDBOX/config/dotfiles/role"
    update_arguments=()
    run_update
    update_arguments=(--verbose)
    [[ "$stdout" == *"==> update hook"* && "$stdout" == *"✓ update hook"* ]] || detail="hook lines missing [$stdout]"
    [[ "$stdout" != *"Étapes"* ]] || detail="$detail plan printed by update.sh [$stdout]"
    report "should not print a plan nor a counter for the update hook container step" "$detail"
}

test_verbose_run_has_no_counter() {
    local detail=""
    setup_scenario
    echo dev >"$SANDBOX/config/dotfiles/role"
    run_update
    [[ "$stdout" != *"Étapes"* && "$stdout" != *"[1/"* ]] || detail="stdout [$stdout]"
    report "should keep the verbose output free of plan and counters" "$detail"
}

test_cached_sudo_ticket_is_not_asked_again() {
    local detail=""
    run_quiet_dev_role
    ! grep -qx 'sudo -v' <<<"$sudo_calls" || detail="sudo -v was called [$sudo_calls]"
    report "should not ask for the sudo password when the ticket is cached" "$detail"
}

test_missing_sudo_ticket_is_asked_once() {
    local detail=""
    setup_scenario
    touch "$SANDBOX/sudo_denied"
    echo dev >"$SANDBOX/config/dotfiles/role"
    update_arguments=()
    run_update
    update_arguments=(--verbose)
    [[ "$(grep -cx 'sudo -v' <<<"$sudo_calls")" == 1 ]] || detail="sudo calls [$sudo_calls]"
    [[ "$stdout" == *"✓ [3/5] build-deps"* ]] || detail="$detail stdout [$stdout]"
    report "should run one visible sudo -v before the root steps when no ticket is cached" "$detail"
}

test_failed_sudo_login_skips_root_steps() {
    local detail=""
    setup_scenario
    touch "$SANDBOX/sudo_denied" "$SANDBOX/sudo_login_fails"
    echo dev >"$SANDBOX/config/dotfiles/role"
    update_arguments=()
    run_update
    update_arguments=(--verbose)
    [[ "$calls" != *"build-deps"* ]] || detail="build-deps ran [$calls]"
    [[ "$stdout" == *"skipped build-deps, run 'just build-deps'"* ]] || detail="$detail stdout [$stdout]"
    [[ "$exit_status" == 0 ]] || detail="$detail exit status $exit_status"
    report "should skip the root steps with a WARN when the sudo login fails" "$detail"
}

test_keepalive_pauses_while_pause_file_exists() {
    local detail=""
    setup_scenario
    mkdir -p "$SANDBOX/runtime"
    install_hook_script "sleep 1.5
touch \"\$UPDATE_SUDO_PAUSE_FILE\"
echo \"\$UPDATE_SUDO_PAUSE_FILE\" >\"$SANDBOX/pause_path\"
before=\$(grep -c 'sudo -n -v' \"$SANDBOX/sudo_calls\")
sleep 3
after=\$(grep -c 'sudo -n -v' \"$SANDBOX/sudo_calls\")
echo \"\$before \$after\" >\"$SANDBOX/pause_counts\""
    update_arguments=()
    run_update
    update_arguments=(--verbose)
    read -r before after <"$SANDBOX/pause_counts"
    [[ "$before" -ge 1 ]] || detail="keep-alive never ran (before $before)"
    [[ "$before" == "$after" ]] || detail="$detail sudo refreshed while paused ($before -> $after)"
    [[ "$(cat "$SANDBOX/pause_path")" == "$SANDBOX/runtime/dotfiles-update-sudo-pause-"* ]] || detail="$detail path [$(cat "$SANDBOX/pause_path")]"
    [[ ! -e "$(cat "$SANDBOX/pause_path")" ]] || detail="$detail pause file left behind"
    report "should not refresh the sudo ticket while the pause file exists and remove it on exit" "$detail"
}

write_stubs
test_keepalive_pauses_while_pause_file_exists
test_unknown_argument_is_rejected
test_verbose_has_no_log
test_quiet_run_exports_log_and_report
test_preset_report_is_used_and_truncated
test_error_in_report_fails_with_summary
test_failing_hook_is_reported
test_old_runs_are_pruned
test_sudo_session_ends_on_exit
test_quiet_role_run_goes_step_by_step
test_quiet_role_run_numbers_every_step
test_failed_sudo_login_counts_skipped_root_steps
test_hook_step_is_not_counted
test_verbose_run_has_no_counter
test_cached_sudo_ticket_is_not_asked_again
test_missing_sudo_ticket_is_asked_once
test_failed_sudo_login_skips_root_steps
test_hook_runs_and_not_just
test_server_role_runs_just
test_missing_role_fails
test_dirty_tree_skips_merge
test_upstream_ahead_merges_and_reexecs
test_up_to_date_does_not_reexec

echo "$passed_count passed, $failed_count failed"
[[ "$failed_count" == 0 ]]
