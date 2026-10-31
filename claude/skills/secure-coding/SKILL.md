---
name: secure-coding
description: >
  Security rules for code that handles identity, data, files, processes or
  outbound requests — authorization, injection, XSS, path traversal, SSRF,
  secrets, tokens, rate limiting, logging, headers, supply chain. Use when
  writing or reviewing any backend, API, auth flow, upload, scraper, ffmpeg
  or child-process code, browser extension, or mobile token storage.
  Triggers: auth, login, session, token, Bouncer, policy, IDOR, CSRF, CORS,
  Shield, CSP, XSS, dangerouslySetInnerHTML, rawQuery, exec, spawn, ffmpeg,
  upload, path traversal, SSRF, fetch url, rate limit, secrets, .env, audit.
---

These are defaults: apply them as far as the project allows, and follow the project when its needs differ (see "Applying These Rules" in `CLAUDE.md`).

**Proportionality.** Scale to the project. A small PWA, script or prototype gets the **Always** list; a multi-user service, a public API, or anything holding credentials, money or personal data gets everything. Skip an item that does not pay off here and name it once in the final report, never in every message.

---

# Always

- **Authorization on every route and action**: a Bouncer policy per action, queries scoped by owner. Never trust an ID from input (IDOR).
- **Validate at every boundary** with VineJS (see **adonis-conventions**).
- **No string-built queries or commands**: Lucid bindings, `execFile`/`spawn` with argument arrays.
- **No secrets in code, logs, client bundles or Inertia shared props.** Env validated in `start/env.ts`.
- **No `dangerouslySetInnerHTML`** without a sanitizer (DOMPurify); validate URL schemes before `href`/`src`.
- **Errors**: no stack traces or internals in responses; no tokens or PII in logs.

```ts
// ❌ IDOR: any user can read any post
const post = await Post.findOrFail(params.id)

// ✅ scoped to the owner, then authorized
const post = await auth.getUserOrFail().related('posts').query().where('id', params.id).firstOrFail()
await bouncer.with(PostPolicy).authorize('view', post)
```

```ts
// ❌ injection
await db.rawQuery(`select * from users where email = '${email}'`)
await exec(`ffmpeg -i ${inputPath} out.mp4`)

// ✅ bindings and argument arrays
await db.rawQuery('select * from users where email = ?', [email])
await execFile('ffmpeg', ['-i', inputPath, 'out.mp4'])
```

---

# When it pays off

**Authentication and sessions**
- Rotate the session on login; cookies `httpOnly`, `secure`, `sameSite`. CSRF through Shield for session apps.
- Mobile and API clients use bearer access tokens, stored hashed server-side.
- Passwords through the Adonis hash (argon2/bcrypt). Tokens from `string.random` or `crypto.randomBytes`, stored as hashes, compared with `timingSafeEqual`, short TTL, single use.

**Output and headers**
- Shield: CSP, HSTS, `frame-ancestors`/X-Frame-Options, `nosniff`.
- CORS: explicit origins, never `*` with credentials.
- Log with structured logging; strip CR/LF from user values (log injection).

**Files**
- Path traversal: `resolve` against a base dir and check the result starts with it. Prefer IDs over user-supplied paths.
- Uploads: size limit, type by magic bytes, stored outside the public dir, random file names.

```ts
const target = resolve(BASE_DIR, requestedName)
if (!target.startsWith(BASE_DIR + sep)) throw new ForbiddenException()
```

**Outbound requests (SSRF)** — scrapers, proxies, webhooks
- Allowlist hosts, or resolve DNS and block private, loopback, link-local and metadata IPs (`169.254.169.254`) before connecting.
- Connect to the resolved IP, re-check on every redirect, set timeouts and a response size cap, allow only `http(s)`.

**Abuse**
- `@adonisjs/limiter` on login, signup, reset and expensive endpoints. Cap pagination size and request body size.

**Supply chain**
- Lockfile committed; pnpm `minimumReleaseAge`; `onlyBuiltDependencies` allowlist for install scripts; few, maintained dependencies.

**Mobile and extension**
- Tokens in `expo-secure-store`, never AsyncStorage or SQLite.
- Extension: minimal permissions, validate every message from content scripts and web pages (check sender and shape), no remote code.

---

# Designing a feature

Answer before building anything that touches identity or data:

- Who can read and modify each resource? What does an attacker gain from each endpoint?
- Account enumeration: same response and same timing for a known and an unknown email.
- Email verification before the account is trusted.
- Passwords per NIST SP 800-63B: minimum length (8+, 15 if the only factor), breached-password check, no composition rules, no forced rotation.
- Reset flow: single-use hashed token, short TTL, invalidate existing sessions on use.
- Data retention and PII minimization: store only what the feature needs, define when it is deleted.

---

# When NOT to apply

- Throwaway prototypes run locally and never exposed.
- Generated code (migrations, framework scaffolds) unless you edit it.
- Test fixtures with fake credentials, clearly marked as such.

---

# Rationalizations to reject

| Rationalization | Reality |
| --- | --- |
| "It's only internal" | Internal tools get exposed; authorization still applies. |
| "The frontend already validates" | Clients are controlled by the attacker; validate on the server. |
| "Nobody will guess the ID" | Unguessable is not authorized; scope the query by owner. |
| "React escapes everything" | Not `dangerouslySetInnerHTML`, `href="javascript:"` or server-built HTML. |
| "I'll add auth later" | Unprotected routes ship; add the policy with the route. |
| "It's just a small fetch to a user URL" | That is SSRF; internal services and cloud metadata are reachable. |
| "The secret is in a private repo" | Repos go public and leak; use env and a secret scanner. |
| "Rate limiting is premature" | Login and reset endpoints are attacked from day one. |

---

# Tools

Run what is present in the project; never install a tool without asking.

- `semgrep scan --config p/typescript --config p/nodejs --config p/owasp-top-ten`: a safety net with a high miss rate, never proof that the code is safe
- `osv-scanner scan source -r .`
- `pnpm audit --prod`
- `gitleaks` (already runs as a git hook)
- Review the final diff for the **Always** list before reporting.
