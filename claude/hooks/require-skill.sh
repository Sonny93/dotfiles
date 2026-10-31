#!/usr/bin/env bash
set -euo pipefail

hook_input=$(cat)
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$hook_input")
session_transcript_path=$(jq -r '.transcript_path // empty' <<<"$hook_input")
agent_id=$(jq -r '.agent_id // empty' <<<"$hook_input")
agent_type=$(jq -r '.agent_type // empty' <<<"$hook_input")
working_directory=$(jq -r '.cwd // empty' <<<"$hook_input")

editing_agent_transcript_path() {
    if [ -n "$agent_id" ]; then
        echo "${session_transcript_path%.jsonl}/subagents/agent-$agent_id.jsonl"
        return
    fi
    echo "$session_transcript_path"
}

transcript_path=$(editing_agent_transcript_path)

is_inside_adonis_project() {
    local directory
    directory=$(dirname "$1")
    while [ "$directory" != "/" ]; do
        [ -f "$directory/adonisrc.ts" ] && return 0
        [ -e "$directory/.git" ] && return 1
        directory=$(dirname "$directory")
    done
    return 1
}

required_skills_for_typescript() {
    case "$1" in
    *.d.ts | */dist/* | */build/* | */.adonisjs/*) return ;;
    *.tsx) echo "typescript-conventions react-conventions" ;;
    *.ts)
        if is_inside_adonis_project "$1"; then
            echo "typescript-conventions adonis-conventions"
            return
        fi
        echo "typescript-conventions"
        ;;
    *.mts | *.cts) echo "typescript-conventions" ;;
    *) ;;
    esac
}

required_skills_for() {
    case "$1" in
    */CLAUDE.md | */CLAUDE.local.md | */AGENTS.md | */.claude/rules/*.md) echo "claude-md" ;;
    */node_modules/* | */CHANGELOG.md | */docs/adr/*) ;;
    */README.md | */docs/*.md | */CONTRIBUTING.md | */DEPLOY.md | */PUBLISHING.md | */SECURITY.md) echo "project-docs" ;;
    *) required_skills_for_typescript "$1" ;;
    esac
}

agent_definition_path() {
    local candidate
    for candidate in "$HOME/.claude/agents/$agent_type.md" "$working_directory/.claude/agents/$agent_type.md"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return
        fi
    done
}

frontmatter_of() {
    awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } NR > 1 { print }' "$1"
}

preloaded_skills_of() {
    frontmatter_of "$1" | awk '
      /^skills:/ {
        inline = $0
        sub(/^skills:[[:space:]]*/, "", inline)
        gsub(/[\[\]"'\'']/, "", inline)
        gsub(/,/, " ", inline)
        print inline
        in_list = 1
        next
      }
      in_list && /^[[:space:]]*-[[:space:]]/ {
        item = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", item)
        gsub(/["'\'']/, "", item)
        print item
        next
      }
      { in_list = 0 }
    ' | tr -s ' \t' '\n\n' | sed '/^$/d'
}

preloaded_skills() {
    [ -n "$agent_type" ] || return 0
    local definition_path
    definition_path=$(agent_definition_path)
    [ -n "$definition_path" ] || return 0
    preloaded_skills_of "$definition_path"
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

is_skill_available() {
    if [ -n "$transcript_path" ] && [ -f "$transcript_path" ] && skill_was_loaded "$1"; then
        return 0
    fi
    grep -qxF "$1" <<<"$preloaded"
}

deny_until_loaded() {
    jq -n --arg skills "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Load the \($skills) skill(s) with the Skill tool before editing this file, then retry the edit."
      }
    }'
}

required_skills=$(required_skills_for "$file_path")

if [ -z "$required_skills" ]; then
    exit 0
fi

preloaded=$(preloaded_skills)
missing_skills=()

for skill in $required_skills; do
    is_skill_available "$skill" || missing_skills+=("$skill")
done

if [ "${#missing_skills[@]}" -eq 0 ]; then
    exit 0
fi

deny_until_loaded "${missing_skills[*]}"
