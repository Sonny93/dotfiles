#!/usr/bin/env bash
# Attaches to or creates a tmux session (the `t` command in zsh).
# Usage: session.sh [<path>|<name>|--complete]
#   no argument: attaches to the latest session, or opens the session picker when already inside tmux; with no session at all, runs the session picker in the terminal
#   <path> (contains `/`, or is `.` or `..`): opens the session of the git root of that directory, created with workspace.sh when missing
#   <name>: opens the session of that name, or creates the one of the project of that name when it has none;
#     with neither, creates the project ~/dev/<name> (see is_valid_project_name, no git init)
#   a session about to be created first asks for its layout (layouts.sh); Esc creates nothing
#   --complete: prints the open sessions and the known projects, one per line, for the shell completion
set -euo pipefail

SCRIPT_DIRECTORY="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIRECTORY
readonly WORKSPACE_SCRIPT="$SCRIPT_DIRECTORY/workspace.sh"
readonly PICKER_SCRIPT="$SCRIPT_DIRECTORY/session-picker.sh"
readonly POPUP_SIZE="60%"
readonly COMPLETE_FLAG="--complete"

# shellcheck source-path=SCRIPTDIR source=projects.sh
source "$SCRIPT_DIRECTORY/projects.sh"
# shellcheck source-path=SCRIPTDIR source=layouts.sh
source "$SCRIPT_DIRECTORY/layouts.sh"

fail() {
    echo "t: $1" >&2
    exit 1
}

is_path_argument() {
    [[ "$1" == */* || "$1" == "." || "$1" == ".." ]]
}

has_session() {
    tmux has-session -t "=$1" 2>/dev/null
}

list_session_names() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null || true
}

list_project_session_names() {
    local directory
    while IFS= read -r directory; do
        session_name_for "$directory"
    done < <(list_project_directories)
}

list_candidates() {
    { list_session_names; list_project_session_names; } | sort -u
}

enter_session() {
    local session_name="$1"
    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "=$session_name"
        return
    fi
    exec tmux attach-session -t "=$session_name"
}

create_session() {
    local layout="$1" directory="$2" session_name="$3"
    "$WORKSPACE_SCRIPT" "$layout" "$directory" "$session_name" >/dev/null
}

create_and_enter_session() {
    local directory="$1" session_name="$2" title="$3" layout
    layout=$(choose_layout "$title") || return 0
    create_session "$layout" "$directory" "$session_name"
    enter_session "$session_name"
}

open_without_argument() {
    if [[ -n "${TMUX:-}" ]]; then
        local current_session
        current_session=$(tmux display-message -p '#{session_name}')
        tmux display-popup -EE -w "$POPUP_SIZE" -h "$POPUP_SIZE" "$(printf '%q %q' "$PICKER_SCRIPT" "$current_session")"
        return
    fi
    if tmux has-session 2>/dev/null; then
        exec tmux attach-session
    fi
    exec "$PICKER_SCRIPT"
}

resolve_directory() {
    local argument="$1" directory git_root
    directory=$(cd -- "$argument" 2>/dev/null && pwd) || fail "not a directory: $argument"
    git_root=$(git -C "$directory" rev-parse --show-toplevel 2>/dev/null) || git_root="$directory"
    printf '%s\n' "$git_root"
}

open_path() {
    local directory session_name
    directory=$(resolve_directory "$1")
    session_name=$(session_name_for "$directory")
    if has_session "$session_name"; then
        enter_session "$session_name"
        return
    fi
    create_and_enter_session "$directory" "$session_name" "Nouvelle session $session_name"
}

create_project() {
    local name="$1" directory layout
    is_valid_project_name "$name" || fail "invalid project name: $name (letters, digits, _ . - ; no / and no leading . or -)"
    directory="$PROJECTS_ROOT/$name"
    layout=$(choose_layout "Nouveau projet ~/dev/$name") || return 0
    mkdir -- "$directory" || fail "cannot create $directory"
    create_session "$layout" "$directory" "$(session_name_for "$name")"
    enter_session "$(session_name_for "$name")"
}

open_name() {
    local session_name directory
    session_name=$(session_name_for "$1")
    if has_session "$session_name"; then
        enter_session "$session_name"
        return
    fi
    if directory=$(find_project_directory "$session_name"); then
        create_and_enter_session "$directory" "$session_name" "Nouvelle session $session_name"
        return
    fi
    create_project "$1"
}

main() {
    case "${1:-}" in
        "") open_without_argument ;;
        "$COMPLETE_FLAG") list_candidates ;;
        *) if is_path_argument "$1"; then open_path "$1"; else open_name "$1"; fi ;;
    esac
}

main "$@"
