#!/usr/bin/env bash
# Picks a session, one of its tabs or a project with fzf and switches the tmux client to it, creating the session with workspace.sh when missing (the layout is asked first).
# Usage: session-picker.sh [<current-session>]
#   <current-session> defaults to the session of the client tmux sees as current (display-popup does not expand formats)
#   meant to run inside a tmux popup (prefix + s); Esc or an empty selection closes it without doing anything
#   also runs directly in a terminal outside tmux (used by `t` when no session exists): it lists the projects only and attaches to the chosen session instead of switching to it
# Enter with a query that matches nothing, or Alt+Enter whatever the matches, creates the project ~/dev/<query> (see is_valid_project_name): the layout is asked first, Esc there creates nothing, no git init;
#   when the query is the name of a cached GitHub repository, it is cloned instead.
# The header shows the typed text in the Alt+Enter hint as the query changes.
# Lists the open sessions as a tree (the current one is marked, each followed by its tabs labelled like the tab bar), then the projects that have no session yet,
#   then the GitHub repositories not cloned yet (only with `gh`, from the cache of projects.sh, renewed in the background at start, with a one-line notice on stderr when the very first fetch has to wait): choosing one asks the layout first, then clones it into ~/dev/<name>, then opens its session.
#   Repositories that already have a session or a folder (~/dev, ~/dotfiles, ~/notes) are not listed; a failed clone prints an error and creates no session.
# The cursor starts on the current tab; a tab row ends with its dimmed session name so filtering by session name finds it.
set -euo pipefail

SCRIPT_DIRECTORY="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIRECTORY
readonly WORKSPACE_SCRIPT="$SCRIPT_DIRECTORY/workspace.sh"
readonly FIELD_SEPARATOR=$'\t'
readonly SESSION_KIND="session"
readonly WINDOW_KIND="window"
readonly PROJECT_KIND="project"
readonly GITHUB_KIND="github"
readonly FIRST_REFRESH_NOTICE="Récupération de la liste des dépôts GitHub..."
readonly GITHUB_LABEL="(GitHub, à cloner)"
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
readonly CREATE_KEY="alt-enter"
readonly HEADER_FORMAT='Entrée : ouvrir · Alt+Entrée : créer ~/dev/%s · Échap : fermer'
readonly FZF_NO_MATCH_STATUS=1

# shellcheck source-path=SCRIPTDIR source=projects.sh
source "$SCRIPT_DIRECTORY/projects.sh"
# shellcheck source-path=SCRIPTDIR source=layouts.sh
source "$SCRIPT_DIRECTORY/layouts.sh"

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

list_github_repositories() {
    local full_name
    while IFS= read -r full_name; do
        print_entry "$GITHUB_KIND" "$full_name" "" "$full_name  $GITHUB_LABEL"
    done < <(list_uncloned_github_repositories | sort -f)
}

list_entries() {
    list_sessions "$1"
    list_new_projects
    list_github_repositories
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
        --print-query --expect "$CREATE_KEY" \
        --header "${HEADER_FORMAT/\%s/}" \
        --bind "change:transform-header(printf '$HEADER_FORMAT' {q})" \
        "${position_options[@]}" \
        --preview "$(printf '%q' "$0") --preview {$KIND_FIELD} {$TARGET_FIELD} {$WINDOW_INDEX_FIELD}" <<<"$entries"
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

launch_session() {
    local layout="$1" directory="$2" session_name="$3"
    "$WORKSPACE_SCRIPT" "$layout" "$directory" "$session_name" >/dev/null
    enter_target "=$session_name"
}

open_project() {
    local directory="$1" session_name layout
    session_name=$(session_name_for "$directory")
    if tmux has-session -t "=$session_name" 2>/dev/null; then
        enter_target "=$session_name"
        return
    fi
    layout=$(choose_layout "Nouvelle session $session_name") || return 0
    launch_session "$layout" "$directory" "$session_name"
}

open_github_repository() {
    local full_name="$1" name="${1#*/}" layout
    layout=$(choose_layout "Cloner $full_name dans ~/dev/$name") || return 0
    clone_github_repository "$full_name" || return 1
    launch_session "$layout" "$PROJECTS_ROOT/$name" "$(session_name_for "$name")"
}

create_project() {
    local name="$1" directory layout full_name
    is_valid_project_name "$name" || {
        echo "Nom de projet invalide : « $name » (lettres, chiffres, _ . - ; sans / ni . ou - au début)" >&2
        return 1
    }
    directory="$PROJECTS_ROOT/$name"
    if [[ -d "$directory" ]]; then
        open_project "$directory"
        return
    fi
    if full_name=$(find_github_repository "$name"); then
        open_github_repository "$full_name"
        return
    fi
    layout=$(choose_layout "Nouveau projet ~/dev/$name") || return 0
    mkdir -- "$directory"
    launch_session "$layout" "$directory" "$(session_name_for "$directory")"
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
        "$GITHUB_KIND") open_github_repository "$target" ;;
        *) open_project "$target" ;;
    esac
}

handle_pick() {
    local -a lines
    mapfile -t lines <<<"$1"
    local query="${lines[0]:-}" key="${lines[1]:-}" selection="${lines[2]:-}"
    if [[ -n "$selection" && "$key" != "$CREATE_KEY" ]]; then
        open_selection "$selection"
        return
    fi
    [[ -n "$query" || "$key" == "$CREATE_KEY" ]] || return 0
    create_project "$query"
}

main() {
    if [[ "${1:-}" == "--preview" ]]; then
        preview_entry "$2" "$3" "$4"
        return
    fi

    command -v fzf >/dev/null || { echo "fzf not found on PATH" >&2; exit 1; }
    if is_github_cache_missing; then
        echo "$FIRST_REFRESH_NOTICE" >&2
    fi
    refresh_github_cache_in_background

    local output status=0
    output=$(pick_entry "${1:-$(find_current_session)}") || status=$?
    [[ "$status" -eq 0 || "$status" -eq "$FZF_NO_MATCH_STATUS" ]] || return 0
    handle_pick "$output"
}

main "$@"
