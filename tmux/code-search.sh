#!/usr/bin/env bash
# Read-only search in the content of the files of the current git repository: ripgrep results live in fzf, with a bat preview on the matched line.
# Usage: code-search.sh   (meant for a tmux popup, Alt+g then r, which keeps it readable on failure with -EE)
# Nothing is searched until something is typed. The query is a regex, case-insensitive unless it holds a capital letter; an invalid regex just shows no result.
# .gitignore is respected, dotfiles are searched, .git is not. Enter shows the file full screen in bat's pager, on the matched line (q goes back to the results), Esc closes.
set -euo pipefail

readonly PROMPT="recherche > "
readonly HEADER="Entrée : ouvrir à la ligne (q : revenir) · Échap : fermer"
readonly RESULT_DELIMITER=":"
readonly FILE_FIELD="{1}"
readonly LINE_FIELD="{2}"
readonly SEARCH_COMMAND="[ -n {q} ] && rg --line-number --column --no-heading --color=always --smart-case --hidden --glob '!.git' -e {q} 2>/dev/null || true"
readonly BAT_OPTIONS="--color=always --style=numbers --highlight-line $LINE_FIELD"
readonly PREVIEW_COMMAND="[ -e $FILE_FIELD ] && bat $BAT_OPTIONS -- $FILE_FIELD"
readonly PREVIEW_WINDOW="right,60%,+$LINE_FIELD/2"
readonly FULL_SCREEN_COMMAND="[ ! -e $FILE_FIELD ] || bat $BAT_OPTIONS --paging=always --pager 'less -R +$LINE_FIELD' -- $FILE_FIELD"

fail() {
    echo "$1" >&2
    exit 1
}

check_requirements() {
    local tool
    for tool in fzf bat rg; do
        command -v "$tool" >/dev/null || fail "$tool not found on PATH, run 'just mise'"
    done
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Pas dans un dépôt git."
}

search() {
    fzf --disabled --ansi --prompt "$PROMPT" --reverse --header "$HEADER" \
        --delimiter "$RESULT_DELIMITER" --bind "change:reload:$SEARCH_COMMAND" \
        --preview "$PREVIEW_COMMAND" --preview-window "$PREVIEW_WINDOW" \
        --bind "enter:execute($FULL_SCREEN_COMMAND)" </dev/null || true
}

check_requirements
cd "$(git rev-parse --show-toplevel)"
search
