---
name: concurrency
description: >
  Concurrency, background work and data-integrity defaults: parallelize
  independent async work, bound it, time it out, move slow or CPU-heavy work
  to jobs or workers, and keep writes ACID (transactions, constraints, atomic
  counters, idempotent jobs, outbox). Use when writing async code, Promise
  chains, queue jobs, transactions, ffmpeg or long processes, SSE progress,
  upserts, retries, or Go/Rust async code. Triggers: Promise.all, await in a
  loop, race condition, transaction, job, queue, worker, idempotent, retry,
  timeout, AbortSignal, transmit, ffmpeg, lock, forUpdate, tokio, goroutine.
---

These are defaults: apply them as far as the project allows, and follow the project when its needs differ (see "Applying These Rules" in `CLAUDE.md`). Builds on **adonis-conventions** (wrap multi-step writes in a transaction, jobs use `@inject()`) and pairs with **performance**.

**Proportionality.** Scale to the project. A small PWA, script or prototype gets the **Always** list; a multi-user service, a public API, or anything with real load or data that must not be lost gets everything. Skip an item that does not pay off here and name it once in the final report, never in every message.

---

# Work type to tool

| Work | Tool |
|---|---|
| Independent async I/O | `Promise.all` |
| Partial failure acceptable | `Promise.allSettled` |
| Many items, or a rate-limited API | Bounded concurrency (`p-limit` or fixed-size chunks) |
| CPU-bound > ~50 ms, or blocking | `worker_threads` (pool, e.g. piscina) or a job |
| Slow (> ~1 s), retriable, external, scheduled or fan-out | `@adonisjs/queue` job |
| Long process (ffmpeg) | `spawn` with streams, inside a job |
| Progress shown in the UI | `@adonisjs/transmit` (SSE) |

---

# Always

- No sequential `await` in a loop for independent calls. Start them together.
- Every external call has a timeout and propagates cancellation.
- No unhandled rejections: `allSettled` or a catch per task when partial success is expected.
- Multi-step writes run in one transaction.

```ts
// ❌ waterfall: total time is the sum
const user = await fetchUser(id)
const orders = await fetchOrders(id)

// ✅ total time is the slowest
const [user, orders] = await Promise.all([fetchUser(id), fetchOrders(id)])

const response = await fetch(url, { signal: AbortSignal.timeout(EXTERNAL_CALL_TIMEOUT_MS) })
```

- React effects abort in cleanup, so a stale response never overwrites a fresh one:

```ts
useEffect(() => {
  const controller = new AbortController()
  loadItems(query, controller.signal).then(setItems, ignoreAbort)
  return () => controller.abort()
}, [query])
```

---

# When it pays off

## Jobs

- Idempotent: running twice gives the same result.
- Payload carries IDs, not models; re-read state inside the job.
- Retries with exponential backoff and a maximum; a clear failure path (mark the record failed, notify).
- Unique job keys to dedupe identical dispatches.
- Dispatch after the DB transaction commits, never inside it, or the job may run before the data exists.
- Keep jobs small and composable; fan out instead of one giant loop.

## Data integrity (ACID)

- One transaction per multi-step write; pass `trx` through services (or use Lucid's `useTransaction`) so every step joins it.
- Constraints live in the database (NOT NULL, UNIQUE, FK, CHECK), not only in app code.
- Check-then-insert races: unique constraint plus upsert (`ON CONFLICT`); Lucid's `updateOrCreate` alone does not remove the race without that constraint.
- Counters: atomic SQL increments (Lucid's `increment`), never read-modify-write.
- Contended rows: pessimistic `forUpdate()` held briefly, or optimistic locking with a version column and retry on mismatch.
- Never call an external service while holding a transaction or lock.
- When a DB write and a side effect (email, webhook, queue message) must both happen: outbox pattern. Write the event row in the same transaction, a job delivers it.

## Coalescing

- Single-flight for concurrent identical triggers (cache stampede, sync): share one in-flight promise per key.
- Debounce user-driven triggers.

## Other languages

- Go: `errgroup` with `context`, bounded with `SetLimit`.
- Rust (tokio): `JoinSet` plus `Semaphore` for bounded fan-out, `tokio::time::timeout` on external calls, `spawn_blocking` for CPU.

---

# When NOT to apply

- Dependent steps: if B needs A's output, keep them sequential.
- Unbounded `Promise.all` over user-sized input: bound it instead.
- Jobs for work under ~100 ms that the user is waiting on anyway.
- Parallelism that only moves the bottleneck onto a saturated DB pool or a rate-limited API.
- Locks or version columns on rows nobody contends for.

---

# Rationalizations to reject

| Rationalization | Reality |
|---|---|
| "`await` in a loop is simpler" | Fine when steps depend on each other. For independent calls it multiplies latency by N. |
| "`Promise.all` on all 10,000 items" | It opens 10,000 sockets or queries at once. Bound it. |
| "The check runs right before the insert" | Two requests pass the check together. Only a unique constraint closes the race. |
| "Read, add one, save" | Concurrent requests lose updates. Use an atomic increment. |
| "Dispatching inside the transaction is fine" | The job can start before commit and miss the data, or run for a rolled-back write. |
| "The job won't run twice" | Retries, worker crashes and duplicate dispatch make it run twice. Design for it. |
| "The API is reliable, no timeout needed" | One hung call then holds a connection, a lock or a worker forever. |
| "Retry immediately until it works" | It hammers a struggling service. Back off exponentially, with a cap. |

---

# Measure

- Log the duration of each step (`performance.now()` deltas) before changing anything.
- Compare wall time sequential vs parallel on realistic input; keep the parallel version only if it wins.
- Watch queue depth, retry counts and failed jobs after shipping.
- Postgres lock waits: query `pg_stat_activity` (`wait_event_type = 'Lock'`) while reproducing the slow case.
- Check pool saturation: connections in use vs the configured maximum under load.
- Race conditions: reproduce with two concurrent requests in a test before fixing, and keep that test.
