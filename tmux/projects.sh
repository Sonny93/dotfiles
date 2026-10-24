#!/usr/bin/env bash
# Known projects and the session name rule, shared by session-picker.sh and session.sh.
# Usage: source projects.sh
#   a project is a directory under PROJECTS_ROOT or one of EXTRA_PROJECT_DIRECTORIES; its session is named after the directory

readonly PROJECTS_ROOT="$HOME/dev"
readonly EXTRA_PROJECT_DIRECTORIES=("$HOME/dotfiles")

session_name_for() {
    local name="${1##*/}"
    printf '%s\n' "${name//[.:]/_}"
}

list_project_directories() {
    local directory
    for directory in "$PROJECTS_ROOT"/*/ "${EXTRA_PROJECT_DIRECTORIES[@]}"; do
        [[ -d "$directory" ]] || continue
        printf '%s\n' "${directory%/}"
    done
}

find_project_directory() {
    local session_name="$1" directory
    while IFS= read -r directory; do
        [[ "$(session_name_for "$directory")" == "$session_name" ]] || continue
        printf '%s\n' "$directory"
        return 0
    done < <(list_project_directories)
    return 1
}
