# Model Workflow

The main session (Opus) thinks; the `implementer` subagent (Sonnet) writes the code. This is a standing instruction to delegate: no need to ask before spawning it.

- **Main session does**: exploring the codebase, analysis, planning, design decisions, answering questions, reviewing diffs, running final verification.
- **`implementer` does**: every code change. Brief it with a self-contained prompt: files, expected behavior, patterns to follow, locked decisions, verification commands.
- **After it returns**: read the actual diff (`git diff`), check it against the plan and the conventions, run typecheck/lint/tests. Send fixes back to the same agent with `SendMessage` instead of patching inline.
- **Split big work** into independent briefs. Run them in parallel only when they touch disjoint files.
- **Only exception**: trivial edits of a few lines (typo, config value, one-line fix found during review) may be done inline.

# Applying These Rules

These rules and the convention skills (`typescript-conventions`, `adonis-conventions`, `react-conventions`) are defaults. When the project's `CLAUDE.md`, code patterns, framework or tooling require something else, follow the project; never add a rewrite or abstraction just to satisfy a rule. When you deviate, say which rule and why in one line.

# Code

- Early returns and guard clauses over nested conditionals.
- One responsibility and one level of abstraction per function, about 20 lines max. Two functions over a boolean parameter. Return values instead of mutating parameters.
- Full names without abbreviations (`getUserById`, not `getUsrById`), never `data`, `result`, `tmp`, `flag`, `obj`, `val`. Booleans `is`/`has`/`can`, functions verb + noun, collections plural, `SCREAMING_SNAKE_CASE` for true constants.
- Named constants instead of magic numbers. `const` and `readonly`, no mutation.
- No inline comments: rewrite code that needs one. Keep existing JSDoc. Delete dead code.
- Errors: handle, rethrow, or convert to a typed domain error. Validate input at system boundaries (HTTP, DB, filesystem, CLI args). Fail fast, close to the origin.
- Depend on abstractions; keep business logic free of framework and infrastructure code. Duplicate twice before abstracting.

# Tests

- Tests ship with the code. Test behavior through the public surface, never private methods.
- One behavior per test: one arrange + act, as many assertions as its outcome needs. Tests that share the same arrange and act are one test.
- Names say what should happen and when: `should return 404 when user does not exist`.
- Unit tests by default, integration tests only at boundaries (DB, HTTP, filesystem). Test files sit next to their source.

# Git

- Commit subjects in imperative mood. PR descriptions explain the why; the diff shows the what.

# Tooling

- Use Context7 for library or API documentation, code generation, setup or configuration steps, without being asked.

@RTK.md
