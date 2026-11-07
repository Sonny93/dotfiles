#!/usr/bin/env bash
# Known projects, the session name rule and the new project name rule, shared by session-picker.sh and session.sh.
# Usage: source projects.sh
#   a project is a directory under PROJECTS_ROOT or one of EXTRA_PROJECT_DIRECTORIES; its session is named after the directory
#   a new project name is a single folder name: letters, digits, `_`, `.` and `-`, not starting with `.` or `-`
# GitHub repositories not cloned yet (only with `gh` on PATH, decisions come from the cache alone, never from the network):
#   the cache lists the `owner/name` of the user's own and organization repositories, without archives and forks, one per line;
#   refresh_github_cache_in_background renews it when older than GITHUB_CACHE_MAX_AGE_MINUTES (stale while revalidate, synchronous when the cache does not exist yet)
#   list_uncloned_github_repositories hides the repositories that already have a session or a folder (~/dev, EXTRA_PROJECT_DIRECTORIES, EXCLUDED_PROJECT_DIRECTORIES)
#   clone_github_repository clones into ~/dev/<name> through a staging folder, so a failed clone leaves no project folder

readonly PROJECTS_ROOT="$HOME/dev"
readonly EXTRA_PROJECT_DIRECTORIES=("$HOME/dotfiles")
readonly EXCLUDED_PROJECT_DIRECTORIES=("$HOME/notes")
readonly GITHUB_CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/github-repositories"
readonly GITHUB_CACHE_MAX_AGE_MINUTES=10
readonly GITHUB_AFFILIATIONS=("owner" "organization_member")
readonly GITHUB_REPOSITORY_FILTER='.[] | select(.archived or .fork | not) | .full_name'
readonly GITHUB_OWNER_PATTERN='^[A-Za-z0-9_.-]+$'
readonly GITHUB_REFRESH_FLAG="--refresh-github-cache"
GITHUB_REFRESH_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/session.sh"
readonly GITHUB_REFRESH_SCRIPT

session_name_for() {
    local name="${1##*/}"
    printf '%s\n' "${name//[.:]/_}"
}

list_project_directories() {
    local directory
    for directory in "$PROJECTS_ROOT"/*/ "${EXTRA_PROJECT_DIRECTORIES[@]}"; do
        [[ -d "$directory" ]] || continue
        printf '%s\n' "${directory%/}"
    done
}

find_project_directory() {
    local session_name="$1" directory
    while IFS= read -r directory; do
        [[ "$(session_name_for "$directory")" == "$session_name" ]] || continue
        printf '%s\n' "$directory"
        return 0
    done < <(list_project_directories)
    return 1
}

is_valid_project_name() {
    [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]
}

fetch_github_repositories() {
    local affiliation
    for affiliation in "${GITHUB_AFFILIATIONS[@]}"; do
        gh api --paginate "user/repos?affiliation=$affiliation&per_page=100" --jq "$GITHUB_REPOSITORY_FILTER" 2>/dev/null || return 1
    done
}

keep_first_repository_per_name() {
    awk '{ name = $0; sub(/^[^\/]*\//, "", name); name = tolower(name); if (!(name in seen)) { seen[name] = 1; print } }'
}

refresh_github_cache() {
    local cache_directory staging_file repositories
    cache_directory=$(dirname "$GITHUB_CACHE_FILE")
    mkdir -p "$cache_directory" || return 1
    staging_file=$(mktemp "$cache_directory/.github-repositories.XXXXXX") || return 1
    if ! repositories=$(fetch_github_repositories); then
        rm -f "$staging_file"
        return 1
    fi
    keep_first_repository_per_name <<<"$repositories" >"$staging_file"
    mv -f "$staging_file" "$GITHUB_CACHE_FILE"
}

is_github_cache_missing() {
    command -v gh >/dev/null && [[ ! -f "$GITHUB_CACHE_FILE" ]]
}

is_github_cache_fresh() {
    [[ -n "$(find "$GITHUB_CACHE_FILE" -mmin "-$GITHUB_CACHE_MAX_AGE_MINUTES" 2>/dev/null)" ]]
}

refresh_github_cache_in_background() {
    command -v gh >/dev/null || return 0
    if [[ ! -f "$GITHUB_CACHE_FILE" ]]; then
        refresh_github_cache || true
        return 0
    fi
    is_github_cache_fresh && return 0
    setsid -f "$GITHUB_REFRESH_SCRIPT" "$GITHUB_REFRESH_FLAG" </dev/null >/dev/null 2>&1
}

is_valid_github_repository() {
    local owner="${1%%/*}" name="${1#*/}"
    [[ "$1" == */* && "$owner" =~ $GITHUB_OWNER_PATTERN ]] && is_valid_project_name "$name"
}

list_cached_github_repositories() {
    local full_name
    command -v gh >/dev/null || return 0
    [[ -f "$GITHUB_CACHE_FILE" ]] || return 0
    while IFS= read -r full_name; do
        is_valid_github_repository "$full_name" || continue
        printf '%s\n' "$full_name"
    done <"$GITHUB_CACHE_FILE"
}

list_known_session_names() {
    local directory
    {
        tmux list-sessions -F '#{session_name}' 2>/dev/null || true
        while IFS= read -r directory; do
            session_name_for "$directory"
        done < <(list_project_directories)
        for directory in "${EXCLUDED_PROJECT_DIRECTORIES[@]}"; do
            session_name_for "$directory"
        done
    } | tr '[:upper:]' '[:lower:]'
}

list_uncloned_github_repositories() {
    list_cached_github_repositories | awk '
        FNR == NR { known[$0] = 1; next }
        { name = $0; sub(/^[^\/]*\//, "", name); gsub(/[.:]/, "_", name); if (!(tolower(name) in known)) print }
    ' <(list_known_session_names) -
}

find_github_repository() {
    local wanted_name="${1,,}" full_name name
    while IFS= read -r full_name; do
        name="${full_name#*/}"
        [[ "${name,,}" == "$wanted_name" ]] || continue
        printf '%s\n' "$full_name"
        return 0
    done < <(list_uncloned_github_repositories)
    return 1
}

clone_github_repository() {
    local full_name="$1" name="${1#*/}" staging_directory target_directory
    command -v gh >/dev/null || { echo "gh est introuvable : impossible de cloner $full_name" >&2; return 1; }
    is_valid_github_repository "$full_name" || { echo "Dépôt invalide : « $full_name »" >&2; return 1; }
    staging_directory="$PROJECTS_ROOT/.$name.clone"
    target_directory="$PROJECTS_ROOT/$name"
    [[ ! -e "$staging_directory" ]] || { echo "Dossier de clonage déjà présent : supprimez $staging_directory puis réessayez" >&2; return 1; }
    [[ ! -e "$target_directory" ]] || { echo "Le dossier $target_directory existe déjà" >&2; return 1; }
    gh repo clone "$full_name" "$staging_directory" || { echo "Échec du clone de $full_name" >&2; return 1; }
    mv -- "$staging_directory" "$target_directory"
}
