#!/usr/bin/env bash
# End-to-end tests of arch-upgrade.sh (the whole script, sourcing the real status.sh) with stubs on PATH for checkupdates, pacman, paru, sudo and systemd-run.
# Usage: arch-upgrade.test.sh
#   prints `ok <name>` or `FAIL <name>: <detail>` per test and a summary line; exits 1 when a test failed
# Isolation: everything lives in a mktemp -d sandbox removed on exit; no real pacman, sudo or systemd command is ever run.

set -uo pipefail

SCRIPT_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
readonly UPGRADE_SCRIPT="$SCRIPT_DIRECTORY/arch-upgrade.sh"
SANDBOX="$(mktemp -d)"
readonly SANDBOX
trap 'rm -rf "$SANDBOX"' EXIT

passed_count=0
failed_count=0
output=""
exit_status=0

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

write_stub() {
    local name="$1" body="$2"
    printf '#!/usr/bin/env bash\n%s\n' "$body" >"$SANDBOX/bin/$name"
    chmod +x "$SANDBOX/bin/$name"
}

write_stubs() {
    mkdir -p "$SANDBOX/bin"
    write_stub checkupdates 'exit "${STUB_CHECKUPDATES_STATUS:-2}"'
    write_stub pacman 'case "$1" in
    -Q) echo "foo 1.0-1" ;;
    -Sup) echo "foo 2.0-1" ;;
    -Qdtq) exit 1 ;;
esac'
    write_stub paru 'exit 0'
    write_stub sudo 'echo "sudo $*" >>"$STUB_CALLS_FILE"'
    write_stub systemd-run 'echo "systemd-run $*" >>"$STUB_CALLS_FILE"'
}

run_upgrade() {
    : >"$SANDBOX/log"
    : >"$SANDBOX/report"
    : >"$SANDBOX/calls"
    output="$(
        PATH="$SANDBOX/bin:$PATH" TMPDIR="$SANDBOX" STUB_CHECKUPDATES_STATUS="$1" STUB_CALLS_FILE="$SANDBOX/calls" \
            UPDATE_LOG="$SANDBOX/log" UPDATE_REPORT="$SANDBOX/report" NO_COLOR=1 \
            bash "$UPGRADE_SCRIPT" </dev/null 2>&1
    )"
    exit_status=$?
}

test_nothing_to_upgrade() {
    local detail=""
    run_upgrade 2
    [[ "$exit_status" == 0 ]] || detail="exit status $exit_status [$output]"
    [[ "$output" == *"✓ system up to date"* ]] || detail="$detail output [$output]"
    [[ "$output" != *"readonly"* ]] || detail="$detail readonly error [$output]"
    [[ ! -s "$SANDBOX/calls" ]] || detail="$detail root commands ran [$(cat "$SANDBOX/calls")]"
    report "should exit 0 and print up to date when checkupdates exits 2" "$detail"
}

test_updates_without_terminal_skip_the_prompt() {
    local detail=""
    run_upgrade 0
    [[ "$exit_status" == 0 ]] || detail="exit status $exit_status [$output]"
    [[ "$output" == *"foo"* ]] || detail="$detail preview missing [$output]"
    [[ "$output" == *"pacman upgrade skipped, run 'just system' to apply it"* ]] || detail="$detail warn missing [$output]"
    [[ "$output" != *"readonly"* ]] || detail="$detail readonly error [$output]"
    grep -q '^WARN pacman upgrade skipped' "$SANDBOX/report" || detail="$detail report [$(cat "$SANDBOX/report")]"
    [[ ! -s "$SANDBOX/calls" ]] || detail="$detail root commands ran [$(cat "$SANDBOX/calls")]"
    report "should skip the upgrade with a WARN and exit 0 when updates are listed and there is no terminal" "$detail"
}

test_failed_preview_fails() {
    local detail=""
    run_upgrade 1
    [[ "$exit_status" == 1 ]] || detail="exit status $exit_status"
    grep -q '^ERROR pacman preview failed' "$SANDBOX/report" || detail="$detail report [$(cat "$SANDBOX/report")]"
    report "should fail with an ERROR when checkupdates fails for another reason" "$detail"
}

write_stubs
test_nothing_to_upgrade
test_updates_without_terminal_skip_the_prompt
test_failed_preview_fails

echo "$passed_count passed, $failed_count failed"
[[ "$failed_count" == 0 ]]
