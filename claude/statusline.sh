#!/bin/bash
# shellcheck disable=SC2154
# Claude Code status line, wired through "statusLine" in claude/settings.json.
# Line one mirrors the Starship prompt (machine badge, directory, git branch and
# status, user@host, time), then the session name.
# Line two shows the model, duration, the transcript size on disk, and the context
# (against the auto-compact window), 5h and 7d usages. The 5h and 7d usages are
# colored by pace (usage against the elapsed share of the window, with " +N" points
# when ahead of it). They show the freshest known quota state, merged across sessions
# (a session only refreshes its own values when it calls the API), unless that window
# already reset. The merged state is logged whenever it moves forward to
# ${XDG_STATE_HOME:-$HOME/.local/state}/claude/quota-usage.tsv.

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
  printf '%s' "${GRAY_BOLD}${USER:-$(id -un)}${RESET}${GRAY}@${HOSTNAME%%.*} ${clock}${RESET}"
}

USAGE_WARNING_PERCENTAGE=50
USAGE_DANGER_PERCENTAGE=80
TOKENS_PER_THOUSAND=1000
TOKENS_PER_MILLION=1000000
SECONDS_PER_DAY=86400
UNMEASURED_CONTEXT_SYMBOL='~'
CONTEXT_WINDOW_PREFIX="context_window"
FIVE_HOUR_WINDOW_SECONDS=18000
SEVEN_DAY_WINDOW_SECONDS=604800
PACE_TOLERANCE_POINTS=5
PACE_DANGER_POINTS=25
PACE_MIDPOINT_POINTS=$(((PACE_TOLERANCE_POINTS + PACE_DANGER_POINTS) / 2))
PACE_GREEN_ANCHOR="80;200;80"
PACE_YELLOW_ANCHOR="230;200;60"
PACE_RED_ANCHOR="230;70;70"

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

elapsed_percentage() {
  local window_seconds="$1" resets_at="$2" elapsed
  elapsed=$(((window_seconds - (resets_at - EPOCHSECONDS)) * PERCENT_MULTIPLIER / window_seconds))
  [ "$elapsed" -lt 0 ] && elapsed=0
  [ "$elapsed" -gt "$PERCENT_MULTIPLIER" ] && elapsed="$PERCENT_MULTIPLIER"
  printf '%s' "$elapsed"
}

blend_anchors() {
  local from_anchor="$1" to_anchor="$2" step="$3" span="$4"
  local from_channels to_channels index blended=()
  IFS=';' read -ra from_channels <<< "$from_anchor"
  IFS=';' read -ra to_channels <<< "$to_anchor"
  for index in 0 1 2; do
    blended+=("$((from_channels[index] + (to_channels[index] - from_channels[index]) * step / span))")
  done
  printf '%s;%s;%s' "${blended[@]}"
}

pace_color() {
  local gap="$1" channels
  if [ "$gap" -le "$PACE_TOLERANCE_POINTS" ]; then
    channels="$PACE_GREEN_ANCHOR"
  elif [ "$gap" -ge "$PACE_DANGER_POINTS" ]; then
    channels="$PACE_RED_ANCHOR"
  elif [ "$gap" -le "$PACE_MIDPOINT_POINTS" ]; then
    channels=$(blend_anchors "$PACE_GREEN_ANCHOR" "$PACE_YELLOW_ANCHOR" "$((gap - PACE_TOLERANCE_POINTS))" "$((PACE_MIDPOINT_POINTS - PACE_TOLERANCE_POINTS))")
  else
    channels=$(blend_anchors "$PACE_YELLOW_ANCHOR" "$PACE_RED_ANCHOR" "$((gap - PACE_MIDPOINT_POINTS))" "$((PACE_DANGER_POINTS - PACE_MIDPOINT_POINTS))")
  fi
  printf '\033[1;38;2;%sm' "$channels"
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

is_unmeasured_context() {
  [ "$1" = "$CONTEXT_WINDOW_PREFIX" ] && [ "$context_window_is_measured" != "true" ]
}

render_unmeasured_context() {
  local label="$1" prefix="$2"
  local window_size_name="${prefix}_context_window_size"
  local window_size="${!window_size_name}"
  printf '%s' "${GRAY}[${label} ${UNMEASURED_CONTEXT_SYMBOL}"
  [ -n "$window_size" ] && printf '/%s' "$(format_token_count "$window_size")"
  printf '%s' "]${RESET}"
}

render_percentage() {
  local prefix="$1" percentage="$2" window_seconds="$3"
  local resets_at_name="${prefix}_resets_at" resets_at gap
  resets_at="${!resets_at_name}"
  if [ -z "$window_seconds" ] || [[ ! "$resets_at" =~ ^[0-9]+$ ]]; then
    printf '%s' "$(usage_color "$percentage")${percentage}%${RESET}"
    return 0
  fi
  gap=$((percentage - $(elapsed_percentage "$window_seconds" "$resets_at")))
  printf '%s' "$(pace_color "$gap")${percentage}%"
  [ "$gap" -gt "$PACE_TOLERANCE_POINTS" ] && printf ' +%s' "$gap"
  printf '%s' "$RESET"
}

render_usage() {
  local label="$1" prefix="$2" reset_format="$3" window_seconds="$4"
  local percentage_name="${prefix}_used_percentage"
  local percentage="${!percentage_name}"
  if is_unmeasured_context "$prefix"; then
    render_unmeasured_context "$label" "$prefix"
    return 0
  fi
  [ -z "$percentage" ] && return 0

  printf '%s' "${GRAY}[${label}${RESET} $(render_percentage "$prefix" "$percentage" "$window_seconds")"
  render_tokens "$prefix"
  render_reset "$prefix" "$reset_format"
  printf '%s' "${GRAY}]${RESET}"
}

render_usages() {
  local usages=()
  local window label prefix reset_format window_seconds usage
  for window in \
    "ctx|${CONTEXT_WINDOW_PREFIX}||" \
    "5h|rate_limits_five_hour|%H:%M|${FIVE_HOUR_WINDOW_SECONDS}" \
    "7d|rate_limits_seven_day|%a %Hh|${SEVEN_DAY_WINDOW_SECONDS}"; do
    IFS='|' read -r label prefix reset_format window_seconds <<< "$window"
    usage=$(render_usage "$label" "$prefix" "$reset_format" "$window_seconds")
    [ -n "$usage" ] && usages+=("$usage")
  done
  printf '%s' "${usages[*]}"
}

SESSION_NAME_MAX_LENGTH=40
MILLISECONDS_PER_MINUTE=60000
MINUTES_PER_HOUR=60
PERCENT_MULTIPLIER=100
SEPARATOR_WIDTH=3
UTF8_LOCALE="C.UTF-8"
EMPTY_SETTINGS_FILE="/dev/null"
CLAUDE_PROCESS_NAME="claude"
AUTOCOMPACT_FLAG="--autocompact"
MAX_PROCESS_ANCESTORS=8
BYTES_PER_KIBIBYTE=1024
BYTES_PER_MEBIBYTE=1048576
TRANSCRIPT_WARNING_BYTES=$((3 * BYTES_PER_MEBIBYTE))
TRANSCRIPT_DANGER_BYTES=$((6 * BYTES_PER_MEBIBYTE))
DECIMAL_BASE=10

# shellcheck disable=SC2016
SESSION_FIELDS_FILTER='
  def whole: if type == "number" then floor else . end;
  def numeric_or_null: if type == "number" then . else null end;
  def settings_object: try ($settings_text | fromjson | objects) catch {};
  def model_id_without_suffix: sub("\\[[^\\]]*\\]$"; "");
  def model_auto_compact_window($model_id):
    try (settings_object | .modelSettings[$model_id].autoCompactWindow | numeric_or_null) catch null;
  def configured_window:
    (.model.id // "") as $model_id
    | first(
        ($environment_window | if test("^[0-9]+$") then tonumber else null end),
        ($flag_window | if test("^[0-9]+$") then tonumber else null end),
        model_auto_compact_window($model_id),
        model_auto_compact_window($model_id | model_id_without_suffix),
        (try (settings_object | .autoCompactWindow | numeric_or_null) catch null),
        null
        | select(. != null)
      ) // null;
  def effective_window:
    .context_window.context_window_size as $full
    | (configured_window // $full) as $window
    | if ($window | type) == "number" and ($full | type) == "number" and $window > $full then $full else $window end;
  def effective_percentage($window):
    .context_window as $context
    | if $context.used_percentage == null or ($context.total_input_tokens | type) != "number" or ($window | type) != "number" or $window <= 0
      then ($context.used_percentage | whole)
      else ($context.total_input_tokens * $percent_multiplier / $window | floor | [., 0] | max | [., $percent_multiplier] | min)
      end;
  effective_window as $window |
  {
    workspace_current_dir: (.workspace.current_dir // .cwd),
    session_name: .session_name,
    transcript_path: .transcript_path,
    model_display_name: .model.display_name,
    effort_level: .effort.level,
    fast_mode: .fast_mode,
    cost_total_minutes: (.cost.total_duration_ms | if type == "number" then . / $milliseconds_per_minute | floor else . end),
    context_window_used_percentage: effective_percentage($window),
    context_window_is_measured: (.context_window.current_usage != null),
    context_window_total_input_tokens: .context_window.total_input_tokens,
    context_window_context_window_size: $window,
    rate_limits_five_hour_used_percentage: (.rate_limits.five_hour.used_percentage | whole),
    rate_limits_five_hour_resets_at: .rate_limits.five_hour.resets_at,
    rate_limits_seven_day_used_percentage: (.rate_limits.seven_day.used_percentage | whole),
    rate_limits_seven_day_resets_at: .rate_limits.seven_day.resets_at,
    quota_five_hour_used_percentage: .rate_limits.five_hour.used_percentage,
    quota_seven_day_used_percentage: .rate_limits.seven_day.used_percentage
  } | to_entries[] | "\(.key)=\(.value // "" | tostring | @sh)"
'

parent_process_id() {
  local stat_line
  IFS= read -r stat_line < "/proc/$1/stat" 2>/dev/null || return 1
  local after_command="${stat_line##*) }" parent_id
  read -r _ parent_id _ <<< "$after_command"
  [[ "$parent_id" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$parent_id"
}

is_claude_process() {
  local arguments=()
  mapfile -d '' -t arguments < "/proc/$1/cmdline" 2>/dev/null || return 1
  [ "${arguments[0]##*/}" = "$CLAUDE_PROCESS_NAME" ]
}

find_claude_process_id() {
  local process_id="$PPID" level
  for ((level = 0; level < MAX_PROCESS_ANCESTORS; level++)); do
    [[ "$process_id" =~ ^[0-9]+$ ]] || return 1
    [ "$process_id" -le 1 ] && return 1
    if is_claude_process "$process_id"; then
      printf '%s' "$process_id"
      return 0
    fi
    process_id=$(parent_process_id "$process_id") || return 1
  done
  return 1
}

parse_window_size() {
  local value="$1"
  [[ "$value" =~ ^([0-9]+)([kKmM]?)$ ]] || return 0
  case "${BASH_REMATCH[2]}" in
    [kK]) printf '%s' "$((BASH_REMATCH[1] * TOKENS_PER_THOUSAND))" ;;
    [mM]) printf '%s' "$((BASH_REMATCH[1] * TOKENS_PER_MILLION))" ;;
    *) printf '%s' "${BASH_REMATCH[1]}" ;;
  esac
}

read_autocompact_flag() {
  local process_id arguments=() index argument
  process_id=$(find_claude_process_id) || return 0
  mapfile -d '' -t arguments < "/proc/$process_id/cmdline" 2>/dev/null || return 0
  for index in "${!arguments[@]}"; do
    argument="${arguments[index]}"
    case "$argument" in
      "$AUTOCOMPACT_FLAG") parse_window_size "${arguments[index + 1]}"; return 0 ;;
      "$AUTOCOMPACT_FLAG"=*) parse_window_size "${argument#*=}"; return 0 ;;
    esac
  done
  return 0
}

load_session_fields() {
  local assignments settings_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  [ -r "$settings_file" ] || settings_file="$EMPTY_SETTINGS_FILE"
  assignments=$(jq -r \
    --rawfile settings_text "$settings_file" \
    --arg environment_window "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}" \
    --arg flag_window "$(read_autocompact_flag)" \
    --argjson percent_multiplier "$PERCENT_MULTIPLIER" \
    --argjson milliseconds_per_minute "$MILLISECONDS_PER_MINUTE" \
    "$SESSION_FIELDS_FILTER" <<< "$INPUT" 2>/dev/null)
  eval "$assignments"
}

QUOTA_LOG_DIRECTORY_MODE=700
QUOTA_CHANGED_STATUS="changed"
QUOTA_LOG_HEADER=$'# epoch_seconds\tfive_hour_used_percentage\tfive_hour_resets_at\tseven_day_used_percentage\tseven_day_resets_at'

quota_log_file() {
  printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/claude/quota-usage.tsv"
}

append_quota_log_line() {
  local log_file="$1" fields="$2"
  # shellcheck disable=SC2174
  mkdir -p -m "$QUOTA_LOG_DIRECTORY_MODE" -- "${log_file%/*}" 2>/dev/null || return 0
  [ -e "$log_file" ] || printf '%s\n' "$QUOTA_LOG_HEADER" 2>/dev/null >> "$log_file" || return 0
  printf '%s\t%s\n' "$EPOCHSECONDS" "$fields" 2>/dev/null >> "$log_file" || return 0
}

# shellcheck disable=SC2016
QUOTA_MERGE_PROGRAM='
  function is_newer(current_percentage, current_resets_at, last_percentage, last_resets_at) {
    if (current_resets_at == "" || current_percentage == "") return 0
    if (last_resets_at == "") return 1
    if (current_resets_at + 0 != last_resets_at + 0) return current_resets_at + 0 > last_resets_at + 0
    return current_percentage + 0 > last_percentage + 0
  }
  BEGIN {
    split(last_line, last, "\t")
    if (is_newer(five_percentage, five_resets_at, last[2], last[3])) {
      merged_five_percentage = five_percentage
      merged_five_resets_at = five_resets_at
    } else {
      merged_five_percentage = last[2]
      merged_five_resets_at = last[3]
    }
    if (is_newer(seven_percentage, seven_resets_at, last[4], last[5])) {
      merged_seven_percentage = seven_percentage
      merged_seven_resets_at = seven_resets_at
    } else {
      merged_seven_percentage = last[4]
      merged_seven_resets_at = last[5]
    }
    merged_line = merged_five_percentage "\t" merged_five_resets_at "\t" merged_seven_percentage "\t" merged_seven_resets_at
    print (merged_line != last[2] "\t" last[3] "\t" last[4] "\t" last[5]) ? "changed" : "unchanged"
    print merged_five_percentage
    print merged_five_resets_at
    print merged_seven_percentage
    print merged_seven_resets_at
  }
'

last_quota_log_line() {
  local last_line
  last_line=$(tail -n 1 -- "$1" 2>/dev/null)
  [[ "$last_line" == '#'* ]] && return 0
  printf '%s' "$last_line"
}

merge_quota_state() {
  local last_line="$1"
  LC_ALL=C awk \
    -v last_line="$last_line" \
    -v five_percentage="$quota_five_hour_used_percentage" \
    -v five_resets_at="$rate_limits_five_hour_resets_at" \
    -v seven_percentage="$quota_seven_day_used_percentage" \
    -v seven_resets_at="$rate_limits_seven_day_resets_at" \
    "$QUOTA_MERGE_PROGRAM" 2>/dev/null
}

apply_merged_window() {
  local prefix="$1" percentage="$2" resets_at="$3"
  [[ "$resets_at" =~ ^[0-9]+$ ]] || return 0
  [ "$resets_at" -gt "$EPOCHSECONDS" ] || return 0
  [[ "$percentage" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 0
  printf -v "${prefix}_used_percentage" '%s' "${percentage%%.*}"
  printf -v "${prefix}_resets_at" '%s' "$resets_at"
}

log_merged_quota_state() {
  local log_file="$1" log_fields
  shift
  printf -v log_fields '%s\t%s\t%s\t%s' "$@"
  append_quota_log_line "$log_file" "$log_fields"
}

sync_quota_state() {
  local log_file merged_output merged_lines=()
  log_file=$(quota_log_file)
  merged_output=$(merge_quota_state "$(last_quota_log_line "$log_file")") || return 0
  mapfile -t merged_lines <<< "$merged_output"
  [ "${merged_lines[0]}" = "$QUOTA_CHANGED_STATUS" ] && log_merged_quota_state "$log_file" "${merged_lines[@]:1:4}"
  apply_merged_window rate_limits_five_hour "${merged_lines[1]:-}" "${merged_lines[2]:-}"
  apply_merged_window rate_limits_seven_day "${merged_lines[3]:-}" "${merged_lines[4]:-}"
  return 0
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
  [ -n "$MACHINE_BADGE" ] && printf '%s ' "$MACHINE_BADGE"
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

render_duration() {
  [ -z "$cost_total_minutes" ] && return 0
  if [ "$cost_total_minutes" -ge "$MINUTES_PER_HOUR" ]; then
    printf '%s' "${GRAY}⏱ $((cost_total_minutes / MINUTES_PER_HOUR))h$(printf '%02d' "$((cost_total_minutes % MINUTES_PER_HOUR))")${RESET}"
  else
    printf '%s' "${GRAY}⏱ ${cost_total_minutes}m${RESET}"
  fi
}

transcript_size_color() {
  local size="$1"
  if [ "$size" -ge "$TRANSCRIPT_DANGER_BYTES" ]; then
    printf '%s' "$RED_BOLD"
  elif [ "$size" -ge "$TRANSCRIPT_WARNING_BYTES" ]; then
    printf '%s' "$YELLOW_BOLD"
  else
    printf '%s' "$GRAY"
  fi
}

format_transcript_size() {
  local size="$1" tenths
  if [ "$size" -lt "$BYTES_PER_MEBIBYTE" ]; then
    printf '%skB' "$((size / BYTES_PER_KIBIBYTE))"
    return 0
  fi
  tenths=$((size * DECIMAL_BASE / BYTES_PER_MEBIBYTE))
  printf '%s.%sMB' "$((tenths / DECIMAL_BASE))" "$((tenths % DECIMAL_BASE))"
}

render_transcript_size() {
  local size
  [ -z "$transcript_path" ] && return 0
  [ -L "$transcript_path" ] && return 0
  [ -f "$transcript_path" ] && [ -r "$transcript_path" ] || return 0
  size=$(stat -c %s -- "$transcript_path" 2>/dev/null) || return 0
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  printf '%s' "$(transcript_size_color "$size")≡ $(format_transcript_size "$size")${RESET}"
}

render_line_one_segments() {
  emit_segment "$(render_location)"
  emit_segment "$(render_identity)"
  emit_segment "$(render_session_name)"
}

render_line_two_segments() {
  emit_segment "$(render_model)"
  emit_segment "$(render_duration)"
  emit_segment "$(render_transcript_size)"
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
sync_quota_state

render_line_one_segments | print_wrapped_line
render_line_two_segments | print_wrapped_line
