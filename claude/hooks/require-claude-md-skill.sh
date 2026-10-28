#!/usr/bin/env bash
set -euo pipefail

hook_input=$(cat)
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$hook_input")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$hook_input")

case "$file_path" in
*/CLAUDE.md | */CLAUDE.local.md | */AGENTS.md | */.claude/rules/*.md) ;;
*) exit 0 ;;
esac

skill_was_loaded() {
    jq -n -e '
      any(inputs;
        (.type == "assistant"
          and any(.message.content[]?; .type == "tool_use" and .name == "Skill" and .input.skill == "claude-md"))
        or (.type == "user"
          and (.message.content | type) == "string"
          and (.message.content | startswith("<command-name>/claude-md</command-name>"))))
    ' "$transcript_path" >/dev/null 2>&1
}

if [ -n "$transcript_path" ] && [ -f "$transcript_path" ] && skill_was_loaded; then
    exit 0
fi

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "Load the claude-md skill with the Skill tool before editing this file, then retry the edit."
  }
}'
