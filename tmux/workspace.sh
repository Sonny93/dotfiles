#!/usr/bin/env bash
# Opens the "Claude + shells" layout: Claude Code on the left, two shells stacked on the right.
# Usage: workspace.sh <directory> <session-name>
#   adds the layout as a window of the session, creating the session detached when it is missing
set -euo pipefail

readonly CLAUDE_COMMAND="claude; exec zsh"
readonly MAIN_LAYOUT="main-vertical"

readonly directory="${1:?usage: workspace.sh <directory> <session-name>}"
readonly session_name="${2:?usage: workspace.sh <directory> <session-name>}"

create_claude_window() {
    if tmux has-session -t "=$session_name" 2>/dev/null; then
        tmux new-window -t "=$session_name:" -c "$directory" -P -F '#{window_id}' "$CLAUDE_COMMAND"
        return
    fi
    tmux new-session -d -s "$session_name" -c "$directory" -P -F '#{window_id}' "$CLAUDE_COMMAND"
}

window_id=$(create_claude_window)
claude_pane_id=$(tmux display-message -p -t "$window_id" '#{pane_id}')

tmux split-window -h -t "$window_id" -c "$directory"
tmux split-window -v -t "$window_id" -c "$directory"
tmux select-layout -t "$window_id" "$MAIN_LAYOUT"
tmux select-pane -t "$claude_pane_id"
