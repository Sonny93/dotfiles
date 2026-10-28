---
name: claude-md
description: >
  Rules for what goes in a CLAUDE.md, CLAUDE.local.md, AGENTS.md or
  .claude/rules/ file. Use before creating, editing, adding a line to,
  or auditing any of them, including mid-task when a decision, gotcha
  or convention seems worth recording.
---

# CLAUDE.md

A CLAUDE.md is loaded into every turn of every session. Each line costs tokens and dilutes the attention every other line gets, relevant or not. The instinct is to record everything; the job is the opposite: keep only what the agent cannot find by reading the repo.

## The test

For every line: can the agent find this in one or two lookups (code, config, `package.json`, Justfile, README, tests, git log)? Yes → it stays out. No → it goes in, as one line.

Goes in:

- A one-line pitch of the project.
- How to verify work: the check command, what must be running first (database, services), how to run a single test, any trap in test discovery.
- Skills and conventions to load, by name. Their content stays in the skill.
- Decisions the code does not explain, each with its why in a clause: a library chosen over alternatives, a boundary that must hold, a privacy or security rule.
- Gotchas: misleading code, dependency bugs, environment traps.
- Rejected options, so they are not proposed again.
- Anything the user had to correct twice.

Stays out:

- Architecture, directory maps, feature descriptions, protocols, schemas, data flows. The code is the source of truth and the copy goes stale.
- Versions, commands and constants already in config files.
- Project status, step logs, history.
- Advice the model already follows by default: clear names, DRY, small functions, handle errors.
- Content another file already holds (skill, README, docs): point to it.
- Mentions of the user's other projects.

## Where else it goes

- Rule for one part of the tree → `.claude/rules/<topic>.md` with a `paths:` frontmatter, loaded only there.
- Procedure (release, migration, deploy) → a skill.
- Rule with no exception (never edit X, always run Y) → a hook or a lint rule. Text is followed most of the time, a hook every time.
- User preference across projects → `~/.claude/CLAUDE.md`. Personal to one repo → `CLAUDE.local.md`, gitignored.

## Editing mid-task

1. Apply the test to the line. If it fails, add nothing and say so in one line.
2. Find the existing line on the same subject and update it instead of adding a second one.
3. Write one line: the fact, plus its why when not obvious. State the target behavior; keep "never" for hard guardrails.
4. Delete any line the change made untrue.

Done when the new line passes the test and no line describes what the change made untrue.

## Full audit

When asked to audit or clean the file, or when creating it:

1. Measure lines and words. Benchmarks: Anthropic says under 200 lines; HumanLayer's root file is under 60; large repos sit at 600 to 1,200 words (biome, supabase, sentry). A small project stays well under 1,000 words.
2. Classify every line: keep, cut (findable), move (rules, skill, hook), stale, or contradicting another line.
3. Check the verify section exists, and run its commands.
4. Check every path, command and name the file references still exists.
5. Rewrite in this order: pitch, verify, conventions, decisions, gotchas, rejected. Keep the file's language.
6. Report the size before and after, what moved where, and what was cut.

Done when every line was classified and every referenced path and command was checked.
