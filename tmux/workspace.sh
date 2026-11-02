#!/usr/bin/env bash
# Opens a layout as a window of a session, creating the session detached when it is missing.
# Usage: workspace.sh <layout> <directory> <session-name>
#   <layout>: claude-shells (Claude Code on the left, two shells stacked on the right), claude (Claude Code alone) or shell (a plain shell)
# A new session resumes the latest Claude conversation of the directory (after a tmux restart, for instance) when it has one;
# a window added to an existing session starts a fresh one, so two tabs never share a conversation.
# `claude --continue` fails on a directory without conversation, hence the check of ~/.claude/projects

set -euo pipefail

readonly CLAUDE_COMMAND="claude; exec zsh"
readonly RESUMED_CLAUDE_COMMAND="claude --continue; exec zsh"
readonly MAIN_LAYOUT="main-vertical"
readonly CLAUDE_PROJECTS_DIRECTORY="$HOME/.claude/projects"
readonly USAGE="usage: workspace.sh <claude-shells|claude|shell> <directory> <session-name>"

has_claude_history() {
    local encoded_name="${1//[^A-Za-z0-9]/-}"
    compgen -G "$CLAUDE_PROJECTS_DIRECTORY/$encoded_name/*.jsonl" >/dev/null
}

has_session() {
    tmux has-session -t "=$1" 2>/dev/null
}

print_claude_command() {
    local directory="$1" session_name="$2"
    if has_session "$session_name" || ! has_claude_history "$directory"; then
        printf '%s\n' "$CLAUDE_COMMAND"
        return
    fi
    printf '%s\n' "$RESUMED_CLAUDE_COMMAND"
}

create_window() {
    local layout="$1" directory="$2" session_name="$3"
    local -a command=()
    [[ "$layout" == "shell" ]] || command=("$(print_claude_command "$directory" "$session_name")")
    if has_session "$session_name"; then
        tmux new-window -t "=$session_name:" -c "$directory" -P -F '#{window_id}' "${command[@]}"
        return
    fi
    tmux new-session -d -s "$session_name" -c "$directory" -P -F '#{window_id}' "${command[@]}"
}

add_shell_panes() {
    local window_id="$1" directory="$2" claude_pane_id
    claude_pane_id=$(tmux display-message -p -t "$window_id" '#{pane_id}')
    tmux split-window -h -t "$window_id" -c "$directory"
    tmux split-window -v -t "$window_id" -c "$directory"
    tmux select-layout -t "$window_id" "$MAIN_LAYOUT"
    tmux select-pane -t "$claude_pane_id"
}

main() {
    local layout="${1:?$USAGE}" directory="${2:?$USAGE}" session_name="${3:?$USAGE}" window_id
    case "$layout" in
        claude-shells | claude | shell) ;;
        *) echo "workspace.sh: unknown layout: $layout ($USAGE)" >&2; exit 1 ;;
    esac
    window_id=$(create_window "$layout" "$directory" "$session_name")
    [[ "$layout" == "claude-shells" ]] || return 0
    add_shell_panes "$window_id" "$directory"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
