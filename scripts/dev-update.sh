#!/usr/bin/env bash
# Runs the steps of a machine role recipe one by one, with one result line per step (quiet mode) or verbose output.
# Usage: dev-update.sh [dev|server]
#        dev-update.sh --list [dev|server]
#   --list prints the labels of the steps the run will count (one per line, `doctor-*` left out), without running anything
#   the step list is read from the Justfile recipe dependencies (just --dump), so it never drifts from `just dev`
#   DOTFILES_DIRECTORY overrides the repo location (tests); meant to run under update.sh (UPDATE_LOG, UPDATE_REPORT)
#   prompting recipes: `system` runs attached to the terminal (it asks to apply the upgrade), `gh-auth` is skipped
#   with a WARN when gh is not logged in (its login is interactive); every other step runs with stdin closed
#   root recipes (`build-deps`) keep the terminal so sudo can use its cached ticket; when no ticket is cached one visible
#   `sudo -v` asks for it first, and the root recipes are skipped with a WARN when it fails
#   `mise` gets a 1800 second timeout, other steps the default; `doctor-*` recipes are skipped (update.sh runs the doctor once)
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH
readonly SCRIPT_DIRECTORY="${SCRIPT_PATH%/*}"
readonly DOTFILES_DIRECTORY="${DOTFILES_DIRECTORY:-${SCRIPT_DIRECTORY%/*}}"
readonly JUSTFILE_PATH="$DOTFILES_DIRECTORY/Justfile"
readonly VISIBLE_RECIPES=" system "
readonly ROOT_RECIPES=" build-deps "
readonly LONG_RECIPES=" mise "
readonly AUTH_RECIPE="gh-auth"
readonly LONG_STEP_TIMEOUT_SECONDS=1800
readonly SUDO_LOGIN_TIMEOUT_SECONDS=120
readonly GH_TIMEOUT_SECONDS=30
HAS_ROOT_ACCESS=""

# shellcheck source=status.sh
# shellcheck source-path=SCRIPTDIR
source "$SCRIPT_DIRECTORY/status.sh"

list_steps() {
    local role="$1"
    just -f "$JUSTFILE_PATH" --dump --dump-format json |
        jq -r --arg role "$role" '.recipes[$role].dependencies[] | ([.recipe] + .arguments) | @tsv'
}

build_step_label() {
    local recipe="$1"
    shift
    echo "$recipe${*:+ $*}"
}

list_step_labels() {
    local step_fields
    while IFS=$'\t' read -r -a step_fields; do
        [[ "${step_fields[0]}" == doctor-* ]] || build_step_label "${step_fields[@]}"
    done
}

skip_unauthenticated_gh() {
    command -v gh >/dev/null && timeout "$GH_TIMEOUT_SECONDS" gh auth status >/dev/null 2>&1 && return 1
    warn "gh not authenticated, skipped $AUTH_RECIPE, run 'just $AUTH_RECIPE'"
    return 0
}

ensure_root_access() {
    if [ -z "$HAS_ROOT_ACCESS" ]; then
        HAS_ROOT_ACCESS=no
        if sudo -n true 2>/dev/null; then
            HAS_ROOT_ACCESS=yes
        else
            echo "Mot de passe sudo requis pour les étapes root :"
            ! timeout --foreground "$SUDO_LOGIN_TIMEOUT_SECONDS" sudo -v || HAS_ROOT_ACCESS=yes
        fi
    fi
    [ "$HAS_ROOT_ACCESS" = yes ]
}

run_step() {
    local recipe="$1"
    shift
    local label
    label="$(build_step_label "$recipe" "$@")"
    if [[ "$recipe" == doctor-* ]]; then
        return 0
    fi
    if [ "$recipe" = "$AUTH_RECIPE" ] && skip_unauthenticated_gh; then
        report_skipped_step "$label"
        return 0
    fi
    if [[ "$ROOT_RECIPES" == *" $recipe "* ]]; then
        if ! ensure_root_access; then
            warn "no sudo ticket, skipped $recipe, run 'just $recipe'"
            report_skipped_step "$label"
            return 0
        fi
        run_quiet_root_step "$label" just -f "$JUSTFILE_PATH" "$recipe" "$@"
        return
    fi
    if [[ "$LONG_RECIPES" == *" $recipe "* ]]; then
        STEP_TIMEOUT_SECONDS="$LONG_STEP_TIMEOUT_SECONDS" run_quiet_step "$label" just -f "$JUSTFILE_PATH" "$recipe" "$@"
        return
    fi
    if [[ "$VISIBLE_RECIPES" == *" $recipe "* ]]; then
        run_visible_step "$label" just -f "$JUSTFILE_PATH" "$recipe" "$@"
        return
    fi
    run_quiet_step "$label" just -f "$JUSTFILE_PATH" "$recipe" "$@"
}

main() {
    local is_listing=0 role steps step_fields failed_count=0
    if [ "${1:-}" = --list ]; then
        is_listing=1
        shift
    fi
    role="${1:-dev}"
    case "$role" in
        dev | server) ;;
        *)
            echo "Usage: dev-update.sh [--list] [dev|server]" >&2
            return 2
            ;;
    esac
    command -v jq >/dev/null || { echo "ERROR: jq is not installed, run 'just mise' first." >&2; return 1; }
    steps="$(list_steps "$role")" && [ -n "$steps" ] || {
        echo "ERROR: could not read the steps of the $role recipe from $JUSTFILE_PATH." >&2
        return 1
    }
    if [ "$is_listing" -eq 1 ]; then
        list_step_labels <<<"$steps"
        return
    fi
    while IFS=$'\t' read -r -a step_fields; do
        run_step "${step_fields[@]}" || failed_count=$((failed_count + 1))
    done <<<"$steps"
    [ "$failed_count" -eq 0 ]
}

main "$@"
