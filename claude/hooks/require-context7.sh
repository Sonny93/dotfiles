#!/usr/bin/env bash
set -euo pipefail

readonly CONTEXT7_SERVER_NAME="plugin:context7:context7"
readonly STATUS_CHECK_TIMEOUT_SECONDS=10
readonly SAFE_SESSION_ID_PATTERN='^[A-Za-z0-9-]+$'
readonly BLOCK_REASON="Context7 n'est pas connecté. Lance /mcp pour t'authentifier, puis renvoie ton message. Pour continuer sans Context7, renvoie simplement ton message."

hook_input=$(cat)
hook_event_name=$(jq -r '.hook_event_name // empty' <<<"$hook_input")
session_id=$(jq -r '.session_id // empty' <<<"$hook_input")

if [[ ! "$session_id" =~ $SAFE_SESSION_ID_PATTERN ]]; then
    exit 0
fi

marker_directory="${XDG_RUNTIME_DIR:-/tmp}/claude-context7"
marker_path="$marker_directory/$session_id"

context7_status() {
    local status_output status_line
    status_output=$(timeout "$STATUS_CHECK_TIMEOUT_SECONDS" claude mcp get "$CONTEXT7_SERVER_NAME" 2>/dev/null) || {
        echo "unknown"
        return
    }
    status_line=$(grep -m1 '^[[:space:]]*Status:' <<<"$status_output" || true)
    if [ -z "$status_line" ]; then
        echo "unknown"
        return
    fi
    if [[ "$status_line" == *Connected* ]]; then
        echo "connected"
        return
    fi
    echo "disconnected"
}

create_marker() {
    mkdir -p "$marker_directory"
    : >"$marker_path"
}

remove_marker() {
    rm -f "$marker_path"
}

handle_session_start() {
    if [ "$(context7_status)" = "disconnected" ]; then
        create_marker
        return
    fi
    remove_marker
}

print_block_decision() {
    jq -n --arg reason "$BLOCK_REASON" '{decision: "block", reason: $reason}'
}

handle_user_prompt_submit() {
    [ -f "$marker_path" ] || return 0
    remove_marker
    if [ "$(context7_status)" = "disconnected" ]; then
        print_block_decision
    fi
}

case "$hook_event_name" in
SessionStart) handle_session_start ;;
UserPromptSubmit) handle_user_prompt_submit ;;
*) ;;
esac
