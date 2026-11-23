#!/usr/bin/env bash
# Tests of update.sh against a temporary origin, clone and config directory, with stubbed just and tmux.
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
    printf '#!/usr/bin/env bash\necho "just $*" >>"%s"\n' "$SANDBOX/calls" >"$SANDBOX/bin/just"
    printf '#!/usr/bin/env bash\nexit 1\n' >"$SANDBOX/bin/tmux"
    chmod +x "$SANDBOX/bin/just" "$SANDBOX/bin/tmux"
}

setup_scenario() {
    rm -rf "$SANDBOX/origin.git" "$SANDBOX/clone" "$SANDBOX/peer" "$SANDBOX/config" "$SANDBOX/calls"
    mkdir -p "$SANDBOX/config/dotfiles"
    touch "$SANDBOX/calls"
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

run_update() {
    stdout="$(PATH="$SANDBOX/bin:$PATH" DOTFILES_DIRECTORY="$SANDBOX/clone" XDG_CONFIG_HOME="$SANDBOX/config" \
        "$UPDATE_SCRIPT" 2>"$SANDBOX/stderr")"
    exit_status=$?
    stderr="$(cat "$SANDBOX/stderr")"
    calls="$(cat "$SANDBOX/calls")"
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

write_stubs
test_hook_runs_and_not_just
test_server_role_runs_just
test_missing_role_fails
test_dirty_tree_skips_merge
test_upstream_ahead_merges_and_reexecs
test_up_to_date_does_not_reexec

echo "$passed_count passed, $failed_count failed"
[[ "$failed_count" == 0 ]]
