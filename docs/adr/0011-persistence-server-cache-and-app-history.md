# ADR 0011 — Persistence: server cache in SQLite, app history in an embedded database

Status: accepted · 2026-09-22

## Context

Both halves of the app kept their state somewhere that could not survive much.

**The proxy** held every review result in an `LruCache` (`server/app/main.py`).
That was a documented decision ("server is a stateless proxy, state is in memory:
`LruCache` + `RateLimiter`" — `docs/arch-server-notes.md`), and it cost real
money on 2026-09-22: the OTES run paid for 238 reviewed units, and restarting
uvicorn to pick up a code change threw all of them away. Re-running the same
document would have paid for them a second time, against a free tier whose
per-minute limit was already the bottleneck (ADR 0010).

**The app** held the review history in `shared_preferences` — one JSON value per
replica, two replicas, rewritten in full on every save. Measured on the real
history: 3 sessions / 1.08 MB, so a save re-encoded and wrote 1.1 MB twice, and a
full 30-session history of OTES-sized runs would approach ~22 MB against
`localStorage`'s ~5 MB ceiling on the web build. The mirroring and self-healing
added on 2026-09-22 made that safe but not cheap.

## Decision

Persist both, in the smallest engine that fits each side.

**Server: SQLite, via the standard library.** `server/app/store.py` implements the
same `get/put/clear/__len__` surface the `LruCache` had, storing the exact JSON the
endpoint already returns, keyed by the same content hash. Because the key already
contains `prompt_version`, rubric version, model selection and every other input
that can change a result, upgrading the prompt or rubric invalidates old rows by
itself — no data migration is needed for that. The file is versioned
(`cache_meta.schema_version`); a file written by a NEWER schema is refused and left
alone. The row cap (`cache_max_entries`, default 10 000) evicts the coldest rows,
reading refreshes recency, and a payload that no longer decodes is dropped and
treated as a miss.

Three properties are non-negotiable, because a cache is not worth an outage:

* **never break a review** — an unusable path (read-only serverless filesystem,
  full disk, corrupt file) degrades to the old in-memory behaviour and logs once;
* **never lie about it** — `/health` reports `cache.degraded`, so a silently
  in-memory cache is visible instead of looking healthy;
* **never touch a stranger's data** — the test suite points `SRS_CACHE_DIR` at a
  throwaway directory (see `server/tests/conftest.py`), because the module-level
  cache is opened at import time and the suite calls `clear()`.

**App: `sembast` — a pure-Dart single-file database — behind the existing
`SessionStore` interface.** One record per session keyed by its id, so saving one
session writes one small record instead of a 1.1 MB list; the snapshot lives in
its own record; the 30-session cap deletes whole records instead of truncating a
list on its way out. `main()` opens it once (`openSessionStore`) and overrides
`sessionStoreProvider`, so nothing above the store changed.

Migration is additive and reversible: the old `shared_preferences` rows are
imported once (flag in the database, written only after a successful import), and
they are **read, never deleted** — a device that downgrades to an older build
still finds its history where it always was. If no database can be opened
(`path_provider` has no implementation in a plain `flutter test`, IndexedDB is
blocked, the support directory is unwritable) the app keeps the
`shared_preferences` store and says so in the log.

## Alternatives rejected

* **Keep everything in memory.** Directly measured cost: a restart discards a
  paid-for run. The same document then costs its 240-odd provider calls again.
* **PostgreSQL/Redis for the proxy.** New infrastructure for data that is a local
  cache of one key, in a design whose entire selling point is that the app talks
  to one small proxy. SQLite is already in the Python standard library.
* **`sqflite` / `sqflite_common_ffi` in the app.** Every SQLite route into
  Flutter needs native code: a library per platform, wasm assets for web, and
  `libsqlite3` on the CI runner. This repo has already paid for that lesson —
  `pdfx`'s native plugin is unusable in every host test runner (three wasted
  debug rounds, documented in AGENTS.md) — and CI runs `flutter test` on a bare
  ubuntu image. A pure-Dart database is exercised by the suite, on the host, with
  zero setup.
* **`drift` / `isar`.** Codegen and native binaries respectively; ADR 0002 says
  no codegen, and the app already hand-writes its small wire models.

## Consequences

- A restart no longer costs a run. Verified end-to-end: with the database on
  disk, a second process served the same two units with `cached: true` and
  **zero** upstream calls, and `/health` reported `review_entries: 2`.
- History writes are per-record; the 30-session cap now deletes records rather
  than rewriting a list, so a session can no longer disappear as a side effect of
  a write that failed halfway.
- The proxy's cache is content-addressed and therefore shared between users: two
  people reviewing the same requirement text with the same settings share an
  entry. That was already true of the in-memory cache; it now persists. Fine for
  a capstone reviewer, and a real consideration the day the proxy serves
  unrelated institutions.
- The daily rate limit is still in memory, so restarting the proxy resets a
  user's quota. Unchanged here; persisting it means deciding a window policy
  (rolling vs. calendar day), which nobody has needed yet.
- `sembast` returns a `Future` per operation like any database, and it is
  per-origin on the web exactly like `localStorage` — a browser still loses the
  history if the dev server changes port, but no longer because the value did not
  fit.
