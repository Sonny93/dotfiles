#!/usr/bin/env bash
# Picks a project with fzf and switches the tmux client to its session, creating it with workspace.sh when missing.
# Usage: project-picker.sh
#   meant to run inside a tmux popup (prefix + g); Esc or an empty selection closes it without doing anything
# The session name rule (`.` and `:` become `_`) is the same as project_session_name in .zshrc, which stays in zsh.
set -euo pipefail

readonly PROJECTS_ROOT="$HOME/dev"
readonly EXTRA_PROJECT_DIRECTORIES=("$HOME/dotfiles")
readonly WORKSPACE_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/workspace.sh"
readonly FIELD_SEPARATOR=$'\t'
readonly PROMPT="projet > "

list_projects() {
    local directory
    for directory in "$PROJECTS_ROOT"/*/ "${EXTRA_PROJECT_DIRECTORIES[@]}"; do
        [[ -d "$directory" ]] || continue
        directory="${directory%/}"
        printf '%s%s%s\n' "${directory##*/}" "$FIELD_SEPARATOR" "$directory"
    done | sort
}

pick_project_directory() {
    local selection
    selection=$(list_projects | fzf --prompt "$PROMPT" --reverse --delimiter "$FIELD_SEPARATOR" --with-nth 1) || return 0
    printf '%s\n' "${selection#*"$FIELD_SEPARATOR"}"
}

session_name_for() {
    local name="${1##*/}"
    printf '%s\n' "${name//[.:]/_}"
}

command -v fzf >/dev/null || { echo "fzf not found on PATH" >&2; exit 1; }

directory=$(pick_project_directory)
[[ -n "$directory" ]] || exit 0

session_name=$(session_name_for "$directory")

if ! tmux has-session -t "=$session_name" 2>/dev/null; then
    "$WORKSPACE_SCRIPT" "$directory" "$session_name" >/dev/null
fi

tmux switch-client -t "=$session_name"
