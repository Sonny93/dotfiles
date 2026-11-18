---
name: note-idea
description: >
  Record an idea in the current project's notes (~/notes/<project>.md),
  kept terse and synced to the private notes repo, or as a ticket in the
  project's tracker when its notes file names one. Use when the user says
  "/note-idea", "note l'idée", "ajoute ça aux notes", "garde ça en idée",
  or when an idea worth keeping comes up and the user agrees to park it
  for later instead of doing it now.
---

# Note an idea

## 1. Find the notes file

- Project root: `git rev-parse --show-toplevel` from the working directory, or the working directory itself outside a repo.
- Project name: the root's directory name with every `.` and `:` replaced by `_` (the tmux session rule, `session_name_for` in `~/dotfiles/tmux/projects.sh`).
- File: `~/notes/<project>.md`. When missing, create it with `# <project>` and a blank line.

## 2. Pull

If `~/notes/.git` exists: `git -C ~/notes pull --rebase --autostash --quiet`. On failure, run `git -C ~/notes rebase --abort` if a rebase is in progress, tell the user, and stop. If `~/notes` is not a git repo, write the note anyway and tell the user to run `just notes`.

## 3. Project with a tracker

When the notes file has a `## Tracker` section, the idea becomes a ticket in that tracker and the notes file stays untouched: the same idea in two places turns into duplicates.

- Search the tracker for a ticket on the same subject. When one exists, show it and ask the user before changing it, instead of creating a second one.
- Fetch the tracker's database to learn its properties, then create the ticket in its `Ideas` status (or, without one, its initial status such as backlog or to do), in the user's language, with what a notes entry would carry: a short title, the what and why, the non-obvious leads. Fill `Type` and `Area` when the idea makes them obvious; no `[Type]` prefix in the title.
- Reply with the ticket's link and stop: steps 4 and 5 don't apply.

## 4. Write the idea

Write in the user's language. The text above the first `##` heading is the user's own free notes: leave it as it is. Add the sections below at the end of the file the first time they are needed.

Pick the size first:

- **Small idea** → bullet under `## Idées`:

  ```markdown
  - **Short title** (YYYY-MM-DD): what and why in one or two sentences.
    - Optional detail lines: a constraint, a lead, an open question. Five at most.
  ```

- **Big idea** (several steps, a design choice, more than five details) → entry under `## Grosses idées`:

  ```markdown
  ### Short title (YYYY-MM-DD)

  Goal and why, in two or three sentences.

  - Key points: one line each, ten lines at most for the whole entry.

  Plan : `~/.claude/plans/<file>.md`
  ```

  The plan line only appears when a Claude Code plan exists for it. Detail beyond ten lines belongs in that plan: the entry stays a summary, and the user can ask for a plan later.

Every line carries information the user needs to pick the idea up again cold: the what, the why, the non-obvious lead. Context they can find in the code stays out.

Before adding, read the file: when the idea is already there, show that entry and ask the user before changing it, instead of writing a second one. Never edit, reorder or delete another entry.

## 5. Commit and push

If `~/notes` is a git repo:

```sh
git -C ~/notes add <project>.md
git -C ~/notes commit -q -m "Add idea to <project> notes"
git -C ~/notes push -q
```

The repo config already signs commits as `notes <notes@localhost>`. On push failure, tell the user; the commit stays local and the next sync pushes it.

## Done when

The entry is in `~/notes/<project>.md`, committed and pushed (or the failure reported), and the reply shows it as written; or, for a project with a tracker, the ticket exists and the reply links it.
