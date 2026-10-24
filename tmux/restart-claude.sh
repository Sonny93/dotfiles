#!/usr/bin/env bash
# Relaunches idle Claude Code instances running in tmux panes so they pick up the newest installed binary.
# Usage: restart-claude.sh
#   reads ~/.claude/sessions/<pid>.json, one file per running Claude Code process
#   an instance already on the installed version, or not idle, is left alone; the others resume their conversation
#   meant to run after `mise upgrade`, from a tmux pane (prefix + Ctrl+K, "Relancer les Claude Code inactifs")
set -euo pipefail

readonly SESSIONS_DIRECTORY="$HOME/.claude/sessions"
readonly INTERACTIVE_KIND="interactive"
readonly IDLE_STATUS="idle"
readonly NO_TMUX_LOCATION="none"
readonly SESSION_ID_PATTERN='^[0-9a-f-]+$'
readonly PANE_LABEL_FORMAT='#{session_name}:#{window_index}.#{pane_index}'

restarted_count=0
busy_count=0
up_to_date_count=0

require_prerequisites() {
    local command_name
    for command_name in jq claude tmux; do
        command -v "$command_name" >/dev/null || { echo "$command_name not found on PATH" >&2; exit 1; }
    done
    tmux list-sessions >/dev/null 2>&1 || { echo "cannot talk to a tmux server" >&2; exit 1; }
}

read_installed_version() {
    claude --version | cut -d ' ' -f 1
}

is_process_alive() {
    kill -0 "$1" 2>/dev/null
}

pane_id_of() {
    echo "${1##*.}"
}

is_pane_owned_by_process() {
    local pane_id="$1" process_id="$2" pane_process_id parent_process_id
    tmux display-message -p -t "$pane_id" '#{pane_id}' >/dev/null 2>&1 || return 1
    pane_process_id="$(tmux display-message -p -t "$pane_id" '#{pane_pid}')"
    parent_process_id="$(ps -o ppid= -p "$process_id" | tr -d ' ')"
    [[ "$pane_process_id" == "$parent_process_id" ]]
}

describe_pane() {
    tmux display-message -p -t "$1" "$PANE_LABEL_FORMAT"
}

respawn_with_resume() {
    local pane_id="$1" working_directory="$2" session_id="$3"
    if [[ ! "$session_id" =~ $SESSION_ID_PATTERN ]]; then
        echo "invalid session id '$session_id' for pane $pane_id, skipped" >&2
        return 1
    fi
    tmux respawn-pane -k -t "$pane_id" -c "$working_directory" "claude --resume $session_id; exec zsh"
}

process_session_file() {
    local session_file="$1"
    local process_id kind tmux_location working_directory session_id version status pane_id pane_label
    IFS=$'\t' read -r process_id kind tmux_location working_directory session_id version status < <(
        jq -r --arg none "$NO_TMUX_LOCATION" '[.pid, .kind, (.tmux // $none), .cwd, .sessionId, .version, .status] | @tsv' "$session_file"
    )
    is_process_alive "$process_id" || return 0
    [[ "$tmux_location" != "$NO_TMUX_LOCATION" && "$kind" == "$INTERACTIVE_KIND" ]] || return 0
    pane_id="$(pane_id_of "$tmux_location")"
    is_pane_owned_by_process "$pane_id" "$process_id" || return 0
    pane_label="$(describe_pane "$pane_id")"

    if [[ "$version" == "$installed_version" ]]; then
        echo "$pane_label already on $version"
        up_to_date_count=$((up_to_date_count + 1))
        return 0
    fi
    if [[ "$status" != "$IDLE_STATUS" ]]; then
        echo "$pane_label is $status, skipped"
        busy_count=$((busy_count + 1))
        return 0
    fi
    respawn_with_resume "$pane_id" "$working_directory" "$session_id" || return 0
    echo "restarted $pane_label ($version -> $installed_version)"
    restarted_count=$((restarted_count + 1))
}

main() {
    require_prerequisites
    installed_version="$(read_installed_version)"
    local session_file
    for session_file in "$SESSIONS_DIRECTORY"/*.json; do
        [[ -e "$session_file" ]] || break
        process_session_file "$session_file"
    done
    echo "$restarted_count restarted, $busy_count skipped busy, $up_to_date_count up to date"
}

main
