#!/usr/bin/env bash
# Pulls the dotfiles repo (fast-forward only), re-applies the machine setup, then restarts idle Claude Code instances.
# Usage: update.sh
#   DOTFILES_DIRECTORY overrides the repo location (tests); DOTFILES_UPDATE_PULLED=1 marks the re-exec after a pull
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH
readonly SCRIPT_DIRECTORY="${SCRIPT_PATH%/*}"
readonly DOTFILES_DIRECTORY="${DOTFILES_DIRECTORY:-${SCRIPT_DIRECTORY%/*}}"
readonly CONFIG_DIRECTORY="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
readonly HOOK_PATH="$CONFIG_DIRECTORY/update-hook"
readonly ROLE_PATH="$CONFIG_DIRECTORY/role"
readonly MAIN_BRANCH="main"
readonly STEP_STYLE='\e[1;30;43m'
readonly DONE_STYLE='\e[1;30;42m'
readonly RESET_STYLE='\e[0m'

# shellcheck source=status.sh
# shellcheck source-path=SCRIPTDIR
source "$SCRIPT_DIRECTORY/status.sh"

print_banner() {
    local style="$1" text="$2"
    printf '\n%b %s %b\n\n' "$style" "$text" "$RESET_STYLE"
}

git_dotfiles() {
    git -C "$DOTFILES_DIRECTORY" "$@"
}

can_fast_forward() {
    if [ "$(git_dotfiles rev-parse --abbrev-ref HEAD)" != "$MAIN_BRANCH" ]; then
        warn "dotfiles is not on $MAIN_BRANCH, skipping the pull"
        return 1
    fi
    if [ -n "$(git_dotfiles status --porcelain --untracked-files=no)" ]; then
        warn "dotfiles has uncommitted changes, skipping the pull"
        return 1
    fi
    if ! git_dotfiles rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        warn "dotfiles has no upstream branch, skipping the pull"
        return 1
    fi
    if ! git_dotfiles fetch --quiet; then
        warn "git fetch failed (offline?), continuing without pulling"
        return 1
    fi
    if ! git_dotfiles merge-base --is-ancestor HEAD '@{u}'; then
        warn "dotfiles has diverged from its upstream, skipping the pull"
        return 1
    fi
    return 0
}

pull_dotfiles() {
    can_fast_forward || return 1
    if [ "$(git_dotfiles rev-parse HEAD)" = "$(git_dotfiles rev-parse '@{u}')" ]; then
        echo "Already up to date"
        return 1
    fi
    git_dotfiles log --oneline 'HEAD..@{u}'
    git_dotfiles merge --ff-only '@{u}'
}

run_pull_step() {
    print_banner "$STEP_STYLE" "1/3 dotfiles (git pull)"
    if [ "${DOTFILES_UPDATE_PULLED:-}" = "1" ]; then
        echo "Pulled already, running the pulled version"
        return 0
    fi
    if pull_dotfiles; then
        exec env DOTFILES_UPDATE_PULLED=1 "$SCRIPT_PATH"
    fi
}

run_setup_recipe() {
    local role
    role="$(cat "$ROLE_PATH" 2>/dev/null || true)"
    if [ "$role" != "dev" ] && [ "$role" != "server" ]; then
        echo "ERROR: no machine role recorded, run 'just dev' or 'just server' once." >&2
        return 1
    fi
    just -f "$DOTFILES_DIRECTORY/Justfile" "$role"
}

run_apply_step() {
    print_banner "$STEP_STYLE" "2/3 Apply"
    if [ -x "$HOOK_PATH" ]; then
        "$HOOK_PATH"
        return
    fi
    run_setup_recipe
}

run_claude_step() {
    print_banner "$STEP_STYLE" "3/3 Claude Code instances (tmux)"
    if command -v claude >/dev/null && tmux list-sessions >/dev/null 2>&1; then
        "$DOTFILES_DIRECTORY/tmux/restart-claude.sh"
        return
    fi
    echo "No Claude Code in tmux, nothing to reload"
}

main() {
    run_pull_step
    run_apply_step
    run_claude_step
    print_banner "$DONE_STYLE" "Update done"
}

main
