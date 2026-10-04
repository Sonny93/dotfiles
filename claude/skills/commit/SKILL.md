---
name: commit
description: >
  Commit the current changes with a clean, Conventional Commits message
  and no assistant attribution. Use when the user says "/commit",
  "commit ça", "fais le commit", or otherwise asks to commit the
  current work. Invoking this skill IS the go-ahead — don't ask for a
  second confirmation before committing.
---

# Commit

## 1. Gather context

Run in parallel:

- `git status` — see staged and untracked files (never `-uall`).
- `git diff` (staged) and `git diff` (unstaged) — see what's actually
  changing.
- `git log --oneline -10` — match this repo's existing message style.

## 2. Stage what belongs

If nothing is staged yet, stage the files relevant to this commit by
name. Never `git add -A` or `git add .` — review `git status` after
staging to make sure nothing unintended (secrets, build artifacts,
unrelated WIP) got included. If a file looks suspicious even with an
innocuous name, check its contents before committing.

## 3. Draft the message

- Conventional Commits format: `type(scope): subject`.
- No `Co-Authored-By` trailer, no `Claude-Session` line, no "Generated
  with Claude Code" footer — no assistant attribution of any kind.
- Subject line only. Add a body only if it's genuinely necessary to
  understand the commit's purpose — the diff already shows the what.
- If the work spans several distinct concerns (e.g. API layer + UI +
  wiring), split into one commit per logical concern rather than one
  giant commit — but don't over-split a repetitive mechanical change
  into one commit per file/item. Ask if the right granularity is unclear.

## 4. Commit

Create the commit(s) via a HEREDOC to preserve formatting. Never use
`--no-verify` or skip hooks unless the user explicitly asked for it. If
a pre-commit hook fails, fix the underlying issue and create a new
commit — don't amend, since the failed attempt never actually committed.

Report the resulting commit hash(es) and message(s) — no other summary
needed.
