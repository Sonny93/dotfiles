#!/usr/bin/env bash
# Read-only browser of the commits of the current branch: fzf over `git log`, with a delta-rendered preview of the selected commit.
# Usage: code-log.sh   (meant for a tmux popup, Alt+g then c, which keeps it readable on failure with -EE)
# Newest first, one line per commit (hash, date, subject, author); typing filters. A merge commit is shown against its first parent, so its diff is never empty. When the repository has several worktrees (those of Claude agents, for instance), it first asks which one, the most recently edited first (pick-worktree.sh).
# Enter shows the commit in diffnav, full screen (q goes back to the list; "o" there opens less, never an editor), Esc closes.
set -euo pipefail

SCRIPT_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
readonly PICK_WORKTREE_SCRIPT="$SCRIPT_DIRECTORY/pick-worktree.sh"

readonly PROMPT="commit > "
readonly HEADER="Entrée : ouvrir dans diffnav (q : revenir) · Échap : fermer"
readonly LOG_FORMAT='%C(yellow)%h%C(reset) %C(green)%ad%C(reset) %s %C(blue)%an%C(reset)'
readonly HASH_FIELD="{1}"
readonly SHOW_COMMAND="git show --diff-merges=first-parent --no-color"
readonly PREVIEW_COMMAND="$SHOW_COMMAND --stat --patch $HASH_FIELD | delta --paging=never --width=\$FZF_PREVIEW_COLUMNS"
readonly OPEN_COMMAND="$SHOW_COMMAND $HASH_FIELD | EDITOR=less diffnav"

fail() {
    echo "$1" >&2
    exit 1
}

check_requirements() {
    local tool
    for tool in fzf delta diffnav; do
        command -v "$tool" >/dev/null || fail "$tool not found on PATH, run 'just mise'"
    done
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Pas dans un dépôt git."
    git rev-parse --verify --quiet HEAD >/dev/null || fail "Aucun commit."
}

browse_commits() {
    git log --color=always --date=short --format="$LOG_FORMAT" | fzf --ansi --prompt "$PROMPT" --reverse --header "$HEADER" \
        --preview "$PREVIEW_COMMAND" --preview-window "right,60%" \
        --bind "enter:execute($OPEN_COMMAND)" || true
}

check_requirements
target_directory=$("$PICK_WORKTREE_SCRIPT") || exit 0
cd -- "$target_directory"
browse_commits
