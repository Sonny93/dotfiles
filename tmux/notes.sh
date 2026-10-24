#!/usr/bin/env bash
# Opens the notes file of the current project in micro, creating it when missing.
# Usage: notes.sh
#   meant to run inside a tmux popup (prefix + n) started in the pane's current path
# The project is the git root directory of $PWD (or $PWD itself outside a repo), named like its session.
# Notes live in ~/notes/<project>.md, outside every repo; Ctrl+S saves, Ctrl+Q closes (autosave keeps the text anyway).
set -euo pipefail

SCRIPT_DIRECTORY="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIRECTORY
readonly NOTES_DIRECTORY="$HOME/notes"
readonly AUTOSAVE_INTERVAL_SECONDS=1

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

main() {
    command -v micro >/dev/null || { echo "micro not found on PATH" >&2; exit 1; }

    local project notes_file
    project=$(session_name_for "$(find_project_root)")
    notes_file="$NOTES_DIRECTORY/$project.md"
    ensure_notes_file "$notes_file" "$project"
    exec micro -autosave "$AUTOSAVE_INTERVAL_SECONDS" -softwrap true "$notes_file"
}

main "$@"
