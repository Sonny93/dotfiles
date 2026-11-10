---
name: minimalstuff-libs
description: >
  Change an @minimalstuff library (ui, tooling) for a consumer project, release
  it, and update consumers. Use when a consumer needs a fix or feature in
  @minimalstuff/ui or @minimalstuff/tooling, when bumping them in a consumer,
  and before any release, tag or deploy of a project that depends on them
  (release-it, `just release`, `pnpm release`, git tag v*,
  `gh workflow run publish.yml`).
---

# @minimalstuff libraries

`ui` lives in `~/dev/ui-minimalstuff`, `tooling` in `~/dev/tooling-minimalstuff`. Only their owner uses them, so a release costs nothing: one release per need, even small, even several a day. Never batch changes to save releases, never use a prerelease instead.

Consumers never carry a `link:` or a `pnpm patch` on `@minimalstuff/*`: the consumer waits for the release, then installs it.

## Change a library

1. Always in a worktree branched from `origin/main`, never in the main checkout (other sessions work in the same repo): `git -C <lib> fetch origin && git -C <lib> worktree add .worktrees/<consumer>-<topic> -b <branch> origin/main`. One worktree per need.
2. In the worktree: `pnpm install`, then the change with the library's own rules (its CLAUDE.md, tests, a line under `## [Unreleased]` in `CHANGELOG.md`, `**Breaking:**` when it is one). Verify it in the library (tests, stories), not through the consumer.
3. A branch left unfinished is rebased on `origin/main` when work resumes. `main` only ever holds finished work, because a release ships everything on it.

The user's go-ahead to do the change covers committing, pushing and releasing it: no need to ask again.

## Release

1. Rebase the branch on `origin/main`, run the library's checks (`pnpm checks` in tooling, `pnpm verify` in ui), then fast-forward main: `git push origin <branch>:main`. If the push is rejected, rebase again; never force-push `main`.
2. Pick the increment from `[Unreleased]`: `**Breaking:**` gives `major` (`minor` while the version is below 1.0), `### Added` gives `minor`, otherwise `patch`.
3. Release through CI only: `gh workflow run publish.yml -R minimalstuff/<lib> -f increment=<increment>`. Never `pnpm release`, release-it, `npm publish` or `git tag` locally: tags are reserved to CI.
4. Wait for it in the background (`gh run watch <run id> -R minimalstuff/<lib> --exit-status`), then install the new version in the consumer that asked for it (see below).
5. Clean up: `git -C <lib> worktree remove .worktrees/<name>`, delete the branch locally and on the remote.

## Update a consumer

1. Read what changed between the installed and the target version in the library's CHANGELOG (`git -C <lib> fetch origin && git -C <lib> show origin/main:CHANGELOG.md`), the sections from the installed version (exclusive) to the target (inclusive). Act on the `**Breaking:**` entries; read commits only when the CHANGELOG is missing or unclear.
2. Install the exact new range (`pnpm add -D @minimalstuff/tooling@^x.y.z`, `-w` at a workspace root) and run the consumer's checks.
3. The consumer's `pnpm-workspace.yaml` must have `minimumReleaseAgeExclude: ['@minimalstuff/*']` so a same-day release installs; add it when missing, never list exact versions.

## Before releasing a consumer

Run `pnpm exec tooling check-release` in the consumer root.

- Exit 0: go on.
- Exit 1 (patch or local link on `@minimalstuff/*`): stop. Release the library change, install it, delete the patch, then retry.
- Exit 2: the lockfile is missing or invalid. Fix that, do not skip the check.

Never bypass the check or the release gates: no `--no-hooks`, `--no-verify`, `CI=` tricks, local tag push, removing the check from a workflow or Dockerfile, or deleting a patch file without depending on a released version. When blocked, tell the user what remains.
