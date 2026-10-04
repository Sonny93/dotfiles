# Status helpers (ok, warn, info, check_link) for doctor recipes; meant to be sourced.
readonly COLOR_GREEN=$'\033[32m'
readonly COLOR_YELLOW=$'\033[33m'
readonly COLOR_BLUE=$'\033[34m'
readonly COLOR_RESET=$'\033[0m'

print_status() {
    local color="$1" label="$2"
    shift 2
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        printf '%s●%s %s: %s\n' "$color" "$COLOR_RESET" "$label" "$*"
    else
        printf '● %s: %s\n' "$label" "$*"
    fi
}

ok() { print_status "$COLOR_GREEN" OK "$*"; }
warn() { print_status "$COLOR_YELLOW" WARN "$*"; }
info() { print_status "$COLOR_BLUE" INFO "$*"; }

check_link() {
    local link="$1" target="$2" recipe="$3"
    if [ "$(readlink "$link")" = "$target" ]; then
        ok "$link -> $target"
    else
        warn "$link is not a symlink to $target, run 'just $recipe'"
    fi
}
