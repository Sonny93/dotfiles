#!/usr/bin/env bash
# Read-only view of the work in progress: diffnav (file tree + diff rendered by delta) on everything not committed yet, untracked files included.
# Usage: code-diff.sh [--print]
#   without argument: opens diffnav in watch mode, so the view follows the edits (meant for a tmux popup, Alt+g then d, which keeps it readable on failure with -EE); when the repository has several worktrees (those of Claude agents, for instance), it first asks which one, the most recently edited first (pick-worktree.sh)
#   --print: what diffnav runs on every refresh: working-tree-diff.sh, or a notice when there is nothing to show (diffnav shows an empty screen otherwise)
set -euo pipefail

SCRIPT_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
readonly PICK_WORKTREE_SCRIPT="$SCRIPT_DIRECTORY/pick-worktree.sh"
readonly WORKING_TREE_DIFF_SCRIPT="$SCRIPT_DIRECTORY/working-tree-diff.sh"
readonly REFRESH_INTERVAL="2s"
readonly NO_CHANGE_NOTICE="Aucun changement en cours"

print_diff_or_notice() {
    local diff
    diff=$("$WORKING_TREE_DIFF_SCRIPT")
    printf '%s\n' "${diff:-$NO_CHANGE_NOTICE}"
}

open_diffnav() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Pas dans un dépôt git." >&2; exit 1; }
    command -v diffnav >/dev/null || { echo "diffnav not found on PATH, run 'just mise'" >&2; exit 1; }
    local watch_command
    printf -v watch_command '%q --print' "$SCRIPT_DIRECTORY/code-diff.sh"
    # diffnav opens the selected file with $EDITOR on "o": less keeps that read-only
    EDITOR=less exec diffnav --watch --watch-cmd "$watch_command" --watch-interval "$REFRESH_INTERVAL"
}

if [[ "${1:-}" == "--print" ]]; then
    print_diff_or_notice
else
    target_directory=$("$PICK_WORKTREE_SCRIPT") || exit 0
    cd -- "$target_directory"
    open_diffnav
fi
