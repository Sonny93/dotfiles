#!/usr/bin/env bash
# Picks a session, one of its tabs or a project with fzf and switches the tmux client to it, creating the session with workspace.sh when missing.
# Usage: session-picker.sh [<current-session>]
#   <current-session> defaults to the session of the client tmux sees as current (display-popup does not expand formats)
#   meant to run inside a tmux popup (prefix + s); Esc or an empty selection closes it without doing anything
#   also runs directly in a terminal outside tmux (used by `t` when no session exists): it lists the projects only and attaches to the chosen session instead of switching to it
# Lists the open sessions as a tree (the current one is marked, each followed by its tabs labelled like the tab bar), then the projects that have no session yet.
# The cursor starts on the current tab; a tab row ends with its dimmed session name so filtering by session name finds it.
set -euo pipefail

SCRIPT_DIRECTORY="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIRECTORY
readonly WORKSPACE_SCRIPT="$SCRIPT_DIRECTORY/workspace.sh"
readonly FIELD_SEPARATOR=$'\t'
readonly SESSION_KIND="session"
readonly WINDOW_KIND="window"
readonly PROJECT_KIND="project"
readonly CURRENT_SESSION_LABEL="(courante)"
readonly NEW_SESSION_LABEL="(nouvelle session)"
readonly WINDOW_INDENT="   "
readonly DIM_START=$'\e[2m'
readonly DIM_END=$'\e[0m'
readonly PROMPT="session > "
readonly KIND_FIELD=1
readonly TARGET_FIELD=2
readonly WINDOW_INDEX_FIELD=3
readonly LABEL_FIELD=4
readonly SESSION_PREVIEW_FORMAT=' #I  #{pane_title}'
readonly WINDOW_LIST_FORMAT="#{window_index}${FIELD_SEPARATOR}#{E:window-status-format}"
readonly ACTIVE_WINDOW_FORMAT='#{window_index}'

# shellcheck source-path=SCRIPTDIR source=projects.sh
source "$SCRIPT_DIRECTORY/projects.sh"

print_entry() {
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
}

list_windows() {
    local session_name="$1" window_index label
    while IFS="$FIELD_SEPARATOR" read -r window_index label; do
        print_entry "$WINDOW_KIND" "$session_name" "$window_index" \
            "$WINDOW_INDENT$label  $DIM_START$session_name$DIM_END"
    done < <(tmux list-windows -t "=$session_name" -F "$WINDOW_LIST_FORMAT")
}

list_sessions() {
    local current_session="$1" session_name label
    while IFS= read -r session_name; do
        label="$session_name"
        [[ "$session_name" == "$current_session" ]] && label="$session_name  $CURRENT_SESSION_LABEL"
        print_entry "$SESSION_KIND" "$session_name" "" "$label"
        list_windows "$session_name"
    done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)
}

list_new_projects() {
    local directory session_name
    while IFS= read -r directory; do
        session_name=$(session_name_for "$directory")
        tmux has-session -t "=$session_name" 2>/dev/null && continue
        print_entry "$PROJECT_KIND" "$directory" "" "${directory##*/}  $NEW_SESSION_LABEL"
    done < <(list_project_directories) | sort
}

list_entries() {
    list_sessions "$1"
    list_new_projects
}

find_current_window_position() {
    local current_session="$1" current_window_index
    current_window_index=$(tmux display-message -p -t "=$current_session:" "$ACTIVE_WINDOW_FORMAT")
    awk -F "$FIELD_SEPARATOR" -v kind="$WINDOW_KIND" -v session_name="$current_session" -v window_index="$current_window_index" \
        '$1 == kind && $2 == session_name && $3 == window_index { print NR; exit }'
}

preview_entry() {
    local kind="$1" target="$2" window_index="$3"
    case "$kind" in
        "$SESSION_KIND") tmux list-windows -t "=$target" -F "$SESSION_PREVIEW_FORMAT" ;;
        "$WINDOW_KIND") tmux capture-pane -ep -t "=$target:$window_index" ;;
        *) printf '%s\n' "$target" ;;
    esac
}

pick_entry() {
    local current_session="$1" entries
    local -a position_options=()
    entries=$(list_entries "$current_session")
    if [[ -n "$current_session" ]]; then
        position_options=(--bind "load:pos($(find_current_window_position "$current_session" <<<"$entries"))")
    fi
    fzf --prompt "$PROMPT" --reverse --ansi --tiebreak=index --delimiter "$FIELD_SEPARATOR" --with-nth "$LABEL_FIELD" \
        "${position_options[@]}" \
        --preview "$(printf '%q' "$0") --preview {$KIND_FIELD} {$TARGET_FIELD} {$WINDOW_INDEX_FIELD}" <<<"$entries" || return 0
}

extract_field() {
    cut -d "$FIELD_SEPARATOR" -f "$2" <<<"$1"
}

enter_target() {
    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "$1"
        return
    fi
    exec tmux attach-session -t "$1"
}

open_project() {
    local directory="$1" session_name
    session_name=$(session_name_for "$directory")
    "$WORKSPACE_SCRIPT" "$directory" "$session_name" >/dev/null
    enter_target "=$session_name"
}

find_current_session() {
    [[ -n "${TMUX:-}" ]] || return 0
    tmux display-message -p '#{client_session}'
}

open_selection() {
    local selection="$1" kind target window_index
    kind=$(extract_field "$selection" "$KIND_FIELD")
    target=$(extract_field "$selection" "$TARGET_FIELD")
    window_index=$(extract_field "$selection" "$WINDOW_INDEX_FIELD")

    case "$kind" in
        "$SESSION_KIND") enter_target "=$target" ;;
        "$WINDOW_KIND") enter_target "=$target:$window_index" ;;
        *) open_project "$target" ;;
    esac
}

main() {
    if [[ "${1:-}" == "--preview" ]]; then
        preview_entry "$2" "$3" "$4"
        return
    fi

    command -v fzf >/dev/null || { echo "fzf not found on PATH" >&2; exit 1; }

    local selection
    selection=$(pick_entry "${1:-$(find_current_session)}")
    [[ -n "$selection" ]] || return 0
    open_selection "$selection"
}

main "$@"
