#!/usr/bin/env bash
# Tests of working-tree-diff.sh, run on throwaway git repositories.
# Usage: working-tree-diff.test.sh
#   prints `ok <name>` or `FAIL <name>: <detail>` per test and a summary line; exits 1 when a test failed
# Isolation: every test gets its own repository in a mktemp -d sandbox, with a fake HOME and no system git config, removed afterwards.

set -uo pipefail

TMUX_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TMUX_DIRECTORY
readonly SCRIPT="$TMUX_DIRECTORY/working-tree-diff.sh"

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
}

commit_all() {
    git add -A
    git commit -q -m "initial"
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

assert_contains() {
    [[ "$1" == *"$2"* ]] || echo "expected the diff to contain [$2], got [$1]"
}

assert_not_contains() {
    [[ "$1" != *"$2"* ]] || echo "expected the diff not to contain [$2], got [$1]"
}

should_show_a_modified_tracked_file() {
    echo "one" >tracked.txt
    commit_all
    echo "two" >>tracked.txt
    assert_contains "$("$SCRIPT")" "+two"
}

should_show_a_staged_file() {
    echo "one" >seed.txt
    commit_all
    echo "staged content" >staged.txt
    git add staged.txt
    assert_contains "$("$SCRIPT")" "+staged content"
}

should_show_an_untracked_file_whose_name_has_a_space() {
    echo "one" >seed.txt
    commit_all
    echo "brand new" >"new file.txt"
    assert_contains "$("$SCRIPT")" "+brand new"
}

should_not_show_an_ignored_file() {
    echo "ignored.txt" >.gitignore
    echo "one" >seed.txt
    commit_all
    echo "secret" >ignored.txt
    assert_not_contains "$("$SCRIPT")" "secret"
}

should_show_files_in_a_repository_without_any_commit() {
    echo "first" >staged.txt
    git add staged.txt
    echo "second" >untracked.txt
    local output
    output=$("$SCRIPT")
    assert_contains "$output" "+first"
    assert_contains "$output" "+second"
}

should_print_nothing_when_nothing_changed() {
    echo "one" >seed.txt
    commit_all
    [[ -z "$("$SCRIPT")" ]] || echo "expected an empty diff"
}

for test_name in $(declare -F | awk '{print $3}' | grep '^should_'); do
    run_test "$test_name"
done

echo "$passed_count passed, $failed_count failed"
[[ "$failed_count" -eq 0 ]]
