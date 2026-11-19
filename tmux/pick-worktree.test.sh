#!/usr/bin/env bash
# Tests of pick-worktree.sh (everything but the fzf picker), run on throwaway git repositories.
# Usage: pick-worktree.test.sh
#   prints `ok <name>` or `FAIL <name>: <detail>` per test and a summary line; exits 1 when a test failed
# Isolation: every test gets its own repository in a mktemp -d sandbox, with a fake HOME and no system git config, removed afterwards.

set -uo pipefail

TMUX_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TMUX_DIRECTORY
readonly SCRIPT="$TMUX_DIRECTORY/pick-worktree.sh"

passed_count=0
failed_count=0

new_repository() {
    SANDBOX=$(mktemp -d)
    export HOME="$SANDBOX/home"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@localhost GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@localhost
    mkdir -p "$HOME" "$SANDBOX/repo"
    cd "$SANDBOX/repo" || exit 1
    git init -q -b main .
    echo "one" >seed.txt
    git add -A
    git commit -q -m "initial"
}

add_worktree() {
    git worktree add -q "$SANDBOX/$1" -b "$1"
}

run_test() {
    local test_name="$1" output
    new_repository
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

assert_equals() {
    [[ "$1" == "$2" ]] || echo "expected [$2], got [$1]"
}

assert_contains() {
    [[ "$1" == *"$2"* ]] || echo "expected [$1] to contain [$2]"
}

assert_not_contains() {
    [[ "$1" != *"$2"* ]] || echo "expected [$1] not to contain [$2]"
}

line_of() {
    grep -F "$2" <<<"$1" | head -n 1
}

should_print_the_top_level_when_the_repository_has_a_single_worktree() {
    mkdir sub
    cd sub || exit 1
    assert_equals "$("$SCRIPT")" "$SANDBOX/repo"
}

should_print_the_current_directory_outside_a_git_repository() {
    local outside="$SANDBOX/outside"
    mkdir "$outside"
    cd "$outside" || exit 1
    assert_equals "$("$SCRIPT")" "$outside"
}

should_list_the_most_recently_edited_worktree_first() {
    add_worktree agent-a
    echo "main edit" >main-edit.txt
    touch -d "now + 1 hour" main-edit.txt
    echo "agent edit" >"$SANDBOX/agent-a/agent-edit.txt"
    touch -d "now + 2 hours" "$SANDBOX/agent-a/agent-edit.txt"
    assert_contains "$("$SCRIPT" --list | head -n 1)" "agent-a"
}

should_leave_out_a_worktree_whose_directory_was_deleted() {
    add_worktree agent-a
    rm -rf "$SANDBOX/agent-a"
    assert_not_contains "$("$SCRIPT" --list)" "agent-a"
}

should_mark_the_worktree_holding_the_current_directory() {
    add_worktree agent-a
    mkdir "$SANDBOX/agent-a/sub"
    cd "$SANDBOX/agent-a/sub" || exit 1
    local lines
    lines=$("$SCRIPT" --list)
    assert_contains "$(line_of "$lines" "agent-a")" "(ici)"
    assert_not_contains "$(line_of "$lines" "repo ·")" "(ici)"
}

should_count_the_uncommitted_changes_of_each_worktree() {
    add_worktree agent-a
    echo "two" >>seed.txt
    echo "new" >untracked.txt
    local lines
    lines=$("$SCRIPT" --list)
    assert_contains "$(line_of "$lines" "repo ·")" "2 changements"
    assert_contains "$(line_of "$lines" "agent-a")" "aucun changement"
}

for test_name in $(declare -F | awk '{print $3}' | grep '^should_'); do
    run_test "$test_name"
done

echo "$passed_count passed, $failed_count failed"
[[ "$failed_count" -eq 0 ]]
