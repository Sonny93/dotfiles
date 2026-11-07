---
name: minimalstuff-libs
description: >
  Change an @minimalstuff library (ui, tooling) from a consumer project, and
  release a project that depends on them. Use when a consumer needs a fix or
  feature in @minimalstuff/ui or @minimalstuff/tooling, when adding a link: or
  pnpm patch on them, and before any release, tag or deploy of a project that
  depends on them (release-it, `just release`, `pnpm release`, git tag v*,
  `gh workflow run publish.yml`).
---

# @minimalstuff libraries

`ui` lives in `~/dev/ui-minimalstuff`, `tooling` in `~/dev/tooling-minimalstuff`. Each repo documents the details: `docs/developing_from_a_consumer.md` (ui), `docs/releasing.md` (both).

## Change a library from a consumer

1. Work only in a git worktree of the library, never in its main checkout (other sessions may use it): `git -C <lib> worktree add .worktrees/<consumer>-<topic> -b <branch>`. One worktree per need.
2. In the worktree: `pnpm install`, then the watch build (`pnpm dev:lib` in ui).
3. In the consumer: depend on the worktree with `link:<path to worktree>`, `pnpm install`. For ui, the consumer's Vite config needs `resolve.dedupe: ['react', 'react-dom']`.
4. The change follows the library's own rules: tests, CHANGELOG line under `[Unreleased]`, its CLAUDE.md.
5. `pnpm patch` only as a temporary fallback, when something must build before the library is released (a Docker image cannot see a `link:` path).

## Finish

1. Merge the worktree branch in the library (ask the user before committing or pushing, as usual).
2. Release the library through CI only: `gh workflow run publish.yml -R minimalstuff/<lib> -f increment=<patch|minor|major>`. Never run `pnpm release`, release-it or `git tag` locally: tags are reserved to CI.
3. In the consumer: depend on the published version, remove the `link:` or the patch (and its `patches/` file), `pnpm install`. If the consumer has `minimumReleaseAgeExclude`, add the exact new version (`@minimalstuff/ui@x.y.z`) there.
4. `git -C <lib> worktree remove .worktrees/<name>`.

## Before releasing a consumer

Run `pnpm exec tooling check-release` in the consumer root.

- Exit 0: go on.
- Exit 1 (patch or local link on `@minimalstuff/*`): stop. Do the Finish steps first.
- Exit 2: the lockfile is missing or invalid. Fix that, do not skip the check.

Never bypass the check or the release gates: no `--no-hooks`, `--no-verify`, `CI=` tricks, local tag push, removing the check from a workflow or Dockerfile, or deleting a patch file without depending on a released version. When blocked, tell the user what remains.
