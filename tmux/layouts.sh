#!/usr/bin/env bash
# Layout chooser shared by session-picker.sh and session.sh, asked only when a session is about to be created.
# Usage: source layouts.sh; choose_layout <title>
#   shows the three layouts of the "Nouvel onglet" menu in fzf under <title>: Enter takes the highlighted one (Claude + shells first), w / c / s pick directly
#   prints the layout id for workspace.sh; Esc prints nothing and returns 1

readonly LAYOUT_FIELD_SEPARATOR=$'\t'
readonly LAYOUT_LABEL_FIELD=2
readonly LAYOUT_KEYS="w,c,s"
readonly LAYOUT_PICKER_HEIGHT="~10"

print_layout_entries() {
    printf '%s\t%s\n' "claude-shells" "Claude + shells  (w)"
    printf '%s\t%s\n' "claude" "Claude seul  (c)"
    printf '%s\t%s\n' "shell" "Shell seul  (s)"
}

layout_for_key() {
    case "$1" in
        w) printf '%s\n' "claude-shells" ;;
        c) printf '%s\n' "claude" ;;
        s) printf '%s\n' "shell" ;;
        *) return 1 ;;
    esac
}

choose_layout() {
    local title="$1" output
    local -a lines
    output=$(print_layout_entries | fzf --no-input --reverse --height "$LAYOUT_PICKER_HEIGHT" \
        --delimiter "$LAYOUT_FIELD_SEPARATOR" --with-nth "$LAYOUT_LABEL_FIELD" \
        --header "$title" --expect "$LAYOUT_KEYS") || return 1
    mapfile -t lines <<<"$output"
    if [[ -n "${lines[0]:-}" ]]; then
        layout_for_key "${lines[0]}"
        return
    fi
    [[ -n "${lines[1]:-}" ]] || return 1
    printf '%s\n' "${lines[1]%%"$LAYOUT_FIELD_SEPARATOR"*}"
}
