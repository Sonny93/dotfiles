#!/usr/bin/env bash
# Picks the git worktree a view should work in: prints its directory on stdout.
# Usage: pick-worktree.sh [--list]
#   without argument: prints the top level of the current worktree when the repository has a single usable one, asks with fzf otherwise (Enter prints the chosen path, Esc exits 1 with nothing printed)
#   --list: prints the lines fzf would receive (tab-delimited: label, then the hidden path), without fzf
# Outside a git work tree, prints the current directory so the callers' own "not a repository" check reports it.
# A usable worktree is neither bare nor prunable, and its directory exists. Newest activity first (latest commit or latest edited changed file), so the worktree an agent is editing right now is preselected.
set -euo pipefail

readonly PROMPT="worktree > "
readonly HEADER="Entrée : choisir ce worktree · Échap : fermer"
readonly PREVIEW_COMMAND="git -C {2} status --short --branch; git -C {2} log -1 --oneline"
readonly FIELD_SEPARATOR=$'\t'
readonly LABEL_SEPARATOR=" · "
readonly CURRENT_MARKER=" (ici)"
readonly DETACHED_LABEL="détachée"
readonly SECONDS_PER_MINUTE=60
readonly SECONDS_PER_HOUR=3600
readonly SECONDS_PER_DAY=86400

fail() {
    echo "$1" >&2
    exit 1
}

list_usable_worktree_paths() {
    local line path="" is_unusable=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            "worktree "*) path="${line#worktree }"; is_unusable=0 ;;
            bare | prunable*) is_unusable=1 ;;
            "") [[ -n "$path" && "$is_unusable" -eq 0 && -d "$path" ]] && printf '%s\n' "$path"; path="" ;;
        esac
    done < <(git worktree list --porcelain; echo)
}

describe_branch() {
    git -C "$1" symbolic-ref --short --quiet HEAD || echo "$DETACHED_LABEL"
}

# Prints "<change count> <newest mtime of a changed file that still exists>"
measure_changes() {
    local entry change_count=0 newest_mtime=0 mtime is_origin_entry=0
    while IFS= read -r -d '' entry; do
        if [[ "$is_origin_entry" -eq 1 ]]; then
            is_origin_entry=0
            continue
        fi
        change_count=$((change_count + 1))
        [[ "${entry:0:2}" == *[RC]* ]] && is_origin_entry=1
        mtime=$(stat -c %Y -- "$1/${entry:3}" 2>/dev/null) || continue
        ((mtime > newest_mtime)) && newest_mtime=$mtime
    done < <(git -C "$1" status --porcelain=v1 -z --untracked-files=all)
    echo "$change_count $newest_mtime"
}

describe_change_count() {
    case "$1" in
        0) echo "aucun changement" ;;
        1) echo "1 changement" ;;
        *) echo "$1 changements" ;;
    esac
}

describe_elapsed() {
    local elapsed=$(($(date +%s) - $1))
    ((elapsed < 0)) && elapsed=0
    if ((elapsed < SECONDS_PER_MINUTE)); then
        echo "à l'instant"
    elif ((elapsed < SECONDS_PER_HOUR)); then
        echo "il y a $((elapsed / SECONDS_PER_MINUTE)) min"
    elif ((elapsed < SECONDS_PER_DAY)); then
        echo "il y a $((elapsed / SECONDS_PER_HOUR)) h"
    else
        echo "il y a $((elapsed / SECONDS_PER_DAY)) j"
    fi
}

build_label() {
    local path="$1" change_count="$2" last_activity="$3"
    printf '%s%s%s%s%s%s%s' "$(basename -- "$path")" "$LABEL_SEPARATOR" "$(describe_branch "$path")" \
        "$LABEL_SEPARATOR" "$(describe_change_count "$change_count")" "$LABEL_SEPARATOR" "$(describe_elapsed "$last_activity")"
}

# Prints "<last activity>\t<label>\t<path>" for one worktree
describe_worktree() {
    local path="$1" current_top_level="$2" change_count newest_mtime commit_time last_activity marker=""
    read -r change_count newest_mtime < <(measure_changes "$path")
    commit_time=$(git -C "$path" log -1 --format=%ct 2>/dev/null || echo 0)
    last_activity=$((commit_time > newest_mtime ? commit_time : newest_mtime))
    [[ "$path" == "$current_top_level" ]] && marker="$CURRENT_MARKER"
    printf '%s\t%s\t%s\n' "$last_activity" "$(build_label "$path" "$change_count" "$last_activity")$marker" "$path"
}

list_worktree_lines() {
    local current_top_level path
    current_top_level=$(git rev-parse --show-toplevel)
    while IFS= read -r path; do
        describe_worktree "$path" "$current_top_level"
    done < <(list_usable_worktree_paths) | sort -t "$FIELD_SEPARATOR" -k1,1nr -s | cut -f2-
}

choose_worktree() {
    local selection
    command -v fzf >/dev/null || fail "fzf not found on PATH, run 'just mise'"
    selection=$(list_worktree_lines | fzf --delimiter "$FIELD_SEPARATOR" --with-nth 1 --prompt "$PROMPT" --reverse \
        --header "$HEADER" --preview "$PREVIEW_COMMAND") || exit 1
    cut -f2 <<<"$selection"
}

main() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        pwd
        return
    fi
    if [[ "${1:-}" == "--list" ]]; then
        list_worktree_lines
        return
    fi
    if [[ "$(list_usable_worktree_paths | wc -l)" -le 1 ]]; then
        git rev-parse --show-toplevel
        return
    fi
    choose_worktree
}

main "$@"
