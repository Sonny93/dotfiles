#!/usr/bin/env bash
# Prints the distribution family (debian or arch) from os-release, so callers pick apt or pacman.
# Usage: distro-family.sh
#   stdout: `debian` or `arch`; exit 1 with an ERROR line on stderr when the file is unreadable or the family is unsupported
# Matching: ID first, then each word of ID_LIKE in order; the first word equal to debian or arch wins (Ubuntu -> debian, CachyOS -> arch).
# Override: OS_RELEASE_FILE replaces /etc/os-release (used by the tests).

set -euo pipefail

readonly OS_RELEASE_PATH="${OS_RELEASE_FILE:-/etc/os-release}"
readonly SUPPORTED_FAMILIES=(debian arch)

read_os_release_field() {
    local field="$1"
    (
        # shellcheck disable=SC1090
        . "$OS_RELEASE_PATH"
        printf '%s' "${!field:-}"
    )
}

is_supported_family() {
    local candidate="$1" family
    for family in "${SUPPORTED_FAMILIES[@]}"; do
        [[ "$candidate" == "$family" ]] && return 0
    done
    return 1
}

find_family() {
    local distribution_id="$1" distribution_like="$2" word
    for word in $distribution_id $distribution_like; do
        if is_supported_family "$word"; then
            printf '%s\n' "$word"
            return 0
        fi
    done
    return 1
}

main() {
    local distribution_id distribution_like
    if [[ ! -r "$OS_RELEASE_PATH" ]]; then
        echo "ERROR: cannot read $OS_RELEASE_PATH. Only the Debian and Arch families are supported." >&2
        exit 1
    fi
    distribution_id="$(read_os_release_field ID)"
    distribution_like="$(read_os_release_field ID_LIKE)"
    find_family "$distribution_id" "$distribution_like" && return 0
    echo "ERROR: unsupported distribution (ID=${distribution_id:-unset}, ID_LIKE=${distribution_like:-unset}). Only the Debian and Arch families are supported." >&2
    exit 1
}

main
