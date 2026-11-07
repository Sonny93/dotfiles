#!/usr/bin/env bash
# Tests of distro-family.sh against fixture os-release files.
# Usage: distro-family.test.sh
#   prints `ok <name>` or `FAIL <name>: <detail>` per test and a summary line; exits 1 when a test failed
# Isolation: fixtures live in a mktemp -d sandbox removed on exit; the real /etc/os-release is never read.

set -uo pipefail

SCRIPT_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
readonly DISTRO_FAMILY_SCRIPT="$SCRIPT_DIRECTORY/distro-family.sh"
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

run_script() {
    local fixture="$1"
    stdout="$(OS_RELEASE_FILE="$fixture" "$DISTRO_FAMILY_SCRIPT" 2>"$SANDBOX/stderr")"
    exit_status=$?
    stderr="$(cat "$SANDBOX/stderr")"
}

write_fixture() {
    local name="$1"
    shift
    printf '%s\n' "$@" >"$SANDBOX/$name"
    printf '%s' "$SANDBOX/$name"
}

test_family() {
    local name="$1" expected="$2" fixture detail=""
    shift 2
    fixture="$(write_fixture "$name" "$@")"
    run_script "$fixture"
    [[ "$stdout" == "$expected" ]] || detail="expected [$expected], got [$stdout]"
    [[ "$exit_status" == 0 ]] || detail="$detail exit status $exit_status"
    report "should print $expected for $name" "$detail"
}

test_unsupported_distribution() {
    local fixture detail=""
    fixture="$(write_fixture fedora 'ID=fedora' 'ID_LIKE="rhel centos"')"
    run_script "$fixture"
    [[ "$exit_status" == 1 ]] || detail="exit status $exit_status"
    [[ -z "$stdout" ]] || detail="$detail stdout [$stdout]"
    [[ "$stderr" == ERROR:*fedora* ]] || detail="$detail stderr [$stderr]"
    report "should fail with an error for fedora" "$detail"
}

test_missing_file() {
    local detail=""
    run_script "$SANDBOX/missing"
    [[ "$exit_status" == 1 ]] || detail="exit status $exit_status"
    [[ -z "$stdout" ]] || detail="$detail stdout [$stdout]"
    [[ "$stderr" == ERROR:* ]] || detail="$detail stderr [$stderr]"
    report "should fail with an error when the file is missing" "$detail"
}

test_family debian debian 'ID=debian'
test_family ubuntu debian 'ID=ubuntu' 'ID_LIKE=debian'
test_family cachyos arch 'ID=cachyos' 'ID_LIKE=arch'
test_family arch arch 'ID=arch'
test_family quoted-id-like debian 'ID=pop' 'ID_LIKE="ubuntu debian"'
test_unsupported_distribution
test_missing_file

echo "$passed_count passed, $failed_count failed"
[[ "$failed_count" == 0 ]]
