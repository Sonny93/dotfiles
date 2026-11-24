#!/usr/bin/env bash
# Tests of format-upgrades.sh, the pacman upgrade preview table, fed with fixture text (no pacman involved).
# Usage: format-upgrades.test.sh
#   prints `ok <name>` or `FAIL <name>: <detail>` per test and a summary line; exits 1 when a test failed

set -uo pipefail

SCRIPT_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
readonly FORMAT_SCRIPT="$SCRIPT_DIRECTORY/format-upgrades.sh"
SANDBOX="$(mktemp -d)"
readonly SANDBOX
trap 'rm -rf "$SANDBOX"' EXIT

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

write_installed() {
    printf 'zlib 1.3-1\nlinux 6.1-1\nlongername-package 2-1\n' >"$SANDBOX/installed"
}

test_table_is_sorted_and_aligned() {
    local detail="" output expected
    write_installed
    output="$(printf 'zlib 1.3-2\nlongername-package 3-1\nlinux 6.2-1\n' | "$FORMAT_SCRIPT" "$SANDBOX/installed")"
    expected=$'linux               6.1-1 -> 6.2-1\nlongername-package  2-1 -> 3-1\nzlib                1.3-1 -> 1.3-2\n3 packages'
    [[ "$output" == "$expected" ]] || detail="output [$output]"
    report "should print a sorted, aligned table with a package count" "$detail"
}

test_new_package_is_marked() {
    local detail="" output
    write_installed
    output="$(printf 'newdep 1.0-1\n' | "$FORMAT_SCRIPT" "$SANDBOX/installed")"
    [[ "$output" == $'newdep  (new) -> 1.0-1\n1 package' ]] || detail="output [$output]"
    report "should show a package without installed version as (new) with a singular count" "$detail"
}

test_empty_transaction_prints_nothing() {
    local detail="" output format_status=0
    write_installed
    output="$("$FORMAT_SCRIPT" "$SANDBOX/installed" </dev/null)" || format_status=$?
    [[ "$format_status" == 0 && -z "$output" ]] || detail="status $format_status output [$output]"
    report "should print nothing for an empty transaction" "$detail"
}

test_missing_installed_file_is_usage_error() {
    local detail="" format_status=0
    "$FORMAT_SCRIPT" "$SANDBOX/absent" </dev/null >/dev/null 2>&1 || format_status=$?
    [[ "$format_status" == 2 ]] || detail="status $format_status"
    report "should exit 2 when the installed versions file is unreadable" "$detail"
}

test_table_is_sorted_and_aligned
test_new_package_is_marked
test_empty_transaction_prints_nothing
test_missing_installed_file_is_usage_error

echo "$passed_count passed, $failed_count failed"
[[ "$failed_count" == 0 ]]
