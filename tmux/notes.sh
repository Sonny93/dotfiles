#!/usr/bin/env bash
# Opens the notes file of the current project in micro, creating it when missing, and keeps ~/notes versioned and synced.
# Usage: notes.sh
#   meant to run inside a tmux popup (prefix + n) started in the pane's current path
# The project is the git root directory of $PWD (or $PWD itself outside a repo), named like its session.
# Notes live in ~/notes/<project>.md, outside every repo; Ctrl+S saves, Ctrl+Q closes (autosave keeps the text anyway), Ctrl+C copies to the client clipboard (OSC 52).
# ~/notes is a git repo set up by `just notes`: pulled before micro opens, committed when it closes, pushed in the background.
# Problems are reported with tmux display-message (they outlive the popup) and never prevent the notes from opening.
set -euo pipefail

SCRIPT_DIRECTORY="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIRECTORY
readonly NOTES_DIRECTORY="$HOME/notes"
readonly AUTOSAVE_INTERVAL_SECONDS=1
readonly COLORSCHEME="cobalt2"
readonly PULL_TIMEOUT_SECONDS=5
readonly REMOTE_NAME="origin"
readonly NOT_VERSIONED_MESSAGE="notes: not versioned, run 'just notes'"
readonly PULL_FAILED_MESSAGE="notes: pull failed, ask Claude to sync ~/notes"
readonly PUSH_FAILED_MESSAGE="notes: push failed, ask Claude to sync ~/notes"

# shellcheck source-path=SCRIPTDIR source=projects.sh
source "$SCRIPT_DIRECTORY/projects.sh"

find_project_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

ensure_notes_file() {
    local notes_file="$1" project="$2"
    mkdir -p "$NOTES_DIRECTORY"
    [[ -f "$notes_file" ]] || printf '# %s\n\n' "$project" > "$notes_file"
}

notes_git() {
    git -C "$NOTES_DIRECTORY" "$@"
}

is_notes_versioned() {
    [[ -d "$NOTES_DIRECTORY/.git" ]]
}

has_remote() {
    notes_git remote get-url "$REMOTE_NAME" >/dev/null 2>&1
}

abort_rebase_if_running() {
    [[ -d "$NOTES_DIRECTORY/.git/rebase-merge" || -d "$NOTES_DIRECTORY/.git/rebase-apply" ]] || return 0
    notes_git rebase --abort
}

pull_notes() {
    has_remote || return 0
    GIT_TERMINAL_PROMPT=0 timeout "$PULL_TIMEOUT_SECONDS" git -C "$NOTES_DIRECTORY" pull --rebase --autostash --quiet >/dev/null 2>&1 && return 0
    abort_rebase_if_running
    tmux display-message "$PULL_FAILED_MESSAGE"
}

commit_notes() {
    local project="$1"
    [[ -n "$(notes_git status --porcelain)" ]] || return 0
    notes_git add -A
    notes_git commit -q -m "Update $project notes"
}

push_notes_in_background() {
    has_remote || return 0
    tmux run-shell -b "git -C '$NOTES_DIRECTORY' push -q || tmux display-message \"$PUSH_FAILED_MESSAGE\""
}

sync_before_editing() {
    if ! is_notes_versioned; then
        tmux display-message "$NOT_VERSIONED_MESSAGE"
        return 0
    fi
    pull_notes
}

sync_after_editing() {
    local project="$1"
    is_notes_versioned || return 0
    commit_notes "$project"
    push_notes_in_background
}

edit_notes() {
    micro -autosave "$AUTOSAVE_INTERVAL_SECONDS" -clipboard terminal -softwrap true -saveundo true -colorscheme "$COLORSCHEME" -truecolor on "$1"
}

main() {
    command -v micro >/dev/null || { echo "micro not found on PATH" >&2; exit 1; }

    local project notes_file
    project=$(session_name_for "$(find_project_root)")
    notes_file="$NOTES_DIRECTORY/$project.md"
    sync_before_editing
    ensure_notes_file "$notes_file" "$project"
    edit_notes "$notes_file" || true
    sync_after_editing "$project"
}

main "$@"
