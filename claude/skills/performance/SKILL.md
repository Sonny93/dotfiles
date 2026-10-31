---
name: performance
description: >
  Performance defaults for new and edited code: fix complexity and I/O first
  (N+1 queries, unpaginated lists, missing indexes, whole-file reads, request
  waterfalls, oversized bundles), measure before micro-optimizing, and avoid
  saturating DB, disk, network or CPU. Use when writing or reviewing queries,
  endpoints, migrations, file handling, caching, React/Inertia pages, bundles
  or SQLite sync code. Triggers: slow, N+1, index, EXPLAIN, pagination, cache,
  bundle size, re-render, memo, lazy, stream, readFileSync, preload,
  database/migrations, Lucid queries, Vite config, FlashList.
---

These are defaults: apply them as far as the project allows, and follow the project when its needs differ (see "Applying These Rules" in `CLAUDE.md`). Builds on **adonis-conventions** (preload relationships, short transactions) and pairs with **concurrency**.

**Proportionality.** Scale to the project. A small PWA, script or prototype gets the **Always** list; a multi-user service, a public API, or anything with real load or data that must not be lost gets everything. Skip an item that does not pay off here and name it once in the final report, never in every message.

---

# Rule

- Measure before micro-optimizing. Fix complexity and I/O first: they dominate everything else.
- State an estimated impact for any optimization ("1 query instead of N+1", "payload 400 KB to 20 KB"). No estimate, no change.
- Readable code beats a 5% gain. Never trade clarity for pixel-level speed.

---

# Always

- No query in a loop (N+1): `preload` relationships or one batched `whereIn`.
- Paginate every list endpoint. Never `.all()` on a table that grows.
- Select only the columns a list needs.
- Aggregates (count, sum, avg, group by) in SQL, never by loading rows and reducing in JS.
- Stream large files, never buffer them (see Disk).
- Route-level code splitting; check the bundle cost before adding a dependency.
- Debounce or throttle requests driven by typing, scrolling or resizing.

```ts
// ❌ 1 + N queries
for (const post of posts) {
  post.author = await User.find(post.authorId)
}

// ✅ 2 queries
const posts = await Post.query().preload('author')
```

---

# When it pays off

## Database

- Index every new `WHERE` / `JOIN` / `ORDER BY` column and every foreign key, in the same migration that introduces it.
- Keyset (cursor) pagination for large or infinite lists; offset is fine for small admin tables.
- `createMany` and bulk upserts over per-row inserts.
- Short transactions; never hold one across a network call.
- Run `EXPLAIN (ANALYZE, BUFFERS)` on every new heavy query. A sequential scan on a big table is the finding.
- Know the pool size: more parallel queries than pool connections just queue. Jobs and workers share the same pool as HTTP.

## Caching

- Only for reads proven hot by measurement.
- Key by user/tenant when data is private: no cross-user leaks.
- Every cache has an explicit TTL and a named invalidation path.
- Static or public responses: `ETag` / `Cache-Control` rather than an app-level cache.

## Network

- Shape payloads with transformers and variants (`summary` vs `detail`): no over-fetching.
- Inertia: use partial reloads (`only`) for filters and refreshes, and deferred props for heavy secondary data so the page renders first.
- Enable compression for text responses.
- Batch API calls; avoid request waterfalls by fetching independent data in parallel (see **concurrency**).

## Disk

- `pipeline(createReadStream(path), destination)` for large files; never `readFileSync` or whole-file buffers in request handlers.
- Delete temp files in `finally`.
- Serve media with HTTP `Range` support.

## CPU and event loop

- No sync crypto, zlib or `JSON.parse`/`stringify` of huge payloads on the request path.
- CPU-heavy work goes to a worker thread or a job (see **concurrency**).

## Frontend (React / Vite)

- Images: sized, modern formats (AVIF/WebP), `loading="lazy"` below the fold.
- Virtualize long lists; on React Native tune `FlashList`/`FlatList` (stable keys, `getItemType`, no inline heavy renders).
- Fix re-render storms by state placement (move state down, split components) before reaching for `memo`. Add `memo`/`useMemo` only after profiling, unless React Compiler already handles it.
- Animate `transform` and `opacity` only; never width, height, top or left.

## Mobile / offline (Expo + SQLite)

- Batch SQLite writes in one transaction.
- Never sync on every keystroke: debounce, then sync in the background.

---

# When NOT to apply

- Code that runs once (migrations, seeds, one-off scripts) on small data.
- Tables bounded by design (a handful of settings rows): no index, no pagination.
- Any optimization without a measured or estimated problem behind it.

---

# Rationalizations to reject

| Rationalization | Reality |
|---|---|
| "It's fast on my machine" | Dev data is tiny. N+1 and missing indexes only show up at production size. |
| "I'll add pagination later" | Clients depend on the response shape; adding it later is a breaking change. |
| "Premature optimization is the root of all evil" | That is about micro-tuning. Queries in loops and unbounded lists are design bugs. |
| "Just wrap it in `useMemo`" | It hides the real cause (state placement) and adds stale-value bugs. Profile first. |
| "A cache will fix it" | A cache over a slow query adds invalidation bugs and still pays the cold miss. Fix the query. |
| "`readFileSync` is simpler" | It blocks the event loop and loads the whole file in RAM. Streaming is three lines. |
| "The ORM handles it" | The ORM runs exactly the queries you describe, including 500 of them. |

---

# Measure

- **Queries per request**: enable Lucid query logging (`debug: true` in the database config, or listen to the `db:query` event) and count them for one request. More than ~10, or any repeated shape, is an N+1.
- **Query plan**: `EXPLAIN (ANALYZE, BUFFERS)` in psql on the real query with realistic row counts.
- **Node CPU**: `node --cpu-prof` (open the `.cpuprofile` in DevTools) or `node --inspect`.
- **Suspect code**: `performance.now()` around it, log the delta, compare before and after.
- **React**: React DevTools Profiler (why did it render, commit duration).
- **Pages**: Lighthouse and Web Vitals (LCP, INP, CLS).
- **Bundle**: `vite build` output sizes; `rollup-plugin-visualizer` if the project has it.
- **CLIs and scripts**: `hyperfine` with warmup runs.

Report the before/after numbers, not just "faster".
