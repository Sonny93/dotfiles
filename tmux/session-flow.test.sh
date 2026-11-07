#!/usr/bin/env bash
# Tests of the session flow: projects.sh, workspace.sh, session.sh and session-picker.sh, on an isolated tmux server.
# Usage: session-flow.test.sh
#   prints `ok <name>` or `FAIL <name>: <detail>` per test and a summary line; exits 1 when a test failed
# Isolation: every test gets its own sandbox (mktemp -d) holding a fake HOME (so ~/dev, ~/.claude/projects and ~/dotfiles are fake)
#   and its own tmux socket (TMUX_TMPDIR), and the sandbox and its tmux server are removed afterwards; the real tmux server and ~/dev are never touched.
# Stubs first on PATH: `claude` logs its directory and arguments to claude.log, `zsh` sleeps to keep panes alive,
#   `fzf` replays the scripted answers <n>.out / <n>.status of the sandbox, one per call, logs each call to fzf.calls and saves its stdin to <n>.in.
# `gh` is absent from PATH by default (the "no gh" behavior of servers); the GitHub tests install a `gh` stub that serves the files owner / organization
#   of $SANDBOX/gh for `gh api`, fails with api.status when present, and logs every call to gh.log; `gh repo clone` creates the directory unless clone.status holds a non-zero status.
# GitHub tests write a fresh cache directly, so no detached refresh is ever spawned.

set -uo pipefail

TMUX_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TMUX_DIRECTORY
readonly POLL_ATTEMPTS=40
readonly POLL_INTERVAL_SECONDS=0.05
readonly TAB=$'\t'

passed_count=0
failed_count=0

# Assertions: they record the failure in the sandbox and let the test go on.

record_failure() {
    printf '%s\n' "$1" >>"$SANDBOX/failures"
}

assert_equals() {
    [[ "$1" == "$2" ]] || record_failure "$3: expected [$1], got [$2]"
}

assert_file_exists() {
    [[ -e "$1" ]] || record_failure "missing: $1"
}

assert_no_file() {
    [[ ! -e "$1" ]] || record_failure "unexpected: $1"
}

assert_contains() {
    [[ "$1" == *"$2"* ]] || record_failure "expected [$2] in [$1]"
}

assert_not_contains() {
    [[ "$1" != *"$2"* ]] || record_failure "unexpected [$2] in [$1]"
}

# Sandbox

write_stubs() {
    local stub_directory="$SANDBOX/stubs"
    mkdir -p "$stub_directory" "$SANDBOX/fzf"
    cat >"$stub_directory/claude" <<'STUB'
#!/bin/sh
echo "$PWD $*" >>"$SANDBOX/claude.log"
STUB
    printf '#!/bin/sh\nexec sleep 600\n' >"$stub_directory/zsh"
    cat >"$stub_directory/fzf" <<'STUB'
#!/bin/sh
cat >"$SANDBOX/fzf/stdin"
counter_file="$SANDBOX/fzf/counter"
count=$(cat "$counter_file" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" >"$counter_file"
mv "$SANDBOX/fzf/stdin" "$SANDBOX/fzf/$count.in"
echo "$count $*" >>"$SANDBOX/fzf.calls"
[ -f "$SANDBOX/fzf/$count.out" ] && cat "$SANDBOX/fzf/$count.out"
status=0
[ -f "$SANDBOX/fzf/$count.status" ] && status=$(cat "$SANDBOX/fzf/$count.status")
exit "$status"
STUB
    chmod +x "$stub_directory"/*
}

remove_gh_from_path() {
    local directory
    local -a directories kept_directories=()
    IFS=: read -ra directories <<<"$PATH"
    for directory in "${directories[@]}"; do
        [[ -x "$directory/gh" ]] && continue
        kept_directories+=("$directory")
    done
    PATH=$(IFS=:; echo "${kept_directories[*]}")
}

enter_sandbox() {
    SANDBOX=$(mktemp -d)
    export SANDBOX
    export HOME="$SANDBOX/home"
    export TMUX_TMPDIR="$SANDBOX/tmux"
    export SHELL=/bin/sh
    unset TMUX TMUX_PANE XDG_CONFIG_HOME XDG_CACHE_HOME
    mkdir -p "$HOME/dev" "$HOME/.claude/projects" "$TMUX_TMPDIR"
    [[ "$TMUX_TMPDIR" == "$SANDBOX"/* ]] || { echo "refusing to run: tmux socket outside the sandbox" >&2; exit 1; }
    write_stubs
    remove_gh_from_path
    export PATH="$SANDBOX/stubs:$PATH"
}

leave_sandbox() {
    tmux kill-server 2>/dev/null
    rm -rf -- "$SANDBOX"
}

# Helpers

fzf_answer() {
    local call_number="$1" output="$2" status="${3:-0}"
    printf '%s' "$output" >"$SANDBOX/fzf/$call_number.out"
    printf '%s' "$status" >"$SANDBOX/fzf/$call_number.status"
}

fzf_call_count() {
    [[ -f "$SANDBOX/fzf.calls" ]] || { echo 0; return; }
    wc -l <"$SANDBOX/fzf.calls" | tr -d ' '
}

install_gh_stub() {
    mkdir -p "$SANDBOX/gh"
    cat >"$SANDBOX/stubs/gh" <<'STUB'
#!/bin/sh
echo "$*" >>"$SANDBOX/gh.log"
if [ "$1" = "api" ]; then
    [ -f "$SANDBOX/gh/api.status" ] && exit "$(cat "$SANDBOX/gh/api.status")"
    case "$*" in
        *affiliation=owner*) cat "$SANDBOX/gh/owner" 2>/dev/null ;;
        *affiliation=organization_member*) cat "$SANDBOX/gh/organization" 2>/dev/null ;;
    esac
    exit 0
fi
if [ "$1 $2" = "repo clone" ]; then
    [ -f "$SANDBOX/gh/clone.status" ] && exit "$(cat "$SANDBOX/gh/clone.status")"
    mkdir -p "$4"
    exit 0
fi
exit 1
STUB
    chmod +x "$SANDBOX/stubs/gh"
}

github_cache_file() {
    echo "$HOME/.cache/dotfiles/github-repositories"
}

write_github_cache() {
    mkdir -p "$(dirname "$(github_cache_file)")"
    printf '%s\n' "$@" >"$(github_cache_file)"
}

picker_github_rows() {
    grep '^github' "$SANDBOX/fzf/1.in" || true
}

github_entry_line() {
    printf 'github%s%s%s%s%s\n' "$TAB" "$1" "$TAB" "$TAB" "$1  (GitHub, à cloner)"
}

claude_entry_line() {
    # shellcheck source-path=SCRIPTDIR source=layouts.sh
    (source "$TMUX_DIRECTORY/layouts.sh"; print_layout_entries | head -n 1)
}

project_entry_line() {
    printf 'project%s%s%s%s%s\n' "$TAB" "$HOME/dev/$1" "$TAB" "$TAB" "$1  (nouvelle session)"
}

encode_path() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9' '-'
}

make_history() {
    local directory="$1" history_directory
    history_directory="$HOME/.claude/projects/$(encode_path "$directory")"
    mkdir -p "$history_directory"
    : >"$history_directory/conversation.jsonl"
}

pane_count() {
    tmux list-panes -s -t "=$1" 2>/dev/null | wc -l | tr -d ' '
}

window_count() {
    tmux list-windows -t "=$1" 2>/dev/null | wc -l | tr -d ' '
}

has_session() {
    tmux has-session -t "=$1" 2>/dev/null
}

wait_for_claude_log() {
    local attempt
    for ((attempt = 0; attempt < POLL_ATTEMPTS; attempt++)); do
        [[ -s "$SANDBOX/claude.log" ]] && return 0
        sleep "$POLL_INTERVAL_SECONDS"
    done
    record_failure "claude.log never written"
}

run_script() {
    local script="$1"
    shift
    LAST_STATUS=0
    bash "$TMUX_DIRECTORY/$script" "$@" </dev/null >"$SANDBOX/stdout" 2>"$SANDBOX/stderr" || LAST_STATUS=$?
    LAST_STDERR=$(cat "$SANDBOX/stderr")
}

# projects.sh and workspace.sh

should_detect_claude_history_only_with_a_jsonl_file() {
    # shellcheck source-path=SCRIPTDIR source=workspace.sh
    source "$TMUX_DIRECTORY/workspace.sh"
    set +e
    local directory="$HOME/dev/my.app" history_directory
    history_directory="$HOME/.claude/projects/$(encode_path "$directory")"
    has_claude_history "$directory" && record_failure "history reported for a missing folder"
    mkdir -p "$history_directory/memory"
    has_claude_history "$directory" && record_failure "history reported with only memory/"
    : >"$history_directory/conversation.jsonl"
    has_claude_history "$directory" || record_failure "history missing with a jsonl file"
}

should_validate_project_names() {
    # shellcheck source-path=SCRIPTDIR source=projects.sh
    source "$TMUX_DIRECTORY/projects.sh"
    set +e
    local name
    for name in foo my-app.v2 _a; do
        is_valid_project_name "$name" || record_failure "rejected [$name]"
    done
    for name in .x -x a/b ""; do
        ! is_valid_project_name "$name" || record_failure "accepted [$name]"
    done
}

should_resume_claude_when_new_session_has_history() {
    mkdir -p "$HOME/dev/app"
    make_history "$HOME/dev/app"
    run_script workspace.sh claude-shells "$HOME/dev/app" app
    wait_for_claude_log
    assert_equals 3 "$(pane_count app)" panes
    assert_contains "$(cat "$SANDBOX/claude.log")" "--continue"
}

should_start_fresh_claude_when_new_session_has_no_history() {
    mkdir -p "$HOME/dev/app"
    run_script workspace.sh claude "$HOME/dev/app" app
    wait_for_claude_log
    assert_equals 1 "$(pane_count app)" panes
    assert_not_contains "$(cat "$SANDBOX/claude.log")" "--continue"
}

should_not_start_claude_for_the_shell_layout() {
    mkdir -p "$HOME/dev/app"
    run_script workspace.sh shell "$HOME/dev/app" app
    assert_equals 1 "$(pane_count app)" panes
    assert_no_file "$SANDBOX/claude.log"
}

should_add_a_fresh_window_to_an_existing_session() {
    mkdir -p "$HOME/dev/app"
    make_history "$HOME/dev/app"
    run_script workspace.sh shell "$HOME/dev/app" app
    run_script workspace.sh claude-shells "$HOME/dev/app" app
    wait_for_claude_log
    assert_equals 2 "$(window_count app)" windows
    assert_not_contains "$(cat "$SANDBOX/claude.log")" "--continue"
}

should_fail_on_unknown_layout() {
    mkdir -p "$HOME/dev/app"
    run_script workspace.sh bogus "$HOME/dev/app" app
    assert_equals 1 "$LAST_STATUS" status
    has_session app && record_failure "session created"
}

# session.sh

should_create_project_and_session_when_name_is_unknown() {
    fzf_answer 1 $'c\n'
    run_script session.sh newproj
    wait_for_claude_log
    assert_file_exists "$HOME/dev/newproj"
    assert_equals 1 "$(pane_count newproj)" panes
    assert_contains "$(cat "$SANDBOX/claude.log")" "$HOME/dev/newproj"
}

should_create_nothing_when_layout_question_is_cancelled() {
    fzf_answer 1 "" 130
    run_script session.sh newproj
    assert_no_file "$HOME/dev/newproj"
    has_session newproj && record_failure "session created"
}

should_reject_invalid_project_name_without_asking() {
    run_script session.sh .x
    assert_contains "$LAST_STDERR" "invalid project name"
    assert_no_file "$HOME/dev/.x"
    assert_equals 0 "$(fzf_call_count)" fzf_calls
}

should_open_known_project_with_the_chosen_layout() {
    mkdir -p "$HOME/dev/existing"
    fzf_answer 1 "$(printf '\n%s\n' "$(claude_entry_line)")"
    run_script session.sh existing
    assert_equals 3 "$(pane_count existing)" panes
}

should_not_ask_layout_when_session_exists() {
    mkdir -p "$HOME/dev/existing"
    run_script workspace.sh shell "$HOME/dev/existing" existing
    run_script session.sh existing
    assert_equals 0 "$(fzf_call_count)" fzf_calls
    assert_equals 1 "$(window_count existing)" windows
}

should_open_path_with_the_chosen_layout() {
    mkdir -p "$HOME/dev/existing"
    fzf_answer 1 $'s\n'
    run_script session.sh "$HOME/dev/existing"
    assert_equals 1 "$(pane_count existing)" panes
    assert_no_file "$SANDBOX/claude.log"
}

# session-picker.sh

should_create_project_from_a_query_without_match() {
    fzf_answer 1 $'zz\n' 1
    fzf_answer 2 $'s\n'
    run_script session-picker.sh
    assert_file_exists "$HOME/dev/zz"
    has_session zz || record_failure "session zz missing"
}

should_create_project_on_alt_enter_even_with_a_match() {
    mkdir -p "$HOME/dev/other"
    fzf_answer 1 "$(printf 'proj\nalt-enter\n%s\n' "$(project_entry_line other)")"
    fzf_answer 2 $'s\n'
    run_script session-picker.sh
    assert_file_exists "$HOME/dev/proj"
    has_session proj || record_failure "session proj missing"
    has_session other && record_failure "matched project opened"
}

should_create_nothing_when_picker_is_cancelled() {
    mkdir -p "$HOME/dev/other"
    fzf_answer 1 "" 130
    run_script session-picker.sh
    assert_equals 1 "$(fzf_call_count)" fzf_calls
    tmux list-sessions >/dev/null 2>&1 && record_failure "session created"
}

should_reject_invalid_name_typed_in_the_picker() {
    fzf_answer 1 $'.bad\nalt-enter\n'
    run_script session-picker.sh
    [[ "$LAST_STATUS" -ne 0 ]] || record_failure "exit status 0"
    assert_contains "$LAST_STDERR" "invalide"
    assert_no_file "$HOME/dev/.bad"
    assert_equals 1 "$(fzf_call_count)" fzf_calls
}

# GitHub repositories

should_list_uncloned_repositories_in_the_picker_and_hide_the_ones_with_a_local_counterpart() {
    install_gh_stub
    mkdir -p "$HOME/dev/cloned" "$HOME/notes" "$HOME/dotfiles" "$HOME/elsewhere"
    run_script workspace.sh shell "$HOME/elsewhere" opened
    write_github_cache me/fresh org/Team me/cloned me/notes me/dotfiles me/opened
    fzf_answer 1 "" 130
    run_script session-picker.sh
    assert_equals "$(github_entry_line me/fresh)"$'\n'"$(github_entry_line org/Team)" "$(picker_github_rows)" github_rows
}

should_ignore_invalid_lines_of_the_cache() {
    install_gh_stub
    write_github_cache x/.hidden x/-rf "bad line" 'bad owner/name' me/ok
    fzf_answer 1 "" 130
    run_script session-picker.sh
    assert_equals "$(github_entry_line me/ok)" "$(picker_github_rows)" github_rows
}

should_not_list_github_repositories_when_gh_is_absent() {
    write_github_cache me/fresh
    fzf_answer 1 "" 130
    run_script session-picker.sh
    assert_equals "" "$(picker_github_rows)" github_rows
}

should_clone_then_open_the_session_when_a_github_row_is_chosen() {
    install_gh_stub
    write_github_cache me/fresh
    fzf_answer 1 "$(printf '\n\n%s\n' "$(github_entry_line me/fresh)")"
    fzf_answer 2 $'s\n'
    run_script session-picker.sh
    assert_file_exists "$HOME/dev/fresh"
    assert_no_file "$HOME/dev/.fresh.clone"
    has_session fresh || record_failure "session fresh missing"
    assert_contains "$(cat "$SANDBOX/gh.log")" "repo clone me/fresh $HOME/dev/.fresh.clone"
}

should_clone_nothing_when_the_layout_question_of_a_github_row_is_cancelled() {
    install_gh_stub
    write_github_cache me/fresh
    fzf_answer 1 "$(printf '\n\n%s\n' "$(github_entry_line me/fresh)")"
    fzf_answer 2 "" 130
    run_script session-picker.sh
    assert_no_file "$SANDBOX/gh.log"
    assert_no_file "$HOME/dev/fresh"
    has_session fresh && record_failure "session created"
}

should_clone_a_cached_repository_when_its_name_is_typed_in_the_picker() {
    install_gh_stub
    write_github_cache me/fresh
    fzf_answer 1 $'fresh\nalt-enter\n'
    fzf_answer 2 $'s\n'
    run_script session-picker.sh
    assert_file_exists "$HOME/dev/fresh"
    assert_contains "$(cat "$SANDBOX/gh.log")" "repo clone me/fresh"
}

should_clone_a_cached_repository_when_its_name_is_given_to_t_in_another_case() {
    install_gh_stub
    write_github_cache me/Fresh
    fzf_answer 1 $'s\n'
    run_script session.sh fresh
    assert_file_exists "$HOME/dev/Fresh"
    assert_no_file "$HOME/dev/.Fresh.clone"
    has_session Fresh || record_failure "session Fresh missing"
    assert_contains "$(cat "$SANDBOX/gh.log")" "repo clone me/Fresh $HOME/dev/.Fresh.clone"
}

should_create_an_empty_folder_without_calling_gh_when_the_name_is_not_cached() {
    install_gh_stub
    write_github_cache me/other
    fzf_answer 1 $'s\n'
    run_script session.sh newproj
    assert_file_exists "$HOME/dev/newproj"
    assert_no_file "$SANDBOX/gh.log"
}

should_create_an_empty_folder_when_gh_is_absent_even_if_the_name_is_cached() {
    write_github_cache me/fresh
    fzf_answer 1 $'s\n'
    run_script session.sh fresh
    assert_file_exists "$HOME/dev/fresh"
    has_session fresh || record_failure "session fresh missing"
}

should_fail_without_folder_or_session_when_the_clone_fails() {
    install_gh_stub
    write_github_cache me/fresh
    echo 1 >"$SANDBOX/gh/clone.status"
    fzf_answer 1 $'s\n'
    run_script session.sh fresh
    [[ "$LAST_STATUS" -ne 0 ]] || record_failure "exit status 0"
    assert_contains "$LAST_STDERR" "Échec du clone de me/fresh"
    assert_no_file "$HOME/dev/fresh"
    assert_no_file "$HOME/dev/.fresh.clone"
    has_session fresh && record_failure "session created"
}

should_refuse_to_clone_over_an_existing_staging_folder() {
    install_gh_stub
    write_github_cache me/fresh
    mkdir -p "$HOME/dev/.fresh.clone"
    fzf_answer 1 $'s\n'
    run_script session.sh fresh
    [[ "$LAST_STATUS" -ne 0 ]] || record_failure "exit status 0"
    assert_contains "$LAST_STDERR" "supprimez"
    assert_no_file "$SANDBOX/gh.log"
}

should_not_clone_a_repository_that_has_a_local_counterpart_outside_dev() {
    install_gh_stub
    mkdir -p "$HOME/notes"
    write_github_cache me/notes
    fzf_answer 1 $'s\n'
    run_script session.sh notes
    assert_no_file "$SANDBOX/gh.log"
    assert_no_file "$HOME/dev/.notes.clone"
}

should_complete_the_names_of_uncloned_repositories() {
    install_gh_stub
    mkdir -p "$HOME/dev/cloned"
    write_github_cache me/fresh me/cloned
    run_script session.sh --complete
    assert_equals $'cloned\nfresh' "$(cat "$SANDBOX/stdout")" completions
}

should_refresh_the_cache_with_the_personal_repository_first_when_names_collide() {
    install_gh_stub
    printf 'me/Shared\nme/solo\n' >"$SANDBOX/gh/owner"
    printf 'org/shared\norg/team\n' >"$SANDBOX/gh/organization"
    run_script session.sh --refresh-github-cache
    assert_equals 0 "$LAST_STATUS" status
    assert_equals $'me/Shared\nme/solo\norg/team' "$(cat "$(github_cache_file)")" cache
    assert_equals 600 "$(stat -c %a "$(github_cache_file)")" mode
}

should_keep_the_old_cache_without_leftovers_when_gh_fails_during_a_refresh() {
    install_gh_stub
    write_github_cache me/old
    echo 1 >"$SANDBOX/gh/api.status"
    run_script session.sh --refresh-github-cache
    assert_equals me/old "$(cat "$(github_cache_file)")" cache
    assert_equals 1 "$(find "$(dirname "$(github_cache_file)")" -type f | wc -l | tr -d ' ')" files
}

# Runner

run_test() {
    local test_name="$1" failures
    failures=$(
        enter_sandbox
        trap leave_sandbox EXIT
        "$test_name"
        cat "$SANDBOX/failures" 2>/dev/null
    )
    if [[ -n "$failures" ]]; then
        echo "FAIL $test_name: ${failures//$'\n'/; }"
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
