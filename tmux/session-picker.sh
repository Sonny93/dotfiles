#!/usr/bin/env bash
# Picks a session or a project with fzf and switches the tmux client to it, creating the session with workspace.sh when missing.
# Usage: session-picker.sh <current-session>
#   meant to run inside a tmux popup (prefix + s); Esc or an empty selection closes it without doing anything
# Lists the open sessions first (the current one is marked), then the projects that have no session yet.
# The session name rule (`.` and `:` become `_`) is the same as project_session_name in .zshrc, which stays in zsh.
set -euo pipefail

readonly PROJECTS_ROOT="$HOME/dev"
readonly EXTRA_PROJECT_DIRECTORIES=("$HOME/dotfiles")
readonly WORKSPACE_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/workspace.sh"
readonly FIELD_SEPARATOR=$'\t'
readonly SESSION_KIND="session"
readonly PROJECT_KIND="project"
readonly CURRENT_SESSION_LABEL="(courante)"
readonly NEW_SESSION_LABEL="(nouvelle session)"
readonly PROMPT="session > "
readonly KIND_FIELD=1
readonly TARGET_FIELD=2
readonly LABEL_FIELD=3
readonly SESSION_PREVIEW_FORMAT=' #I  #{pane_title}'

list_sessions() {
    local current_session="$1" session_name label
    while IFS= read -r session_name; do
        label="$session_name"
        [[ "$session_name" == "$current_session" ]] && label="$session_name  $CURRENT_SESSION_LABEL"
        printf '%s\t%s\t%s\n' "$SESSION_KIND" "$session_name" "$label"
    done < <(tmux list-sessions -F '#{session_name}' | sort)
}

session_name_for() {
    local name="${1##*/}"
    printf '%s\n' "${name//[.:]/_}"
}

list_new_projects() {
    local directory session_name
    for directory in "$PROJECTS_ROOT"/*/ "${EXTRA_PROJECT_DIRECTORIES[@]}"; do
        [[ -d "$directory" ]] || continue
        directory="${directory%/}"
        session_name=$(session_name_for "$directory")
        tmux has-session -t "=$session_name" 2>/dev/null && continue
        printf '%s\t%s\t%s\n' "$PROJECT_KIND" "$directory" "${directory##*/}  $NEW_SESSION_LABEL"
    done | sort
}

list_entries() {
    list_sessions "$1"
    list_new_projects
}

preview_entry() {
    local kind="$1" target="$2"
    if [[ "$kind" == "$SESSION_KIND" ]]; then
        tmux list-windows -t "=$target" -F "$SESSION_PREVIEW_FORMAT"
        return
    fi
    printf '%s\n' "$target"
}

pick_entry() {
    list_entries "$1" | fzf --prompt "$PROMPT" --reverse --delimiter "$FIELD_SEPARATOR" --with-nth "$LABEL_FIELD" \
        --preview "$(printf '%q' "$0") --preview {$KIND_FIELD} {$TARGET_FIELD}" || return 0
}

switch_to_project() {
    local directory="$1" session_name
    session_name=$(session_name_for "$directory")
    "$WORKSPACE_SCRIPT" "$directory" "$session_name" >/dev/null
    tmux switch-client -t "=$session_name"
}

main() {
    if [[ "${1:-}" == "--preview" ]]; then
        preview_entry "$2" "$3"
        return
    fi

    command -v fzf >/dev/null || { echo "fzf not found on PATH" >&2; exit 1; }

    local selection kind target
    selection=$(pick_entry "${1:?usage: session-picker.sh <current-session>}")
    [[ -n "$selection" ]] || return 0
    kind="${selection%%"$FIELD_SEPARATOR"*}"
    target="${selection#*"$FIELD_SEPARATOR"}"
    target="${target%%"$FIELD_SEPARATOR"*}"

    if [[ "$kind" == "$SESSION_KIND" ]]; then
        tmux switch-client -t "=$target"
        return
    fi
    switch_to_project "$target"
}

main "$@"
