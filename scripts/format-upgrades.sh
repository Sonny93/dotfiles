#!/usr/bin/env bash
# Prints the pacman upgrade preview as an aligned, sorted `name  old -> new` table followed by a package count.
# Usage: format-upgrades.sh INSTALLED_FILE < TRANSACTION
#   TRANSACTION holds one `name new_version` line per package (pacman -Sup --print-format '%n %v')
#   INSTALLED_FILE holds one `name version` line per installed package (pacman -Q)
#   a package missing from INSTALLED_FILE is shown as `name  (new) -> version`; empty input prints nothing
set -euo pipefail

readonly NEW_PACKAGE_MARKER="(new)"

main() {
    local installed_file="${1:-}"
    if [ ! -r "$installed_file" ]; then
        echo "Usage: format-upgrades.sh INSTALLED_FILE < TRANSACTION" >&2
        exit 2
    fi
    sort -k1,1 | awk -v marker="$NEW_PACKAGE_MARKER" -v installed_file="$installed_file" '
        BEGIN {
            count = 0
            width = 0
            while ((getline line < installed_file) > 0) {
                split(line, fields, " ")
                installed[fields[1]] = fields[2]
            }
        }
        NF >= 2 {
            names[count] = $1
            old_versions[count] = ($1 in installed) ? installed[$1] : marker
            new_versions[count] = $2
            if (length($1) > width) width = length($1)
            count++
        }
        END {
            for (index_ = 0; index_ < count; index_++)
                printf "%-*s  %s -> %s\n", width, names[index_], old_versions[index_], new_versions[index_]
            if (count > 0)
                printf "%d package%s\n", count, (count == 1 ? "" : "s")
        }'
}

main "$@"
