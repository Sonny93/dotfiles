#!/usr/bin/env bash
# Read-only browser of the files of the current git repository: fzf with a bat preview, nothing can be edited from it.
# Usage: code-files.sh   (meant for a tmux popup, Alt+g then f, which keeps it readable on failure with -EE)
# Lists the tracked files and the new untracked ones, .gitignore respected. Tracked files deleted in the working tree stay listed, with a notice as preview and nothing on Enter. Enter shows the file full screen in bat's pager (q goes back to the list), Esc closes. When the repository has several worktrees (those of Claude agents, for instance), it first asks which one, the most recently edited first (pick-worktree.sh).
set -euo pipefail

SCRIPT_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
readonly PICK_WORKTREE_SCRIPT="$SCRIPT_DIRECTORY/pick-worktree.sh"

readonly PROMPT="fichier > "
readonly HEADER="Entrée : ouvrir en plein écran (q : revenir) · Échap : fermer"
readonly PREVIEW_LINE_COUNT=500
readonly DELETED_FILE_NOTICE="Fichier supprimé (pas encore commité)"
readonly PREVIEW_COMMAND="if [ -e {} ]; then bat --color=always --style=numbers --line-range=:$PREVIEW_LINE_COUNT -- {}; else echo '$DELETED_FILE_NOTICE'; fi"
readonly FULL_SCREEN_COMMAND="[ ! -e {} ] || bat --color=always --style=numbers --paging=always -- {}"

fail() {
    echo "$1" >&2
    exit 1
}

check_requirements() {
    command -v fzf >/dev/null || fail "fzf not found on PATH, run 'just mise'"
    command -v bat >/dev/null || fail "bat not found on PATH, run 'just mise'"
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Pas dans un dépôt git."
}

list_files() {
    git ls-files --cached --others --exclude-standard --deduplicate -z
}

pick_file() {
    list_files | fzf --read0 --prompt "$PROMPT" --reverse --header "$HEADER" \
        --preview "$PREVIEW_COMMAND" --bind "enter:execute($FULL_SCREEN_COMMAND)" || true
}

check_requirements
target_directory=$("$PICK_WORKTREE_SCRIPT") || exit 0
cd -- "$target_directory"
pick_file
