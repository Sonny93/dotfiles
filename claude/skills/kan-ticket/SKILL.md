---
name: kan-ticket
description: >
  Work a kan.bn ticket end-to-end: fetch it, flag it In Progress, do the
  work, keep the card updated, then stop and wait for the user's
  go-ahead before committing anything. Use when the user says "occupe-toi
  du ticket kan.bn <id>", "prends la carte <id>", or otherwise hands off
  a kan.bn card to work on. Requires a card ID/public ID or board+card
  reference as argument — if none is given, ask for it and do nothing else.
---

# kan.bn Ticket

Takes one argument: a kan.bn card ID (public ID) or a direct reference to
it (board + card title). If no ticket was given when this skill was
invoked, ask for it and stop — don't guess which card, don't list the
board and pick one yourself.

Uses the `mcp__kan__*` tools (kan.bn MCP server).

## Process

### 1. Fetch the ticket

Use `card_getById` (look up the board/workspace first with `board_list` /
`board_getBySlug` if only a title was given) to load the card's current
title, list, labels, and description. Read the full description — it may
already carry scope notes or progress from an earlier session.

### 2. Flag it In Progress

kan.bn's `card_update` has no `listPublicId` param — there is no way to
move a card between lists directly. To reflect "now in progress":
`card_delete` the current card and `card_create` a new one in the
in-progress list, with the same title and the same description (carried
over as-is, not summarized away). Do this **before** starting the actual
work, not after — the board should reflect reality while work happens.

Confirm the board's list names/IDs first (they vary per board — don't
assume "À faire" / "En cours" / "Terminé" apply outside a board you've
already confirmed uses that layout).

### 3. Do the work

Implement whatever the ticket describes. Follow whatever project-specific
conventions apply in the repo (framework skills, CLAUDE.md, existing
patterns) — this skill only governs the ticket lifecycle, not how to
write the code.

### 4. Keep the ticket updated

As work progresses — and definitely before finishing — update the card's
description with what someone would need to understand what happened:
what was actually built, key decisions, any follow-up left open.

**Write the description as plain text / Markdown only — never raw HTML.**
kan.bn renders the description verbatim; if you write `<p>example</p>` it
shows those literal tags to the user instead of formatting the text. Use
Markdown syntax (line breaks, `-` lists, backticks) instead of any HTML
tag.

### 5. Stop — do not move the ticket to Done, do not commit

When the work is done:

- **Do not** delete+recreate the card into the Done/Terminé list. The
  user reviews and validates the result themselves, then moves it there.
  Leave the card in the in-progress list.
- **Do not** run `git commit` (or push). Report that the work is ready
  for review and wait for the user's explicit go-ahead.

### 6. Commit — only after explicit go-ahead

Once the user gives the green light:

- Conventional Commits format: `type(scope): subject`.
- No `Co-Authored-By` trailer, no `Claude-Session` line, no "Generated
  with Claude Code" footer — no assistant attribution of any kind.
- Subject line only. Add a body only if it's genuinely necessary to
  understand the commit's purpose — the diff already shows the what.
- If the work spans several distinct concerns, split into one commit per
  logical concern rather than one giant commit — but don't over-split a
  repetitive mechanical change into one commit per file/item. Ask if the
  right granularity is unclear.
