#!/usr/bin/env bash
# Quiet Arch system upgrade: rootless preview, Arch news, one prompt, then the pacman transaction as a transient systemd unit.
# Usage: arch-upgrade.sh
#   meant for the `system` recipe, only when update.sh set UPDATE_LOG (quiet mode)
#   the unit survives Ctrl+C, a closed terminal and a logout, and inhibits shutdown, sleep and the lid switch while it runs
#   the root-owned transaction log is /var/log/dotfiles/pacman-<timestamp>.log; its path is shown and reported on failure
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH
readonly SCRIPT_DIRECTORY="${SCRIPT_PATH%/*}"
readonly PACMAN_LOG_DIRECTORY="/var/log/dotfiles"
readonly PACMAN_LOCK_PATH="/var/lib/pacman/db.lck"
readonly EXIT_SENTINEL="DOTFILES_PACMAN_EXIT"
readonly NO_UPDATES_STATUS=2
readonly POLL_SECONDS=1
readonly INTERRUPTED_STATUS=130
readonly NO_TERMINAL_STATUS=2
readonly APPLY_PROMPT="Appliquer ? [O/n]"
readonly ORPHANS_PROMPT="Supprimer les orphelins ? [O/n]"
readonly CHECKUPDATES_DB="${TMPDIR:-/tmp}/checkup-db-${UID}/"
readonly UNIT_SCRIPT='systemd-inhibit --what=shutdown:sleep:handle-lid-switch --who=dotfiles --why="pacman upgrade" pacman -Syu --noconfirm
pacman_status=$?
printf "%s %s\n" "$1" "$pacman_status"
exit "$pacman_status"'
export CHECKUPDATES_DB

# shellcheck source=status.sh
# shellcheck source-path=SCRIPTDIR
source "$SCRIPT_DIRECTORY/status.sh"

confirm() {
    local prompt="$1" answer
    [ -t 0 ] || return "$NO_TERMINAL_STATUS"
    while true; do
        read -r -p "$prompt " answer || return "$NO_TERMINAL_STATUS"
        case "${answer,,}" in
            "" | o | oui | y | yes) return 0 ;;
            n | non | no) return 1 ;;
        esac
    done
}

has_pending_updates() {
    local checkupdates_status=0
    checkupdates >/dev/null 2>&1 || checkupdates_status=$?
    case "$checkupdates_status" in
        0) return 0 ;;
        "$NO_UPDATES_STATUS") return 1 ;;
    esac
    print_step_failed "pacman preview (checkupdates exit $checkupdates_status)"
    report_line ERROR "pacman preview failed (checkupdates exit $checkupdates_status)"
    return 3
}

read_transaction() {
    pacman -Sup --dbpath "$CHECKUPDATES_DB" --print-format '%n %v' 2>/dev/null | grep -E '^[^ ]+ [^ ]+$' || true
}

show_news() {
    command -v paru >/dev/null || return 0
    local news
    news="$(paru -Pw 2>/dev/null)" || return 0
    [ -z "$news" ] || printf 'Arch news:\n%s\n' "$news"
}

refuse_when_locked() {
    [ -e "$PACMAN_LOCK_PATH" ] || return 0
    print_step_failed "pacman upgrade: $PACMAN_LOCK_PATH exists (another pacman running, or a stale lock)"
    report_line ERROR "pacman upgrade refused: $PACMAN_LOCK_PATH exists"
    return 1
}

start_unit() {
    local unit="$1" pacman_log="$2"
    sudo install -d -m 755 -o root -g root "$PACMAN_LOG_DIRECTORY"
    sudo systemd-run --quiet --collect --unit="$unit" --setenv=LC_ALL=C \
        --property="StandardOutput=append:$pacman_log" \
        /bin/sh -c "$UNIT_SCRIPT" dotfiles-pacman "$EXIT_SENTINEL"
}

has_exit_status() {
    grep -q "^$EXIT_SENTINEL " "$1" 2>/dev/null
}

is_unit_alive() {
    case "$(systemctl is-active "$1" 2>/dev/null)" in
        active | activating | deactivating | reloading) return 0 ;;
    esac
    return 1
}

show_progress() {
    [ -t 1 ] || return 0
    local last_line columns
    columns="$(tput cols 2>/dev/null || echo 80)"
    last_line="$(tail -n 1 "$1" 2>/dev/null | cut -c "1-$((columns - 12))")"
    printf '\r\033[K  pacman: %s' "$last_line"
}

clear_progress() {
    [ -t 1 ] || return 0
    printf '\r\033[K'
}

leave_unit_running() {
    local unit="$1" pacman_log="$2"
    clear_progress
    echo "Interrupted: pacman keeps running in the background (unit $unit)."
    echo "Follow it with: tail -f $pacman_log"
    report_line WARN "pacman upgrade still running in the background, log: $pacman_log"
    exit "$INTERRUPTED_STATUS"
}

follow_unit() {
    local unit="$1" pacman_log="$2" alive
    trap 'leave_unit_running "$unit" "$pacman_log"' INT
    while true; do
        alive=0
        ! is_unit_alive "$unit" || alive=1
        has_exit_status "$pacman_log" && break
        [ "$alive" -eq 1 ] || break
        show_progress "$pacman_log"
        sleep "$POLL_SECONDS"
    done
    trap - INT
    clear_progress
}

read_exit_status() {
    sed -n "s/^$EXIT_SENTINEL //p" "$1" 2>/dev/null | tail -n 1
}

report_pacman_warnings() {
    local pacman_log="$1" warning_line
    while IFS= read -r warning_line; do
        warn "pacman: ${warning_line#warning: }"
    done < <(grep '^warning:' "$pacman_log" | sort -u || true)
}

report_reboot_need() {
    local pacman_log="$1"
    if grep -q 'Reboot is recommended' "$pacman_log" || [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
        info "reboot recommended"
        report_line REBOOT "reboot recommended after the pacman upgrade"
    fi
}

report_pacman_failure() {
    local pacman_log="$1" excerpt
    print_step_failed "pacman upgrade"
    excerpt="$(grep -iE "$FAILURE_PATTERN|could not|unresolvable|breaks dependency" "$pacman_log" | tail -n "$FAILURE_EXCERPT_LINES" || true)"
    [ -z "$excerpt" ] || sed 's/^/    /' <<<"$excerpt"
    echo "    log: $pacman_log"
    report_line ERROR "pacman upgrade failed, log: $pacman_log"
}

finish_transaction() {
    local pacman_log="$1" package_count="$2" exit_status
    exit_status="$(read_exit_status "$pacman_log")"
    if [ "$exit_status" != "0" ]; then
        report_pacman_failure "$pacman_log"
        return 1
    fi
    print_step_ok "pacman upgrade ($package_count packages)"
    report_pacman_warnings "$pacman_log"
    report_reboot_need "$pacman_log"
}

run_transaction() {
    local package_count="$1" timestamp unit pacman_log
    timestamp="$(date +%Y-%m-%dT%H-%M-%S)"
    unit="dotfiles-pacman-$timestamp"
    pacman_log="$PACMAN_LOG_DIRECTORY/pacman-$timestamp.log"
    refuse_when_locked || return 1
    append_log_header "pacman upgrade (root log: $pacman_log)"
    start_unit "$unit" "$pacman_log" || {
        print_step_failed "pacman upgrade (could not start $unit)"
        report_line ERROR "pacman upgrade could not start"
        return 1
    }
    follow_unit "$unit" "$pacman_log"
    finish_transaction "$pacman_log" "$package_count"
}

remove_orphans() {
    local orphans answer_status=0
    mapfile -t orphans < <(pacman -Qdtq 2>/dev/null || true)
    if [ "${#orphans[@]}" -eq 0 ]; then
        print_step_ok "no orphan packages"
        return 0
    fi
    echo "Orphans: ${orphans[*]}"
    confirm "$ORPHANS_PROMPT" || answer_status=$?
    if [ "$answer_status" -ne 0 ]; then
        warn "orphan packages kept, run 'just system' to remove them"
        return 0
    fi
    run_quiet_step "remove orphan packages" sudo pacman -Rns --noconfirm "${orphans[@]}"
}

preview_transaction() {
    local transaction="$1" installed_file
    installed_file="$(mktemp)"
    pacman -Q >"$installed_file"
    "$SCRIPT_DIRECTORY/format-upgrades.sh" "$installed_file" <<<"$transaction"
    rm -f "$installed_file"
}

main() {
    local pending_status=0 transaction answer_status=0
    if [ -z "${UPDATE_LOG:-}" ]; then
        echo "arch-upgrade.sh runs in quiet mode only (UPDATE_LOG unset)" >&2
        return 2
    fi
    has_pending_updates || pending_status=$?
    [ "$pending_status" -ne 3 ] || return 1
    if [ "$pending_status" -ne 0 ]; then
        print_step_ok "system up to date"
        return 0
    fi
    transaction="$(read_transaction)"
    if [ -z "$transaction" ]; then
        print_step_ok "system up to date"
        return 0
    fi
    preview_transaction "$transaction" | tee -a "$UPDATE_LOG"
    show_news
    confirm "$APPLY_PROMPT" || answer_status=$?
    if [ "$answer_status" -ne 0 ]; then
        warn "pacman upgrade skipped, run 'just system' to apply it"
        return 0
    fi
    run_transaction "$(grep -c . <<<"$transaction")" || return 1
    remove_orphans
}

main "$@"
