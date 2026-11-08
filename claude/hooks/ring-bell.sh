#!/usr/bin/env bash
# Rings the terminal bell (tmux turns the tab pink) when Claude really needs the user.
# It replaces preferredNotifChannel=terminal_bell: that bell is the idle_prompt notification, which fires about 60s
# after Claude finishes, only if the user has not typed since, and also while a background shell is still running.
# Hooks have no tty, so the BEL goes back through the hook JSON field terminalSequence, which Claude Code writes itself.
# Events: Stop (turn done), StopFailure (turn ended on an API error), Notification (permission, question).
set -euo pipefail

readonly IDLE_PROMPT_NOTIFICATION_TYPE="idle_prompt"

hook_input=$(cat)
hook_event_name=$(jq -r '.hook_event_name // empty' <<<"$hook_input")

ring_bell() {
    jq -nc --arg sequence $'\a' '{terminalSequence: $sequence}'
}

has_pending_work() {
    jq -e '((.background_tasks // []) | length > 0) or ((.session_crons // []) | length > 0)' <<<"$hook_input" >/dev/null
}

handle_stop() {
    has_pending_work && return 0
    ring_bell
}

handle_notification() {
    local notification_type
    notification_type=$(jq -r '.notification_type // empty' <<<"$hook_input")
    [[ "$notification_type" == "$IDLE_PROMPT_NOTIFICATION_TYPE" ]] && return 0
    ring_bell
}

case "$hook_event_name" in
Stop) handle_stop ;;
StopFailure) ring_bell ;;
Notification) handle_notification ;;
*) ;;
esac
