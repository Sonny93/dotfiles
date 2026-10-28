#!/usr/bin/env bash
set -euo pipefail

hook_input=$(cat)
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$hook_input")
session_transcript_path=$(jq -r '.transcript_path // empty' <<<"$hook_input")
agent_id=$(jq -r '.agent_id // empty' <<<"$hook_input")

editing_agent_transcript_path() {
    if [ -n "$agent_id" ]; then
        echo "${session_transcript_path%.jsonl}/subagents/agent-$agent_id.jsonl"
        return
    fi
    echo "$session_transcript_path"
}

transcript_path=$(editing_agent_transcript_path)

required_skill_for() {
    case "$1" in
    */CLAUDE.md | */CLAUDE.local.md | */AGENTS.md | */.claude/rules/*.md) echo "claude-md" ;;
    */node_modules/* | */CHANGELOG.md | */docs/adr/*) ;;
    */README.md | */docs/*.md | */CONTRIBUTING.md | */DEPLOY.md | */PUBLISHING.md | */SECURITY.md) echo "project-docs" ;;
    *) ;;
    esac
}

skill_was_loaded() {
    jq -n -e --arg skill "$1" '
      any(inputs;
        (.type == "assistant"
          and any(.message.content[]?; .type == "tool_use" and .name == "Skill" and .input.skill == $skill))
        or (.type == "user"
          and (.message.content | type) == "string"
          and (.message.content | startswith("<command-name>/" + $skill + "</command-name>"))))
    ' "$transcript_path" >/dev/null 2>&1
}

deny_until_loaded() {
    jq -n --arg skill "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Load the \($skill) skill with the Skill tool before editing this file, then retry the edit."
      }
    }'
}

required_skill=$(required_skill_for "$file_path")

if [ -z "$required_skill" ]; then
    exit 0
fi

if [ -n "$transcript_path" ] && [ -f "$transcript_path" ] && skill_was_loaded "$required_skill"; then
    exit 0
fi

deny_until_loaded "$required_skill"
