---
name: notion-ticket
description: >
  Work a Notion ticket end-to-end: fetch it, flag it In Progress, do the
  work, keep the ticket updated, stop and wait for the user's go-ahead
  before committing anything, then move it to Done once committed. Use when the user says "occupe-toi
  du ticket notion <id>", "prends le ticket <id>", or otherwise hands off
  one or several Notion tickets/cards to work on. When several unrelated
  tickets are handed at once, this session keeps one subject and the
  others run in their own background sessions. Requires at least one
  ticket ID or URL, or a criterion to pick tickets from the tracker
  ("les moins coûteux"): with neither, ask for it and do nothing else.
---

# Notion Ticket

Takes one or several arguments: Notion ticket IDs, page IDs, or URLs. If
no ticket was given when this skill was invoked, ask for it and stop:
don't guess which ticket, don't list the database and pick one yourself.

Uses the `mcp__claude_ai_Notion__*` tools (Notion connector from claude.ai).

## Several tickets

When more than one ticket is handed at once, split them before starting:

- Group them into subjects. Related tickets (same feature or area, likely
  the same files, one depends on another, or they need the same context)
  form one subject, worked one after the other in the same session.
  Clearly unrelated tickets are separate subjects. When unsure, keep them
  together and say so in the report so the user can split them.
- This session keeps the first subject and works it with the process
  below. Every other subject goes to its own background session through
  the `background-sessions` skill: one prompt per subject listing its
  ticket URLs, each loading this skill there.
- Handing several tickets at once is the go-ahead to launch those
  sessions: don't ask first, unless it would make more than 4 sessions in
  total including this one (each session costs quota); then ask.
- Before starting your own work, tell the user which session handles which
  tickets (session name, ticket titles) and which subject this session
  kept.
- When the user asks to choose tickets from the tracker by a criterion
  (for example "the cheapest ones"), list the chosen tickets with one line
  of reason each in that same message, then proceed as above: their
  criterion is the go-ahead. With no ticket and no criterion, the rule
  above still applies: ask and stop.

## Process

### 1. Fetch the ticket

Use `notion-fetch` (or search first with `notion-search` if given a loose
reference instead of a direct ID/URL) to load the ticket's current title,
Status, Area, Type, and body content. Read the full body: it may already
contain scope notes, links, or prior progress from an earlier session.

### 2. Flag it In Progress

Before doing any other work, update the ticket's `Status` property to
`In Progress` via `notion-update-page`. Do this first, not after
finishing: the board should reflect reality while work is happening,
not just at the end.

Don't touch the title format: no `[Type]` prefix, the `Type` select
column already carries that. Don't rename an existing title unless the
user asked you to.

### 3. Do the work

Implement whatever the ticket describes. Follow whatever project-specific
conventions apply in the repo (framework skills, CLAUDE.md, existing
patterns): this skill only governs the ticket lifecycle, not how to
write the code.

In a repository that uses devslot (a `devslot.toml`, a devslot block in
`.env`, or a devslot message at session start), write code and start
environments only in a devslot worktree: enter one with `EnterWorktree`,
named after the ticket, before the first edit. Reading, searching and
updating the ticket work from the main checkout.

### 4. Keep the ticket updated

As the work progresses (and definitely before finishing), update the
ticket body with the information someone would need to understand what
happened: what was actually built (it may diverge from the original
ask), key decisions, any follow-up left open, relevant commit-to-be
scope. Use `notion-update-page` / append content as needed. Keep it
factual and skimmable, not a transcript of the session.

### 5. Stop: do not commit yet

When the work is done:

- Leave `Status` at `In Progress` while the user reviews the result.
- **Do not** run `git commit` (or push). Report that the work is ready
  for review and wait for the user's explicit go-ahead.

### 6. Commit: only after explicit go-ahead

Once the user gives the green light:

- Commit through the `commit` skill.
- In a devslot worktree: commit there, then run `ds worktree land` from
  the worktree to bring the commits onto the main checkout's branch (the
  same go-ahead covers it). It only fast-forwards: if it says the base
  moved, `git rebase <base>` in the worktree, resolve, commit, and run it
  again. Any other refusal: explain it to the user and ask. Never push.

### 7. Move the ticket to Done

Once the commits are in, set `Status` to `Done` via `notion-update-page`.
Do the same for every ticket created or flagged In Progress during this
session (e.g. sub-tickets filed for findings) whose work is committed;
leave any whose work is still open at `In Progress` and say so in the
report. The board is sorted by last edited time, so the ticket lands at
the top of the Done column on its own.
