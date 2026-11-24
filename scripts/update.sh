#!/usr/bin/env bash
# Pulls the dotfiles repo (fast-forward only), re-applies the machine setup, then restarts idle Claude Code instances.
# Usage: update.sh [--verbose]
#   default is quiet: banners, one result line per step, the pulled commits and a final summary; everything else goes to UPDATE_LOG
#   --verbose prints the full output of every step instead (no UPDATE_LOG)
#   UPDATE_REPORT (one `WARN|ERROR|REBOOT <text>` line each) is always written; a preset value is used as is, so a caller can read it afterwards
#   UPDATE_SUDO_PAUSE_FILE (exported, unique per run): while that file exists the sudo keep-alive stops refreshing the ticket;
#   a caller creates it before running AUR builds and removes it after; update.sh removes it on exit
#   logs and reports live in ${XDG_STATE_HOME:-~/.local/state}/dotfiles/update, the 14 newest are kept
#   exits non-zero when a step failed or the report holds an ERROR
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
readonly FAILED_STYLE='\e[1;30;41m'
readonly STATE_DIRECTORY="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/update"
readonly KEPT_RUN_FILES=14
readonly SUDO_REFRESH_SECONDS="${UPDATE_SUDO_REFRESH_SECONDS:-60}"
readonly USAGE_STATUS=2
readonly FETCH_TIMEOUT_SECONDS=30
readonly FETCH_LOW_SPEED_LIMIT=1000
readonly FETCH_LOW_SPEED_SECONDS=20

IS_VERBOSE=0
KEEPALIVE_PID=""
readonly RESET_STYLE='\e[0m'

# shellcheck source=status.sh
# shellcheck source-path=SCRIPTDIR
source "$SCRIPT_DIRECTORY/status.sh"

print_banner() {
    local style="$1" text="$2"
    printf '\n%b %s %b\n\n' "$style" "$text" "$RESET_STYLE"
}

git_dotfiles() {
    GIT_TERMINAL_PROMPT=0 git -C "$DOTFILES_DIRECTORY" "$@"
}

git_fetch_dotfiles() {
    GIT_TERMINAL_PROMPT=0 timeout "$FETCH_TIMEOUT_SECONDS" git \
        -c "http.lowSpeedLimit=$FETCH_LOW_SPEED_LIMIT" -c "http.lowSpeedTime=$FETCH_LOW_SPEED_SECONDS" \
        -C "$DOTFILES_DIRECTORY" fetch --quiet
}

parse_arguments() {
    local argument
    for argument in "$@"; do
        case "$argument" in
            --verbose) IS_VERBOSE=1 ;;
            *)
                echo "Usage: update.sh [--verbose]" >&2
                exit "$USAGE_STATUS"
                ;;
        esac
    done
}

prune_run_files() {
    local extension
    for extension in log report; do
        find "$STATE_DIRECTORY" -maxdepth 1 -type f -name "*.$extension" | sort | head -n "-$KEPT_RUN_FILES" | xargs -r rm -f --
    done
}

prepare_run_files() {
    local timestamp
    if [ "${DOTFILES_UPDATE_PULLED:-}" = "1" ]; then
        return 0
    fi
    timestamp="$(date +%Y-%m-%dT%H-%M-%S)"
    mkdir -p "$STATE_DIRECTORY"
    chmod 700 "$STATE_DIRECTORY"
    unset UPDATE_LOG
    if [ "$IS_VERBOSE" -eq 0 ]; then
        export UPDATE_LOG="$STATE_DIRECTORY/$timestamp.log"
        : >"$UPDATE_LOG"
    fi
    export UPDATE_SUDO_PAUSE_FILE="${XDG_RUNTIME_DIR:-/tmp}/dotfiles-update-sudo-pause-$timestamp"
    export UPDATE_REPORT="${UPDATE_REPORT:-$STATE_DIRECTORY/$timestamp.report}"
    mkdir -p "$(dirname "$UPDATE_REPORT")"
    : >"$UPDATE_REPORT"
    prune_run_files
}

start_sudo_keepalive() {
    command -v sudo >/dev/null || return 0
    local parent_pid="$$"
    (
        while kill -0 "$parent_pid" 2>/dev/null; do
            [ -e "${UPDATE_SUDO_PAUSE_FILE:-}" ] || sudo -n -v 2>/dev/null || true
            sleep "$SUDO_REFRESH_SECONDS"
        done
    ) </dev/null >/dev/null 2>&1 &
    KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
    [ -z "$KEEPALIVE_PID" ] || kill "$KEEPALIVE_PID" 2>/dev/null || true
    KEEPALIVE_PID=""
}

end_sudo_session() {
    stop_sudo_keepalive
    [ -z "${UPDATE_SUDO_PAUSE_FILE:-}" ] || rm -f -- "$UPDATE_SUDO_PAUSE_FILE"
    command -v sudo >/dev/null || return 0
    sudo -k 2>/dev/null || true
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
    if ! git_fetch_dotfiles; then
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
        print_step_ok "Already up to date"
        return 1
    fi
    git_dotfiles log --oneline 'HEAD..@{u}'
    run_quiet_step "fast-forward merge" git -C "$DOTFILES_DIRECTORY" merge --ff-only '@{u}'
}

run_pull_step() {
    print_banner "$STEP_STYLE" "1/3 dotfiles (git pull)"
    if [ "${DOTFILES_UPDATE_PULLED:-}" = "1" ]; then
        echo "Pulled already, running the pulled version"
        return 0
    fi
    if pull_dotfiles; then
        stop_sudo_keepalive
        exec env DOTFILES_UPDATE_PULLED=1 "$SCRIPT_PATH"
    fi
}

run_role_steps() {
    local role="$1" steps_status=0 doctor_status=0
    env DOTFILES_DIRECTORY="$DOTFILES_DIRECTORY" "$SCRIPT_DIRECTORY/dev-update.sh" "$role" || steps_status=$?
    run_quiet_step "doctor-$role" just -f "$DOTFILES_DIRECTORY/Justfile" "doctor-$role" || doctor_status=$?
    [ "$steps_status" -eq 0 ] || return "$steps_status"
    return "$doctor_status"
}

run_setup_recipe() {
    local role
    role="$(cat "$ROLE_PATH" 2>/dev/null || true)"
    if [ "$role" != "dev" ] && [ "$role" != "server" ]; then
        echo "ERROR: no machine role recorded, run 'just dev' or 'just server' once." >&2
        report_line ERROR "no machine role recorded"
        return 1
    fi
    if [ -n "${UPDATE_LOG:-}" ]; then
        run_role_steps "$role"
        return
    fi
    run_quiet_step "just $role" just -f "$DOTFILES_DIRECTORY/Justfile" "$role"
}

run_apply_step() {
    print_banner "$STEP_STYLE" "2/3 Apply"
    if [ -x "$HOOK_PATH" ]; then
        run_visible_step "update hook" "$HOOK_PATH"
        return
    fi
    run_setup_recipe
}

run_claude_step() {
    print_banner "$STEP_STYLE" "3/3 Claude Code instances (tmux)"
    if command -v claude >/dev/null && tmux list-sessions >/dev/null 2>&1; then
        run_quiet_step "Claude Code restart" "$DOTFILES_DIRECTORY/tmux/restart-claude.sh"
        return
    fi
    print_step_ok "No Claude Code in tmux, nothing to reload"
}

run_steps() {
    run_pull_step && run_apply_step && run_claude_step
}

main() {
    local steps_status=0 summary_status=0
    parse_arguments "$@"
    prepare_run_files
    start_sudo_keepalive
    trap end_sudo_session EXIT
    run_steps || steps_status=$?
    print_report_summary || summary_status=$?
    if [ "$steps_status" -ne 0 ] || [ "$summary_status" -ne 0 ]; then
        print_banner "$FAILED_STYLE" "Update finished with errors"
        exit 1
    fi
    print_banner "$DONE_STYLE" "Update done"
}

main "$@"
