#!/usr/bin/env bash
# Install the repo Tabby config over the live one, carrying over the machine-local
# default profile and known hosts. Run through `just tabby`.
#
# Optional environment overrides (used for testing):
#   TABBY_CONFIG_PATH  live Tabby config to read and write
#   SSH_CONFIG_PATH    ssh config to list Host aliases from
set -euo pipefail

readonly REPO_CONFIG_PATH="$HOME/dotfiles/tabby/config.yaml"
readonly LIVE_CONFIG_PATH="${TABBY_CONFIG_PATH:-$HOME/.config/tabby/config.yaml}"
readonly SSH_CONFIG_PATH="${SSH_CONFIG_PATH:-$HOME/.ssh/config}"
readonly OPENSSH_PROFILE_PREFIX="openssh-config:"
readonly LOCAL_PROFILE_PREFIX="local:"
readonly TERMINAL_SECTION="terminal"
readonly SSH_SECTION="ssh"
readonly LOCAL_SHELL_CHOICE=0

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

assert_tabby_not_running() {
    if pgrep -x tabby >/dev/null; then
        fail "Tabby is running. Quit it fully (including the tray icon) and run again."
    fi
}

extract_section_lines() {
    local sectionName="$1" configPath="$2"
    awk -v sectionName="$sectionName" '
        $0 == sectionName ":" { isInside = 1; next }
        isInside && /^[^ \t]/ { isInside = 0 }
        isInside
    ' "$configPath"
}

read_default_profile() {
    local configPath="$1"
    extract_section_lines "$TERMINAL_SECTION" "$configPath" \
        | sed -n 's/^  profile: *//p' \
        | head -n 1
}

read_known_hosts_block() {
    local configPath="$1"
    extract_section_lines "$SSH_SECTION" "$configPath" | awk '
        isCapturing && /^   / { print; next }
        isCapturing { exit }
        /^  knownHosts:/ {
            if ($0 ~ /\[\]/) exit
            isCapturing = 1
            print
        }
    '
}

count_known_hosts() {
    local knownHostsBlock="$1"
    [ -n "$knownHostsBlock" ] || { echo 0; return; }
    printf '%s\n' "$knownHostsBlock" | grep -c '^ *- host:' || true
}

list_host_aliases() {
    awk '
        tolower($1) == "host" {
            for (columnIndex = 2; columnIndex <= NF; columnIndex++) {
                if ($columnIndex ~ /[*?]/ || $columnIndex ~ /^!/) continue
                print $columnIndex
            }
        }
    ' "$SSH_CONFIG_PATH"
}

compute_openssh_profile_id() {
    local hostAlias="$1" aliasDigest
    aliasDigest="$(printf '%s' "$hostAlias" | sha256sum | cut -d' ' -f1)"
    echo "${OPENSSH_PROFILE_PREFIX}${aliasDigest}"
}

read_choice() {
    local choice
    if { : </dev/tty; } 2>/dev/null; then
        read -r -p "Choice: " choice </dev/tty >&2 || fail "No input available."
    else
        read -r choice || fail "No input available."
    fi
    echo "$choice"
}

print_profile_menu() {
    local -a hostAliases=("$@")
    local position
    echo "Choose the default profile:" >&2
    echo "  ${LOCAL_SHELL_CHOICE}) Local shell (Tabby default)" >&2
    for position in "${!hostAliases[@]}"; do
        echo "  $((position + 1))) ${hostAliases[position]}" >&2
    done
}

is_valid_choice() {
    local choice="$1" choiceCount="$2"
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "$choiceCount" ]
}

read_host_aliases() {
    [ -r "$SSH_CONFIG_PATH" ] || return 0
    list_host_aliases
}

prompt_default_profile() {
    local -a hostAliases=("$@")
    if [ ! -r "$SSH_CONFIG_PATH" ]; then
        echo "No ssh config at $SSH_CONFIG_PATH, using the local shell." >&2
        return 0
    fi
    if [ "${#hostAliases[@]}" -eq 0 ]; then
        echo "No Host aliases in $SSH_CONFIG_PATH, using the local shell." >&2
        return 0
    fi

    print_profile_menu "${hostAliases[@]}"
    local choice
    while true; do
        choice="$(read_choice)"
        is_valid_choice "$choice" "${#hostAliases[@]}" && break
        echo "Invalid choice, enter a number between 0 and ${#hostAliases[@]}." >&2
    done
    [ "$choice" -ne "$LOCAL_SHELL_CHOICE" ] || return 0
    compute_openssh_profile_id "${hostAliases[choice - 1]}"
}

is_surviving_profile() {
    local existingProfile="$1" hostAlias
    shift
    [[ "$existingProfile" == ${OPENSSH_PROFILE_PREFIX}* ]] || return 1
    for hostAlias in "$@"; do
        [ "$(compute_openssh_profile_id "$hostAlias")" = "$existingProfile" ] && return 0
    done
    return 1
}

warn_discarded_profile() {
    local existingProfile="$1"
    [ -n "$existingProfile" ] || return 0
    [[ "$existingProfile" != ${LOCAL_PROFILE_PREFIX}* ]] || return 0
    echo "Default profile $existingProfile will not exist after install, choose a new one." >&2
}

select_default_profile() {
    local existingProfile="$1"
    shift
    if is_surviving_profile "$existingProfile" "$@"; then
        echo "Default profile kept: $existingProfile" >&2
        echo "$existingProfile"
        return 0
    fi
    warn_discarded_profile "$existingProfile"
    prompt_default_profile "$@"
}

assert_repo_config_valid() {
    [ -r "$REPO_CONFIG_PATH" ] || fail "Cannot read repo config at $REPO_CONFIG_PATH."
    grep -qx "${TERMINAL_SECTION}:" "$REPO_CONFIG_PATH" || fail "Repo config has no '${TERMINAL_SECTION}:' line."
    grep -qx "${SSH_SECTION}:" "$REPO_CONFIG_PATH" || fail "Repo config has no '${SSH_SECTION}:' line."
}

build_config() {
    local profileId="$1" knownHostsBlock="$2"
    PROFILE_ID="$profileId" KNOWN_HOSTS_BLOCK="$knownHostsBlock" awk '
        { print }
        /^terminal:$/ && ENVIRON["PROFILE_ID"] != "" { print "  profile: " ENVIRON["PROFILE_ID"] }
        /^ssh:$/ && ENVIRON["KNOWN_HOSTS_BLOCK"] != "" { print ENVIRON["KNOWN_HOSTS_BLOCK"] }
    ' "$REPO_CONFIG_PATH"
}

backup_live_config() {
    local backupPath
    backupPath="$(dirname "$LIVE_CONFIG_PATH")/config.backup-$(date +%Y%m%d-%H%M%S).yaml"
    cp "$LIVE_CONFIG_PATH" "$backupPath"
    echo "$backupPath"
}

main() {
    local existingProfile="" knownHostsBlock="" profileId="" backupPath="none"
    local -a hostAliases

    assert_tabby_not_running
    assert_repo_config_valid

    if [ -f "$LIVE_CONFIG_PATH" ]; then
        existingProfile="$(read_default_profile "$LIVE_CONFIG_PATH")"
        knownHostsBlock="$(read_known_hosts_block "$LIVE_CONFIG_PATH")"
    fi

    mapfile -t hostAliases < <(read_host_aliases)
    profileId="$(select_default_profile "$existingProfile" "${hostAliases[@]}")"

    local newConfig
    newConfig="$(build_config "$profileId" "$knownHostsBlock")"

    mkdir -p "$(dirname "$LIVE_CONFIG_PATH")"
    if [ -f "$LIVE_CONFIG_PATH" ]; then
        backupPath="$(backup_live_config)"
        echo "Backup written: $backupPath"
    fi
    printf '%s\n' "$newConfig" >"$LIVE_CONFIG_PATH"

    echo "Tabby config installed: $LIVE_CONFIG_PATH"
    echo "  Default profile: ${profileId:-Tabby default local shell}"
    echo "  Known hosts kept: $(count_known_hosts "$knownHostsBlock")"
    echo "  Backup: $backupPath"
}

main "$@"
