#!/usr/bin/env bash
# Uninstalls plugins and removes marketplaces that dotfiles managed before and no longer declares.
# Usage: prune-plugins.sh <base_settings> <claude_home>
#   state: <claude_home>/dotfiles-managed.json, written only when every removal succeeded
#   exits 1 when a removal failed, an id is invalid or claude is missing, so a later run retries

set -euo pipefail

readonly PLUGIN_PATTERN='^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$'
readonly MARKETPLACE_PATTERN='^[A-Za-z0-9._-]+$'

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <base_settings> <claude_home>" >&2
    exit 2
fi

readonly BASE_SETTINGS="$1"
readonly CLAUDE_HOME="$2"
readonly STATE_FILE="$CLAUDE_HOME/dotfiles-managed.json"
readonly LOCAL_SETTINGS="$CLAUDE_HOME/settings.json"
readonly INSTALLED_PLUGINS_FILE="$CLAUDE_HOME/plugins/installed_plugins.json"
readonly KNOWN_MARKETPLACES_FILE="$CLAUDE_HOME/plugins/known_marketplaces.json"

failure_count=0

record_failure() {
    echo "$1" >&2
    failure_count=$((failure_count + 1))
}

list_keys() {
    local file="$1" filter="$2"
    [ -f "$file" ] || return 0
    jq -r "($filter) // {} | keys[]" "$file"
}

list_state() {
    local field="$1"
    [ -f "$STATE_FILE" ] || return 0
    jq -r --arg field "$field" '(.[$field] // [])[]' "$STATE_FILE"
}

to_json_array() {
    jq -Rn '[inputs | select(length > 0)] | unique'
}

list_stale() {
    local previous="$1" current="$2"
    comm -23 <(LC_ALL=C sort <<<"$previous") <(LC_ALL=C sort <<<"$current")
}

write_atomic() {
    local destination="$1" content="$2" temporary_file
    temporary_file="$(mktemp "$destination.XXXXXX")"
    chmod 600 "$temporary_file"
    printf '%s\n' "$content" >"$temporary_file"
    mv "$temporary_file" "$destination"
}

write_state() {
    local plugins="$1" marketplaces="$2" state
    state="$(jq -n \
        --argjson plugins "$(to_json_array <<<"$plugins")" \
        --argjson marketplaces "$(to_json_array <<<"$marketplaces")" \
        '{plugins: $plugins, marketplaces: $marketplaces}')"
    mkdir -p "$CLAUDE_HOME"
    write_atomic "$STATE_FILE" "$state"
}

delete_settings_key() {
    local section="$1" key="$2" updated
    [ -f "$LOCAL_SETTINGS" ] || return 0
    jq -e --arg section "$section" --arg key "$key" '(.[$section] // {}) | has($key)' "$LOCAL_SETTINGS" >/dev/null || return 0
    updated="$(jq --arg section "$section" --arg key "$key" 'del(.[$section][$key])' "$LOCAL_SETTINGS")"
    write_atomic "$LOCAL_SETTINGS" "$updated"
}

has_key() {
    local list="$1" key="$2"
    grep -qxF -- "$key" <<<"$list"
}

run_claude() {
    if ! command -v claude >/dev/null 2>&1; then
        record_failure "WARN: claude is not on PATH, cannot run: claude $*"
        return 1
    fi
    if ! claude "$@" >/dev/null; then
        record_failure "ERROR: claude $* failed"
        return 1
    fi
}

prune_plugin() {
    local plugin="$1" installed="$2"
    if [[ ! "$plugin" =~ $PLUGIN_PATTERN ]]; then
        record_failure "ERROR: invalid plugin id '$plugin'"
        return 0
    fi
    if has_key "$installed" "$plugin"; then
        run_claude plugin uninstall "$plugin" || return 0
        echo "Uninstalled plugin $plugin"
    fi
    delete_settings_key enabledPlugins "$plugin"
}

prune_marketplace() {
    local marketplace="$1" known="$2"
    if [[ ! "$marketplace" =~ $MARKETPLACE_PATTERN ]]; then
        record_failure "ERROR: invalid marketplace name '$marketplace'"
        return 0
    fi
    if has_key "$known" "$marketplace"; then
        run_claude plugin marketplace remove "$marketplace" || return 0
        echo "Removed marketplace $marketplace"
    fi
    delete_settings_key extraKnownMarketplaces "$marketplace"
}

prune_each() {
    local prune_function="$1" stale="$2" reference="$3" id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        "$prune_function" "$id" "$reference"
    done <<<"$stale"
}

main() {
    local current_plugins current_marketplaces
    current_plugins="$(list_keys "$BASE_SETTINGS" '.enabledPlugins')"
    current_marketplaces="$(list_keys "$BASE_SETTINGS" '.extraKnownMarketplaces')"

    if [ -f "$STATE_FILE" ]; then
        prune_each prune_plugin "$(list_stale "$(list_state plugins)" "$current_plugins")" "$(list_keys "$INSTALLED_PLUGINS_FILE" '.plugins')"
        prune_each prune_marketplace "$(list_stale "$(list_state marketplaces)" "$current_marketplaces")" "$(list_keys "$KNOWN_MARKETPLACES_FILE" '.')"
    fi

    if [ "$failure_count" -gt 0 ]; then
        echo "Some removals failed, managed state kept: rerun 'just claude' to retry." >&2
        exit 1
    fi
    write_state "$current_plugins" "$current_marketplaces"
}

main
