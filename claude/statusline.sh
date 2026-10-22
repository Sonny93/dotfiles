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
YELLOW_BOLD=$'\033[1;33m'
GREEN_BOLD=$'\033[1;32m'
GREEN=$'\033[32m'
RED=$'\033[31m'
BOLD=$'\033[1m'

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

  printf '%s' "${PURPLE_BOLD} ${branch}${RESET}"
  [ -n "$symbols$ahead_behind" ] && printf ' %s' "${RED_BOLD}[${symbols}${ahead_behind}]${RESET}"
  return 0
}

render_identity() {
  [ -n "$MACHINE_BADGE" ] && printf '%s ' "$MACHINE_BADGE"
  printf '%s' "${GRAY_BOLD}$(whoami)${RESET}${GRAY}@$(hostname -s) $(date +%H:%M:%S)${RESET}"
}

USAGE_WARNING_PERCENTAGE=50
USAGE_DANGER_PERCENTAGE=80
TOKENS_PER_THOUSAND=1000
TOKENS_PER_MILLION=1000000

usage_color() {
  local percentage="$1"
  if [ "$percentage" -ge "$USAGE_DANGER_PERCENTAGE" ]; then
    printf '%s' "$RED_BOLD"
  elif [ "$percentage" -ge "$USAGE_WARNING_PERCENTAGE" ]; then
    printf '%s' "$YELLOW_BOLD"
  else
    printf '%s' "$GREEN_BOLD"
  fi
}

relative_day() {
  local timestamp="$1"
  case "$(date -d "@${timestamp}" +%F)" in
    "$(date -d '-1 day' +%F)") printf 'yesterday' ;;
    "$(date +%F)") printf 'today' ;;
    "$(date -d '+1 day' +%F)") printf 'tomorrow' ;;
    *) printf '%%a' ;;
  esac
}

render_reset() {
  local window_path="$1" reset_format="$2"
  local resets_at
  [ -z "$reset_format" ] && return 0
  resets_at=$(printf '%s' "$INPUT" | jq -r "${window_path}.resets_at // empty" 2>/dev/null)
  [ -z "$resets_at" ] && return 0
  reset_format="${reset_format//%a/$(relative_day "$resets_at")}"
  printf ' %s' "${GRAY}↻ $(date -d "@${resets_at}" +"$reset_format")${RESET}"
}

format_token_count() {
  local token_count="$1"
  if [ "$token_count" -ge "$TOKENS_PER_MILLION" ]; then
    printf '%sM' "$((token_count / TOKENS_PER_MILLION))"
  else
    printf '%sk' "$((token_count / TOKENS_PER_THOUSAND))"
  fi
}

render_tokens() {
  local window_path="$1"
  local used_tokens window_size
  used_tokens=$(printf '%s' "$INPUT" | jq -r "${window_path}.total_input_tokens // empty" 2>/dev/null)
  window_size=$(printf '%s' "$INPUT" | jq -r "${window_path}.context_window_size // empty" 2>/dev/null)
  [ -z "$used_tokens" ] && return 0
  [ -z "$window_size" ] && return 0
  printf ' %s' "${GRAY}$(format_token_count "$used_tokens")/$(format_token_count "$window_size")${RESET}"
}

render_usage() {
  local label="$1" window_path="$2" reset_format="$3"
  local percentage
  percentage=$(printf '%s' "$INPUT" | jq -r "${window_path}.used_percentage // empty | floor" 2>/dev/null)
  [ -z "$percentage" ] && return 0

  printf '%s' "${GRAY}[${label}${RESET} $(usage_color "$percentage")${percentage}%${RESET}"
  render_tokens "$window_path"
  render_reset "$window_path" "$reset_format"
  printf '%s' "${GRAY}]${RESET}"
}

render_usages() {
  local usages=()
  local window label window_path reset_format usage
  for window in \
    "ctx|.context_window|" \
    "5h|.rate_limits.five_hour|%H:%M" \
    "7d|.rate_limits.seven_day|%a %Hh"; do
    IFS='|' read -r label window_path reset_format <<< "$window"
    usage=$(render_usage "$label" "$window_path" "$reset_format")
    [ -n "$usage" ] && usages+=("$usage")
  done
  printf '%s' "${usages[*]}"
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

SESSION_NAME_MAX_LENGTH=40
MILLISECONDS_PER_MINUTE=60000
MINUTES_PER_HOUR=60
PERCENT_MULTIPLIER=100
SEPARATOR_WIDTH=3
UTF8_LOCALE="C.UTF-8"

read_json() {
  printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null
}

emit_segment() {
  [ -n "$1" ] && printf '%s\n' "$1"
  return 0
}

visible_width() {
  local LC_ALL="$UTF8_LOCALE"
  local plain
  plain=$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g')
  printf '%s' "${#plain}"
}

render_location() {
  local directory git_part
  directory=$(render_directory)
  git_part=$(render_git "$directory")
  printf '%s' "${CYAN_BOLD}${directory/#"$HOME"/\~}${RESET}"
  [ -n "$git_part" ] && printf ' %s' "$git_part"
  return 0
}

render_session_name() {
  local LC_ALL="$UTF8_LOCALE"
  local session_name
  session_name=$(read_json '.session_name // empty' | tr -d '\000-\037')
  [ -z "$session_name" ] && return 0
  if [ "${#session_name}" -gt "$SESSION_NAME_MAX_LENGTH" ]; then
    session_name="${session_name:0:$((SESSION_NAME_MAX_LENGTH - 1))}…"
  fi
  printf '%s' "$session_name"
}

render_model() {
  local model_name effort_level
  model_name=$(read_json '.model.display_name // empty')
  [ -z "$model_name" ] && return 0
  effort_level=$(read_json '.effort.level // empty')
  printf '%s' "${BOLD}${model_name}${RESET}"
  [ -n "$effort_level" ] && printf '%s' "${GRAY} · ${effort_level}${RESET}"
  [ "$(read_json '.fast_mode // empty')" = "true" ] && printf ' ⚡'
  return 0
}

render_prompt_cache() {
  local hit_percentage misses color
  hit_percentage=$(read_json ".prompt_cache.hit_ratio // empty | . * ${PERCENT_MULTIPLIER} | floor")
  [ -z "$hit_percentage" ] && return 0
  color="$GRAY"
  [ "$(read_json '.prompt_cache.warm // empty')" = "true" ] && color="$GREEN_BOLD"
  printf '%s' "${color}♻ ${hit_percentage}%${RESET}"
  misses=$(read_json '.prompt_cache.misses // 0 | floor')
  [ "$misses" -gt 0 ] && printf ' %s' "${RED_BOLD}✗${misses}${RESET}"
  return 0
}

render_lines() {
  local added removed
  added=$(read_json '.cost.total_lines_added // 0 | floor')
  removed=$(read_json '.cost.total_lines_removed // 0 | floor')
  [ "$added" -eq 0 ] && [ "$removed" -eq 0 ] && return 0
  printf '%s %s' "${GREEN}+${added}${RESET}" "${RED}-${removed}${RESET}"
}

render_duration() {
  local total_minutes
  total_minutes=$(read_json ".cost.total_duration_ms // empty | . / ${MILLISECONDS_PER_MINUTE} | floor")
  [ -z "$total_minutes" ] && return 0
  if [ "$total_minutes" -ge "$MINUTES_PER_HOUR" ]; then
    printf '%s' "${GRAY}⏱ $((total_minutes / MINUTES_PER_HOUR))h$(printf '%02d' "$((total_minutes % MINUTES_PER_HOUR))")${RESET}"
  else
    printf '%s' "${GRAY}⏱ ${total_minutes}m${RESET}"
  fi
}

render_line_one_segments() {
  emit_segment "$(render_location)"
  emit_segment "$(render_identity)"
  emit_segment "$(render_session_name)"
  emit_segment "$(render_caveman_badge)"
}

render_line_two_segments() {
  emit_segment "$(render_model)"
  emit_segment "$(render_prompt_cache)"
  emit_segment "$(render_lines)"
  emit_segment "$(render_duration)"
  emit_segment "$(render_usages)"
}

is_wrapping_enabled() {
  [[ "$COLUMNS" =~ ^[0-9]+$ ]]
}

print_wrapped_line() {
  local separator="${GRAY}·${RESET}"
  local segments=() segment segment_width row="" row_width=0
  mapfile -t segments
  for segment in "${segments[@]}"; do
    segment_width=$(visible_width "$segment")
    if [ -z "$row" ]; then
      row="$segment"
      row_width="$segment_width"
    elif is_wrapping_enabled && [ $((row_width + SEPARATOR_WIDTH + segment_width)) -gt "$COLUMNS" ]; then
      printf '%s\n' "$row"
      row="$segment"
      row_width="$segment_width"
    else
      row+=" ${separator} ${segment}"
      row_width=$((row_width + SEPARATOR_WIDTH + segment_width))
    fi
  done
  [ -n "$row" ] && printf '%s\n' "$row"
  return 0
}

render_line_one_segments | print_wrapped_line
render_line_two_segments | print_wrapped_line
