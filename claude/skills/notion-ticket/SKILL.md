---
name: notion-ticket
description: >
  Work a Notion ticket end-to-end: fetch it, flag it In Progress, do the
  work, keep the ticket updated, stop and wait for the user's go-ahead
  before committing anything, then move it to Done once committed. Use when the user says "occupe-toi
  du ticket notion <id>", "prends le ticket <id>", or otherwise hands off
  a Notion ticket/card to work on. Requires a ticket ID or URL as
  argument — if none is given, ask for it and do nothing else.
---

# Notion Ticket

Takes one argument: a Notion ticket ID, page ID, or URL. If no ticket was
given when this skill was invoked, ask for it and stop — don't guess
which ticket, don't list the database and pick one yourself.

Uses the `mcp__notion__*` tools (official Notion MCP server).

## Process

### 1. Fetch the ticket

Use `notion-fetch` (or search first with `notion-search` if given a loose
reference instead of a direct ID/URL) to load the ticket's current title,
Status, Area, Type, and body content. Read the full body — it may already
contain scope notes, links, or prior progress from an earlier session.

### 2. Flag it In Progress

Before doing any other work, update the ticket's `Status` property to
`In Progress` via `notion-update-page`. Do this first, not after
finishing — the board should reflect reality while work is happening,
not just at the end.

Don't touch the title format — no `[Type]` prefix, the `Type` select
column already carries that. Don't rename an existing title unless the
user asked you to.

### 3. Do the work

Implement whatever the ticket describes. Follow whatever project-specific
conventions apply in the repo (framework skills, CLAUDE.md, existing
patterns) — this skill only governs the ticket lifecycle, not how to
write the code.

### 4. Keep the ticket updated

As the work progresses — and definitely before finishing — update the
ticket body with the information someone would need to understand what
happened: what was actually built (it may diverge from the original
ask), key decisions, any follow-up left open, relevant commit-to-be
scope. Use `notion-update-page` / append content as needed. Keep it
factual and skimmable, not a transcript of the session.

### 5. Stop — do not commit yet

When the work is done:

- Leave `Status` at `In Progress` while the user reviews the result.
- **Do not** run `git commit` (or push). Report that the work is ready
  for review and wait for the user's explicit go-ahead.

### 6. Commit — only after explicit go-ahead

Once the user gives the green light:

- Conventional Commits format: `type(scope): subject`.
- No `Co-Authored-By` trailer, no `Claude-Session` line, no "Generated
  with Claude Code" footer — no assistant attribution of any kind.
- Subject line only. Add a body only if it's genuinely necessary to
  understand the commit's purpose — the diff already shows the what.
- If the work spans several distinct concerns (e.g. API layer + UI +
  wiring), split into one commit per logical concern rather than one
  giant commit — but don't over-split a repetitive mechanical change
  into one commit per file/item. Ask if the right granularity is unclear.

### 7. Move the ticket to Done

Once the commits are in, set `Status` to `Done` via `notion-update-page`.
Do the same for every ticket created or flagged In Progress during this
session (e.g. sub-tickets filed for findings) whose work is committed;
leave any whose work is still open at `In Progress` and say so in the
report. The board is sorted by last edited time, so the ticket lands at
the top of the Done column on its own.
