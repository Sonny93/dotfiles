---
name: typescript-conventions
description: >
  TypeScript conventions for any TS/TSX file — type system rules, file and
  module structure, exports, errors, tests. Use when creating, editing,
  reviewing or refactoring TypeScript code in any project, with or without a
  framework. The stack skills (adonis-conventions, react-conventions) build
  on it.
---

These are defaults: apply them as far as the project allows, and follow the project when its needs differ (see "Applying These Rules" in `CLAUDE.md`).

# Type System

- `strict: true` always — no exceptions
- Never use `any` — use `unknown` and narrow explicitly
- Never use non-null assertion `!` — handle the null case
- Never use `as SomeType` to silence errors — fix the type
- Prefer `type` over `interface` unless declaration merging is needed
- Use discriminated unions over optional fields to model state
- Enums are forbidden — use `as const` objects instead
- Generic type parameters must be descriptive: `TEntity` not `T`
- Avoid `Partial<T>` as a lazy escape hatch — model intent explicitly
- `unknown` for external data (API responses, parsed JSON) — always validate before use
- Co-locate types with the code that owns them — no global `types.ts` dumping ground
- Return types on public functions are mandatory — never rely on inference for API surfaces
- Zod (or equivalent) at every external boundary — HTTP input, env vars, config files
- Object parameters (function arguments, component props) are typed `Readonly<...>` — they are never mutated

```ts
// ✅
type CreateUserInput = {
  email: string
  name: string
}

export function createUser(input: Readonly<CreateUserInput>): User {}

// ❌
interface CreateUserInput {
  email: string
  name: string
}

export function createUser(input: CreateUserInput) {}
```

---

# File & Module Structure

- All filenames in snake_case
- Filename matches its single export in snake_case: `UserService` → `user_service.ts`, `useAuth` → `use_auth.ts`
- One export per file — one class, one function, one hook, one component
- Group by domain, not by type: `users/` holds everything about users
- Promotion rule: code starts in the most specific folder and moves to a `shared/` folder only on its second use — never pre-emptively
- Subdivide a domain folder once it exceeds ~8 files
- No barrel `index.ts` files — import from the source file directly (a stack skill may name generated exceptions)
- Max ~150 lines per file — extract when it grows beyond that (a stack skill may override)

---

# Exports

- Named exports only — never `export default`
- Exception: a framework that resolves the module by its default export (the stack skill names the case)

---

# Errors

- Never throw a generic `Error` — one typed error class per domain failure, with a stable `code`
- Business code throws; the boundary (HTTP handler, CLI entry) translates to the outside world
- Never expose stack traces or internal messages outside

```ts
export class UserNotFoundError extends Error {
  readonly code = 'E_USER_NOT_FOUND'
}
```

A stack skill may name a framework base class instead of `Error`.

---

# Business Logic vs Framework

- Business logic lives in modules with zero framework or infrastructure imports
- Framework code (controllers, components, handlers) stays thin and delegates

---

# Tests

- Test file next to its source, same name + `.spec.ts`: `user_service.spec.ts` beside `user_service.ts`
- Build test data with factories or builders — never inline fixture objects
- Test through the public API
