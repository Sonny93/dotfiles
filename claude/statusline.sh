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

shopt -s extglob

IFS= read -r -d '' INPUT

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

GIT_ABBREVIATED_HASH_LENGTH=7

render_directory() {
  printf '%s' "${workspace_current_dir:-$PWD}"
}

git_branch_name() {
  local status_output="$1"
  local branch="" object_id="" kind key value
  while IFS=' ' read -r kind key value; do
    [ "$kind" = "#" ] || break
    case "$key" in
      branch.head) branch="$value" ;;
      branch.oid) object_id="$value" ;;
    esac
  done <<< "$status_output"
  [ "$branch" = "(detached)" ] && branch="${object_id:0:GIT_ABBREVIATED_HASH_LENGTH}"
  printf '%s' "$branch"
}

git_status_symbols() {
  local status_output="$1"
  local staged="" modified="" untracked="" unmerged="" kind code
  while IFS=' ' read -r kind code _; do
    case "$kind" in
      1|2)
        [ "${code:0:1}" != "." ] && staged="+"
        [ "${code:1:1}" != "." ] && modified="!"
        ;;
      u) unmerged="=" ;;
      '?') untracked="?" ;;
    esac
  done <<< "$status_output"
  printf '%s' "${staged}${modified}${untracked}${unmerged}"
}

git_divergence_symbol() {
  local status_output="$1"
  local kind key ahead_behind ahead behind
  while IFS=' ' read -r kind key ahead_behind; do
    [ "$kind" = "#" ] || break
    [ "$key" = "branch.ab" ] && break
  done <<< "$status_output"
  [ "$key" = "branch.ab" ] || return 0
  ahead="${ahead_behind%% *}"
  behind="${ahead_behind##* }"
  if [ "$ahead" != "+0" ] && [ "$behind" != "-0" ]; then
    printf '⇕'
  elif [ "$ahead" != "+0" ]; then
    printf '⇡'
  elif [ "$behind" != "-0" ]; then
    printf '⇣'
  fi
}

render_git() {
  local directory="$1"
  local status_output branch symbols ahead_behind

  status_output=$(git -C "$directory" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null) || return 0

  branch=$(git_branch_name "$status_output")
  [ -z "$branch" ] && return 0
  symbols=$(git_status_symbols "$status_output")
  ahead_behind=$(git_divergence_symbol "$status_output")

  printf '%s' "${PURPLE_BOLD} ${branch}${RESET}"
  [ -n "$symbols$ahead_behind" ] && printf ' %s' "${RED_BOLD}[${symbols}${ahead_behind}]${RESET}"
  return 0
}

render_identity() {
  local clock
  printf -v clock '%(%H:%M)T' -1
  [ -n "$MACHINE_BADGE" ] && printf '%s ' "$MACHINE_BADGE"
  printf '%s' "${GRAY_BOLD}${USER:-$(id -un)}${RESET}${GRAY}@${HOSTNAME%%.*} ${clock}${RESET}"
}

USAGE_WARNING_PERCENTAGE=50
USAGE_DANGER_PERCENTAGE=80
TOKENS_PER_THOUSAND=1000
TOKENS_PER_MILLION=1000000
SECONDS_PER_DAY=86400

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
  local target_day yesterday today tomorrow
  printf -v target_day '%(%F)T' "$timestamp"
  printf -v yesterday '%(%F)T' "$((EPOCHSECONDS - SECONDS_PER_DAY))"
  printf -v today '%(%F)T' "$EPOCHSECONDS"
  printf -v tomorrow '%(%F)T' "$((EPOCHSECONDS + SECONDS_PER_DAY))"
  case "$target_day" in
    "$yesterday") printf 'yesterday' ;;
    "$today") printf 'today' ;;
    "$tomorrow") printf 'tomorrow' ;;
    *) printf '%%a' ;;
  esac
}

render_reset() {
  local resets_at_name="${1}_resets_at" reset_format="$2"
  local resets_at formatted_reset
  [ -z "$reset_format" ] && return 0
  resets_at="${!resets_at_name}"
  [ -z "$resets_at" ] && return 0
  reset_format="${reset_format//%a/$(relative_day "$resets_at")}"
  printf -v formatted_reset "%(${reset_format})T" "$resets_at"
  printf ' %s' "${GRAY}↻ ${formatted_reset}${RESET}"
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
  local used_tokens_name="${1}_total_input_tokens" window_size_name="${1}_context_window_size"
  local used_tokens="${!used_tokens_name}" window_size="${!window_size_name}"
  [ -z "$used_tokens" ] && return 0
  [ -z "$window_size" ] && return 0
  printf ' %s' "${GRAY}$(format_token_count "$used_tokens")/$(format_token_count "$window_size")${RESET}"
}

render_usage() {
  local label="$1" prefix="$2" reset_format="$3"
  local percentage_name="${prefix}_used_percentage"
  local percentage="${!percentage_name}"
  [ -z "$percentage" ] && return 0

  printf '%s' "${GRAY}[${label}${RESET} $(usage_color "$percentage")${percentage}%${RESET}"
  render_tokens "$prefix"
  render_reset "$prefix" "$reset_format"
  printf '%s' "${GRAY}]${RESET}"
}

render_usages() {
  local usages=()
  local window label prefix reset_format usage
  for window in \
    "ctx|context_window|" \
    "5h|rate_limits_five_hour|%H:%M" \
    "7d|rate_limits_seven_day|%a %Hh"; do
    IFS='|' read -r label prefix reset_format <<< "$window"
    usage=$(render_usage "$label" "$prefix" "$reset_format")
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

SESSION_FIELDS_FILTER='
  def whole: if type == "number" then floor else . end;
  {
    workspace_current_dir: (.workspace.current_dir // .cwd),
    session_name: .session_name,
    model_display_name: .model.display_name,
    effort_level: .effort.level,
    fast_mode: .fast_mode,
    prompt_cache_hit_percentage: (.prompt_cache.hit_ratio | if type == "number" then . * $percent_multiplier | floor else . end),
    prompt_cache_warm: .prompt_cache.warm,
    prompt_cache_misses: (.prompt_cache.misses | whole),
    cost_total_lines_added: (.cost.total_lines_added | whole),
    cost_total_lines_removed: (.cost.total_lines_removed | whole),
    cost_total_minutes: (.cost.total_duration_ms | if type == "number" then . / $milliseconds_per_minute | floor else . end),
    context_window_used_percentage: (.context_window.used_percentage | whole),
    context_window_total_input_tokens: .context_window.total_input_tokens,
    context_window_context_window_size: .context_window.context_window_size,
    rate_limits_five_hour_used_percentage: (.rate_limits.five_hour.used_percentage | whole),
    rate_limits_five_hour_resets_at: .rate_limits.five_hour.resets_at,
    rate_limits_seven_day_used_percentage: (.rate_limits.seven_day.used_percentage | whole),
    rate_limits_seven_day_resets_at: .rate_limits.seven_day.resets_at
  } | to_entries[] | "\(.key)=\(.value // "" | tostring | @sh)"
'

load_session_fields() {
  local assignments
  assignments=$(jq -r \
    --argjson percent_multiplier "$PERCENT_MULTIPLIER" \
    --argjson milliseconds_per_minute "$MILLISECONDS_PER_MINUTE" \
    "$SESSION_FIELDS_FILTER" <<< "$INPUT" 2>/dev/null)
  eval "$assignments"
}

emit_segment() {
  [ -n "$1" ] && printf '%s\n' "$1"
  return 0
}

visible_width() {
  local LC_ALL="$UTF8_LOCALE"
  local plain="${1//$'\033['*([0-9;])m/}"
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
  local display_name="${session_name//[[:cntrl:]]/}"
  [ -z "$display_name" ] && return 0
  if [ "${#display_name}" -gt "$SESSION_NAME_MAX_LENGTH" ]; then
    display_name="${display_name:0:$((SESSION_NAME_MAX_LENGTH - 1))}…"
  fi
  printf '%s' "$display_name"
}

render_model() {
  [ -z "$model_display_name" ] && return 0
  printf '%s' "${BOLD}${model_display_name}${RESET}"
  [ -n "$effort_level" ] && printf '%s' "${GRAY} · ${effort_level}${RESET}"
  [ "$fast_mode" = "true" ] && printf ' ⚡'
  return 0
}

render_prompt_cache() {
  local misses="${prompt_cache_misses:-0}" color="$GRAY"
  [ -z "$prompt_cache_hit_percentage" ] && return 0
  [ "$prompt_cache_warm" = "true" ] && color="$GREEN_BOLD"
  printf '%s' "${color}♻ ${prompt_cache_hit_percentage}%${RESET}"
  [ "$misses" -gt 0 ] && printf ' %s' "${RED_BOLD}✗${misses}${RESET}"
  return 0
}

render_lines() {
  local added="${cost_total_lines_added:-0}" removed="${cost_total_lines_removed:-0}"
  [ "$added" -eq 0 ] && [ "$removed" -eq 0 ] && return 0
  printf '%s %s' "${GREEN}+${added}${RESET}" "${RED}-${removed}${RESET}"
}

render_duration() {
  [ -z "$cost_total_minutes" ] && return 0
  if [ "$cost_total_minutes" -ge "$MINUTES_PER_HOUR" ]; then
    printf '%s' "${GRAY}⏱ $((cost_total_minutes / MINUTES_PER_HOUR))h$(printf '%02d' "$((cost_total_minutes % MINUTES_PER_HOUR))")${RESET}"
  else
    printf '%s' "${GRAY}⏱ ${cost_total_minutes}m${RESET}"
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

load_session_fields

render_line_one_segments | print_wrapped_line
render_line_two_segments | print_wrapped_line
