#!/usr/bin/env bash
# Runs the steps of a machine role recipe one by one, with one result line per step (quiet mode) or verbose output.
# Usage: dev-update.sh [dev|server]
#   the step list is read from the Justfile recipe dependencies (just --dump), so it never drifts from `just dev`
#   DOTFILES_DIRECTORY overrides the repo location (tests); meant to run under update.sh (UPDATE_LOG, UPDATE_REPORT)
#   prompting recipes: `system` runs attached to the terminal (it asks to apply the upgrade), `gh-auth` is skipped
#   with a WARN when gh is not logged in (its login is interactive); every other step runs with stdin closed
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH
readonly SCRIPT_DIRECTORY="${SCRIPT_PATH%/*}"
readonly DOTFILES_DIRECTORY="${DOTFILES_DIRECTORY:-${SCRIPT_DIRECTORY%/*}}"
readonly JUSTFILE_PATH="$DOTFILES_DIRECTORY/Justfile"
readonly VISIBLE_RECIPES=" system "
readonly AUTH_RECIPE="gh-auth"

# shellcheck source=status.sh
# shellcheck source-path=SCRIPTDIR
source "$SCRIPT_DIRECTORY/status.sh"

list_steps() {
    local role="$1"
    just -f "$JUSTFILE_PATH" --dump --dump-format json |
        jq -r --arg role "$role" '.recipes[$role].dependencies[] | ([.recipe] + .arguments) | @tsv'
}

skip_unauthenticated_gh() {
    command -v gh >/dev/null && gh auth status >/dev/null 2>&1 && return 1
    warn "gh not authenticated, skipped $AUTH_RECIPE, run 'just $AUTH_RECIPE'"
    return 0
}

run_step() {
    local recipe="$1"
    shift
    local label="$recipe${*:+ $*}"
    if [ "$recipe" = "$AUTH_RECIPE" ] && skip_unauthenticated_gh; then
        return 0
    fi
    if [[ "$VISIBLE_RECIPES" == *" $recipe "* ]]; then
        run_visible_step "$label" just -f "$JUSTFILE_PATH" "$recipe" "$@"
        return
    fi
    run_quiet_step "$label" just -f "$JUSTFILE_PATH" "$recipe" "$@"
}

main() {
    local role="${1:-dev}" steps step_fields failed_count=0
    case "$role" in
        dev | server) ;;
        *)
            echo "Usage: dev-update.sh [dev|server]" >&2
            return 2
            ;;
    esac
    command -v jq >/dev/null || { echo "ERROR: jq is not installed, run 'just mise' first." >&2; return 1; }
    steps="$(list_steps "$role")" && [ -n "$steps" ] || {
        echo "ERROR: could not read the steps of the $role recipe from $JUSTFILE_PATH." >&2
        return 1
    }
    while IFS=$'\t' read -r -a step_fields; do
        run_step "${step_fields[@]}" || failed_count=$((failed_count + 1))
    done <<<"$steps"
    [ "$failed_count" -eq 0 ]
}

main "$@"
