---
name: plan-phase
description: >
  Execute the next phase of a local multi-phase plan file, delegating
  simple sub-tasks to cheaper models, then update the plan to reflect
  what actually happened. Use when the user says "occupe-toi de la
  phase suivante", "continue le plan", or references a plan by
  name/path. If no plan path is given, list local plans for the current
  project (or ask for a name/path) — never guess which plan to run.
---

# Plan Phase

Executes the next unfinished phase of a local, phased plan document.
These plans typically live outside the repo (e.g. `~/.claude/plans/*.md`),
tracking phase-by-phase progress, decisions, and deviations for a
multi-session piece of work.

## 1. Find the plan

If a plan path was given as argument, use it directly.

Otherwise:

- Look for plan files relevant to the **current project** — check
  `~/.claude/plans/*.md` (and any other plan directory the user has
  previously pointed you to for this project) for files that reference
  this repo's name, path, or subject matter. Skim the first heading/intro
  of each candidate to confirm relevance — plan filenames are often
  random codenames, not descriptive.
- If exactly one relevant plan is found, confirm it with the user before
  proceeding rather than assuming.
- If multiple relevant plans are found, list them (path + one-line
  summary of what each covers) and ask which one.
- If none are found, ask the user for a name or path.

**Never fabricate or start a plan out of thin air, and never proceed
without a confirmed plan.** If nothing is provided and nothing relevant
is found, stop there and do nothing else.

## 2. Read the plan

Read the full plan file. Identify:

- The next phase that isn't yet marked done.
- Locked/non-negotiable decisions recorded earlier in the plan — don't
  re-litigate them.
- Any deviations already noted from earlier phases that change what
  "next phase" actually means in practice.

## 3. Execute the phase

Do the work for that phase only — not the next one, even if it looks
quick. One phase per invocation.

Delegate the code writing to the `implementer` subagent (Sonnet) instead
of doing it inline. Give it a self-contained brief: exact files, exact
pattern, locked decisions, exact verification command. Reserve the
current model for judgment calls — architecture, naming, API design,
ambiguous trade-offs — and for reviewing the delegated diff rather than
producing it.

Follow whatever project-specific conventions apply in the repo
(framework skills, CLAUDE.md, existing patterns).

## 4. Update the plan file

Before finishing, edit the plan document itself to reflect what actually
happened — not just a checkbox flip:

- Mark the phase done.
- Record what was actually built if it diverged from the original plan,
  and why.
- Note any bugs found, follow-ups left open, or trade-offs decided
  mid-phase, so the next invocation of this skill has accurate context.

## 5. Stop and wait for validation

Report what changed for this phase (plus test/lint/typecheck results if
applicable) and **stop the turn there** — even if the next phase looks
unambiguous. Do not start scaffolding or testing the next phase "while
waiting". Wait for the user's explicit go-ahead before running this
skill again for the next phase.

## 6. Commit — only within this phase's own scope

Commit only what belongs to this phase, once it's ready:

- Conventional Commits format: `type(scope): subject`.
- No `Co-Authored-By` trailer, no `Claude-Session` line, no "Generated
  with Claude Code" footer — no assistant attribution of any kind.
- Keep the commit message as concise as possible — subject line only,
  no body, unless a body is genuinely necessary to understand the
  commit's purpose.
- If the phase naturally spans several distinct concerns (e.g. data
  layer + UI + wiring), split into one commit per concern — but don't
  over-split a repetitive mechanical change into one commit per
  file/item. Ask if the right granularity is unclear.
