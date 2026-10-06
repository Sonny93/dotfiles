#!/bin/bash
# caveman — statusline badge script for Claude Code
# Reads the caveman mode flag file and outputs a colored badge.
#
# Usage in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash /path/to/caveman-statusline.sh" }
#
# Plugin users: Claude will offer to set this up on first session.
# Standalone users: install.sh wires this automatically.

#
# Also mirrors the starship prompt: directory, git branch, git status, user@host, time.

INPUT=$(cat)

RESET=$'\033[0m'
GRAY=$'\033[90m'
GRAY_BOLD=$'\033[1;90m'
CYAN_BOLD=$'\033[1;36m'
PURPLE_BOLD=$'\033[1;35m'
RED_BOLD=$'\033[1;31m'

render_directory() {
  local directory
  directory=$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
  [ -z "$directory" ] && directory="$PWD"
  printf '%s' "$directory"
}

render_git() {
  local directory="$1"
  local branch status_output symbols="" ahead_behind=""

  git -C "$directory" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  branch=$(git -C "$directory" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$directory" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  [ -z "$branch" ] && return 0

  status_output=$(git -C "$directory" --no-optional-locks status --porcelain=v1 --branch 2>/dev/null)

  printf '%s' "$status_output" | grep -q '^[MADRC]. ' && symbols+="+"
  printf '%s' "$status_output" | grep -q '^.[MD] ' && symbols+="!"
  printf '%s' "$status_output" | grep -q '^??' && symbols+="?"
  printf '%s' "$status_output" | grep -q '^UU\|^AA\|^DD' && symbols+="="

  case "$(printf '%s' "$status_output" | head -n 1)" in
    *ahead*behind*) ahead_behind="⇕" ;;
    *ahead*) ahead_behind="⇡" ;;
    *behind*) ahead_behind="⇣" ;;
  esac

  printf ' %s' "${PURPLE_BOLD} ${branch}${RESET}"
  [ -n "$symbols$ahead_behind" ] && printf ' %s' "${RED_BOLD}[${symbols}${ahead_behind}]${RESET}"
  return 0
}

render_identity() {
  printf '%s' "${GRAY_BOLD}$(whoami)${RESET}${GRAY}@$(hostname -s) $(date +%H:%M:%S)${RESET}"
}

render_caveman_badge() {
FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"

# Refuse symlinks — a local attacker could point the flag at ~/.ssh/id_rsa and
# have the statusline render its bytes (including ANSI escape sequences) to
# the terminal every keystroke.
[ -L "$FLAG" ] && return 0
[ ! -f "$FLAG" ] && return 0

# Hard-cap the read at 64 bytes and strip anything outside [a-z0-9-] — blocks
# terminal-escape injection and OSC hyperlink spoofing via the flag contents.
MODE=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
MODE=$(printf '%s' "$MODE" | tr -cd 'a-z0-9-')

# Whitelist. Anything else → render nothing rather than echo attacker bytes.
case "$MODE" in
  off|lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress) ;;
  *) return 0 ;;
esac

if [ -z "$MODE" ] || [ "$MODE" = "full" ]; then
  printf '\033[38;5;172m[CAVEMAN]\033[0m'
else
  SUFFIX=$(printf '%s' "$MODE" | tr '[:lower:]' '[:upper:]')
  printf '\033[38;5;172m[CAVEMAN:%s]\033[0m' "$SUFFIX"
fi

# Savings suffix: on by default. Opt out via CAVEMAN_STATUSLINE_SAVINGS=0.
# Reads a pre-rendered string written by caveman-stats.js so we don't shell out
# to node on every keystroke. Refuses symlinks and strips control bytes —
# same hardening as the flag file (a local attacker could plant a file with
# ANSI escape codes otherwise). Until /caveman-stats has run at least once,
# the suffix file is absent and nothing is rendered — so the default is safe
# for fresh installs (no fake number, no crash).
if [ "${CAVEMAN_STATUSLINE_SAVINGS:-1}" != "0" ]; then
  SAVINGS_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-statusline-suffix"
  if [ -f "$SAVINGS_FILE" ] && [ ! -L "$SAVINGS_FILE" ]; then
    SAVINGS=$(head -c 64 "$SAVINGS_FILE" 2>/dev/null | tr -d '\000-\037')
    [ -n "$SAVINGS" ] && printf ' \033[38;5;172m%s\033[0m' "$SAVINGS"
  fi
fi
return 0
}

DIRECTORY=$(render_directory)
printf '%s' "${CYAN_BOLD}${DIRECTORY/#"$HOME"/\~}${RESET}"
render_git "$DIRECTORY"
printf ' %s ' "${GRAY}·${RESET}"
render_identity
BADGE=$(render_caveman_badge)
[ -n "$BADGE" ] && printf ' %s' "$BADGE"
printf '\n'
