#!/usr/bin/env bash
# Picks an action from palette.tsv with fzf and hands its tmux command to the client that opened the popup.
# Usage: command-palette.sh
#   meant to run inside a tmux popup (prefix + Ctrl+K); Esc or an empty selection closes it without doing anything
# palette.tsv holds one action per line: label, key hint (may be empty), tmux command, separated by TABs.
# The popup cannot run the command itself: prompts, menus and popups need the client's screen, which the popup holds.
# So the command goes into the server option @palette_command, and the binding in tmux.conf runs it once the popup is closed.
set -euo pipefail

readonly ACTIONS_FILE="$(dirname "${BASH_SOURCE[0]}")/palette.tsv"
readonly FIELD_SEPARATOR=$'\t'
readonly COMMAND_FIELD=3
readonly PROMPT="action > "
readonly PENDING_COMMAND_OPTION="@palette_command"
readonly DIM=$'\033[2m'
readonly RESET=$'\033[0m'
readonly COLUMN_GAP=2

list_actions() {
    awk -F "$FIELD_SEPARATOR" -v OFS="$FIELD_SEPARATOR" -v dim="$DIM" -v reset="$RESET" -v file="$ACTIONS_FILE" '
        /^#/ || NF == 0 { next }
        NF != 3 { printf "%s line %d: expected label, key hint and command separated by TABs\n", file, NR > "/dev/stderr"; exit 1 }
        { print $1, dim $2 reset, $3 }
    ' "$ACTIONS_FILE"
}

label_column_width() {
    awk -F "$FIELD_SEPARATOR" -v gap="$COLUMN_GAP" '
        length($1) > width { width = length($1) }
        END { print width + gap }
    '
}

pick_command() {
    local actions="$1"
    local selection
    selection=$(fzf --ansi --prompt "$PROMPT" --reverse --delimiter "$FIELD_SEPARATOR" --with-nth 1,2 \
        --tabstop "$(label_column_width <<<"$actions")" <<<"$actions") || return 0
    cut -f "$COMMAND_FIELD" <<<"$selection"
}

tmux set-option -s -u "$PENDING_COMMAND_OPTION"

command -v fzf >/dev/null || { echo "fzf not found on PATH" >&2; exit 1; }

actions=$(list_actions)
command=$(pick_command "$actions")
[[ -n "$command" ]] || exit 0

tmux set-option -s "$PENDING_COMMAND_OPTION" "$command"
