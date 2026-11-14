#!/usr/bin/env bash
# Prints the diff of everything not committed yet, read-only: staged and unstaged changes, then the untracked files as new files; ignored files are left out.
# Usage: working-tree-diff.sh   (run from inside a git repository; prints nothing when there is no change)
# Before the first commit the empty tree stands for HEAD, so a fresh repository works too.
set -uo pipefail

readonly EMPTY_TREE_OBJECT_TYPE="tree"

resolve_base() {
    if git rev-parse --verify --quiet HEAD >/dev/null; then
        echo "HEAD"
        return
    fi
    git hash-object -t "$EMPTY_TREE_OBJECT_TYPE" /dev/null
}

print_tracked_changes() {
    git diff --no-color --no-ext-diff "$(resolve_base)" --
}

print_untracked_changes() {
    local file
    while IFS= read -r -d '' file; do
        # --no-index exits 1 when the files differ, which is the expected outcome here
        git diff --no-color --no-ext-diff --no-index -- /dev/null "$file" || true
    done < <(git ls-files --others --exclude-standard -z)
}

print_tracked_changes
print_untracked_changes
