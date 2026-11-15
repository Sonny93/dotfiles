#!/usr/bin/env bash
# Tests of prune-plugins.sh: removal of plugins and marketplaces dotfiles managed and no longer declares.
# Usage: prune-plugins.test.sh
#   prints `ok <name>` or `FAIL <name>: <detail>` per test and a summary line; exits 1 when a test failed
# Isolation: every test runs in a mktemp -d sandbox holding a claude home and a fake claude first on PATH, removed afterwards.

set -uo pipefail

CLAUDE_DIRECTORY="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLAUDE_DIRECTORY
readonly SCRIPT="$CLAUDE_DIRECTORY/prune-plugins.sh"
readonly REMOVED_PLUGIN="gone@market"
readonly HAND_PLUGIN="hand@elsewhere"
readonly REMOVED_MARKETPLACE="old-market"

passed_count=0
failed_count=0

new_sandbox() {
    SANDBOX=$(mktemp -d)
    CLAUDE_HOME="$SANDBOX/claude"
    BASE_SETTINGS="$SANDBOX/base.json"
    CLAUDE_LOG="$SANDBOX/claude.log"
    mkdir -p "$CLAUDE_HOME/plugins" "$SANDBOX/bin"
    : >"$CLAUDE_LOG"
    cat >"$SANDBOX/bin/claude" <<FAKE
#!/usr/bin/env bash
echo "\$*" >>"$CLAUDE_LOG"
[ -z "\${FAKE_CLAUDE_FAIL:-}" ]
FAKE
    chmod +x "$SANDBOX/bin/claude"
    export PATH="$SANDBOX/bin:$ORIGINAL_PATH"
    unset FAKE_CLAUDE_FAIL
    cd "$SANDBOX" || exit 1
}

run_test() {
    local test_name="$1" output
    new_sandbox
    output=$("$test_name" 2>&1)
    if [[ -z "$output" ]]; then
        echo "ok $test_name"
        passed_count=$((passed_count + 1))
    else
        echo "FAIL $test_name: $output"
        failed_count=$((failed_count + 1))
    fi
    cd / && rm -rf "$SANDBOX"
}

write_base() {
    jq -n --argjson plugins "$1" --argjson marketplaces "$2" \
        '{enabledPlugins: $plugins, extraKnownMarketplaces: $marketplaces}' >"$BASE_SETTINGS"
}

write_state() {
    jq -n --argjson plugins "$1" --argjson marketplaces "$2" \
        '{plugins: $plugins, marketplaces: $marketplaces}' >"$CLAUDE_HOME/dotfiles-managed.json"
}

write_local_settings() {
    printf '%s\n' "$1" >"$CLAUDE_HOME/settings.json"
}

write_installed() {
    jq -n --argjson plugins "$1" '{plugins: $plugins}' >"$CLAUDE_HOME/plugins/installed_plugins.json"
}

write_known_marketplaces() {
    printf '%s\n' "$1" >"$CLAUDE_HOME/plugins/known_marketplaces.json"
}

prune() {
    "$SCRIPT" "$BASE_SETTINGS" "$CLAUDE_HOME" 2>&1
}

assert_equals() {
    [[ "$1" == "$2" ]] || echo "expected [$2], got [$1]"
}

assert_contains() {
    [[ "$1" == *"$2"* ]] || echo "expected output to contain [$2], got [$1]"
}

assert_claude_log_empty() {
    [[ ! -s "$CLAUDE_LOG" ]] || echo "expected no claude call, got [$(cat "$CLAUDE_LOG")]"
}

state_field() {
    jq -c ".$1" "$CLAUDE_HOME/dotfiles-managed.json"
}

settings_plugin_keys() {
    jq -c '.enabledPlugins | keys' "$CLAUDE_HOME/settings.json"
}

should_record_the_state_and_remove_nothing_on_first_run() {
    write_base '{"kept@market": true}' '{"market": {}}'
    write_installed '{"kept@market": []}'
    prune >/dev/null
    assert_equals "$(state_field plugins)" '["kept@market"]'
    assert_equals "$(state_field marketplaces)" '["market"]'
    assert_claude_log_empty
}

should_uninstall_a_plugin_removed_from_the_base() {
    local output
    write_base '{"kept@market": true}' null
    write_state '["gone@market","kept@market"]' '[]'
    write_installed '{"gone@market": [], "kept@market": []}'
    write_local_settings '{"enabledPlugins": {"gone@market": true, "kept@market": true}}'
    output=$(prune)
    assert_equals "$(cat "$CLAUDE_LOG")" "plugin uninstall $REMOVED_PLUGIN"
    assert_equals "$(settings_plugin_keys)" '["kept@market"]'
    assert_contains "$output" "Uninstalled plugin $REMOVED_PLUGIN"
    assert_equals "$(state_field plugins)" '["kept@market"]'
}

should_leave_a_hand_installed_plugin_untouched() {
    write_base '{"kept@market": true}' null
    write_state '["kept@market"]' '[]'
    write_installed "{\"kept@market\": [], \"$HAND_PLUGIN\": []}"
    write_local_settings "{\"enabledPlugins\": {\"kept@market\": true, \"$HAND_PLUGIN\": true}}"
    prune >/dev/null
    assert_claude_log_empty
    assert_equals "$(settings_plugin_keys)" '["hand@elsewhere","kept@market"]'
}

should_remove_a_marketplace_removed_from_the_base() {
    local output
    write_base '{}' null
    write_state '[]' '["old-market"]'
    write_known_marketplaces '{"old-market": {}, "other": {}}'
    write_local_settings '{"extraKnownMarketplaces": {"old-market": {}, "other": {}}}'
    output=$(prune)
    assert_equals "$(cat "$CLAUDE_LOG")" "plugin marketplace remove $REMOVED_MARKETPLACE"
    assert_equals "$(jq -c '.extraKnownMarketplaces | keys' "$CLAUDE_HOME/settings.json")" '["other"]'
    assert_contains "$output" "Removed marketplace $REMOVED_MARKETPLACE"
}

should_only_drop_the_settings_key_when_the_stale_plugin_is_not_installed() {
    write_base '{}' null
    write_state '["gone@market"]' '[]'
    write_local_settings '{"enabledPlugins": {"gone@market": true, "kept@market": true}}'
    prune >/dev/null
    assert_claude_log_empty
    assert_equals "$(settings_plugin_keys)" '["kept@market"]'
}

should_keep_the_old_state_and_fail_when_an_uninstall_fails() {
    local exit_code
    write_base '{}' null
    write_state '["gone@market"]' '[]'
    write_installed '{"gone@market": []}'
    write_local_settings '{"enabledPlugins": {"gone@market": true}}'
    FAKE_CLAUDE_FAIL=1 prune >/dev/null
    exit_code=$?
    assert_equals "$exit_code" "1"
    assert_equals "$(state_field plugins)" '["gone@market"]'
}

should_keep_the_old_state_and_fail_when_claude_is_missing() {
    local output exit_code
    write_base '{}' null
    write_state '["gone@market"]' '[]'
    write_installed '{"gone@market": []}'
    output=$(PATH="/usr/bin:/bin" "$SCRIPT" "$BASE_SETTINGS" "$CLAUDE_HOME" 2>&1)
    exit_code=$?
    assert_equals "$exit_code" "1"
    assert_contains "$output" "gone@market"
    assert_equals "$(state_field plugins)" '["gone@market"]'
}

should_reject_an_invalid_plugin_id() {
    local output exit_code
    write_base '{}' null
    write_state '["bad id;rm@market"]' '[]'
    output=$(prune)
    exit_code=$?
    assert_equals "$exit_code" "1"
    assert_contains "$output" "invalid plugin id"
    assert_claude_log_empty
}

should_reject_an_invalid_marketplace_name() {
    local output exit_code
    write_base '{}' null
    write_state '[]' '["bad name;"]'
    output=$(prune)
    exit_code=$?
    assert_equals "$exit_code" "1"
    assert_contains "$output" "invalid marketplace name"
    assert_claude_log_empty
}

ORIGINAL_PATH="$PATH"

for test_name in $(declare -F | awk '{print $3}' | grep '^should_'); do
    run_test "$test_name"
done

echo "$passed_count passed, $failed_count failed"
[[ "$failed_count" -eq 0 ]]
