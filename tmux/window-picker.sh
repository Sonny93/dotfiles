#!/usr/bin/env bash
# Picks a window (onglet) of a session with fzf and switches the tmux client to it.
# Usage: window-picker.sh [<session>]
#   <session> defaults to the session of the client tmux sees as current (display-popup does not expand formats)
#   meant to run inside a tmux popup (prefix + w); Esc or an empty selection closes it without doing anything
# Lists the windows with the same label as the tab bar, the cursor starts on the current window and the preview shows its active pane.
set -euo pipefail

readonly FIELD_SEPARATOR=$'\t'
readonly PROMPT="onglet > "
readonly INDEX_FIELD=1
readonly LABEL_FIELD=2
readonly WINDOW_LIST_FORMAT="#{window_index}${FIELD_SEPARATOR}#{E:window-status-format}"
readonly ACTIVE_WINDOW_FORMAT='#{window_active}'
readonly ACTIVE_WINDOW_FLAG="1"

list_entries() {
    tmux list-windows -t "=$1" -F "$WINDOW_LIST_FORMAT"
}

find_active_position() {
    local position=0 is_active
    while IFS= read -r is_active; do
        position=$((position + 1))
        [[ "$is_active" == "$ACTIVE_WINDOW_FLAG" ]] && break
    done < <(tmux list-windows -t "=$1" -F "$ACTIVE_WINDOW_FORMAT")
    printf '%s\n' "$position"
}

preview_window() {
    tmux capture-pane -ep -t "=$1:$2"
}

pick_window() {
    local session="$1"
    list_entries "$session" | fzf --prompt "$PROMPT" --reverse --delimiter "$FIELD_SEPARATOR" --with-nth "$LABEL_FIELD" \
        --bind "load:pos($(find_active_position "$session"))" \
        --preview "$(printf '%q' "$0") --preview $(printf '%q' "$session") {$INDEX_FIELD}" || return 0
}

main() {
    if [[ "${1:-}" == "--preview" ]]; then
        preview_window "$2" "$3"
        return
    fi

    command -v fzf >/dev/null || { echo "fzf not found on PATH" >&2; exit 1; }

    local session selection index
    session="${1:-$(tmux display-message -p '#{client_session}')}"
    selection=$(pick_window "$session")
    [[ -n "$selection" ]] || return 0
    index="${selection%%"$FIELD_SEPARATOR"*}"

    tmux select-window -t "=$session:$index"
}

main "$@"
