---
name: note-idea
description: >
  Record an idea in the current project's notes (~/notes/<project>.md),
  kept terse and synced to the private notes repo. Use when the user says
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

## 3. Write the idea

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

Before adding, read the file: when the idea is already there, update that entry instead of writing a second one.

## 4. Commit and push

If `~/notes` is a git repo:

```sh
git -C ~/notes add <project>.md
git -C ~/notes commit -q -m "Add idea to <project> notes"
git -C ~/notes push -q
```

The repo config already signs commits as `notes <notes@localhost>`. On push failure, tell the user; the commit stays local and the next sync pushes it.

## Done when

The entry is in `~/notes/<project>.md`, committed and pushed (or the failure reported). Reply with the entry as written.
