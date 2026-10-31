---
name: audit
description: >
  Run a full security, accessibility, performance and documentation audit of a repo,
  branch or path with independent reviewer subagents, and write the
  findings as a phased plan file. Use when the user says "/audit",
  "audite le repo", "audit de la branche X".
disable-model-invocation: true
argument-hint: "[all | <branch> | <path>]"
---

# Audit

Audits a codebase with read-only reviewers and turns the findings into a
plan that `plan-phase` can execute. It fixes nothing.

## 1. Scope

- No argument or `all`: the whole repo.
- A branch name: the diff against the default branch.
- A path: that subtree.

State the project's size and stakes in one line (small PWA, multi-user
service, public API, credentials, money, personal data). Reviewers use it
to decide how much to report.

## 2. Pick the reviewers

- `security-reviewer`: always.
- `a11y-reviewer`: if there is UI.
- `perf-reviewer`: if there is a database, jobs, I/O or a frontend bundle.
- Docs: if the scope holds a README, `docs/`, a `CLAUDE.md` or an `AGENTS.md`. A `general-purpose` agent briefed to load the `project-docs` and `claude-md` skills and run their "Full audit" in report-only mode: no edits, no deletions, every proposed change goes into its findings (doc that no longer matches the code, dead commands and paths, `CLAUDE.md` lines to cut or move), in the same output format.

Launch them in parallel in a single message. Each brief is
self-contained: scope (files or diff range), stakes, what to skip
(generated code, vendored code, lockfiles, style), and a reminder of the
output format (`Verdict`, findings sorted by severity, "No findings." is
valid). Never pass your own opinions or suspected issues.

For a whole-repo audit of a large repo, split by app or package into
several briefs of the same reviewer, about 6 agents in total.

## 3. Consolidate

- Dedupe findings reported by several reviewers or several briefs.
- Re-check every Critical and High yourself by reading the code. Drop
  what does not hold, downgrade what is overstated.
- Sort by severity.

## 4. Write the plan

Read `claude/skills/plan-phase/SKILL.md` first and match the plan format
it expects (phases, progress tracking, decisions, deviations).

Path: `~/.claude/plans/<project>-audit-<YYYY-MM-DD>.md`.

- Phases ordered Critical and High first, then Medium, then Low.
- Each task: `file:line`, problem, fix, which reviewer found it.
- Open the plan with scope, stakes and the reviewers' verdicts.

## 5. Report

Print a short summary: counts per severity, the top 3 findings, and the
plan path. Suggest `/plan-phase <path>`. Fix nothing.
