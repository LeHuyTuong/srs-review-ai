# ADR-0016 — A class roster is a capability, a decision is a fact, and "read" is the phone's own business

**Status:** Accepted
**Date:** 2026-09-27
**Deciders:** Amy
**Related:** ADR-0002 (no codegen), ADR-0011 (persistence: SQLite cache, sembast history), ADR-0015 (`AppRole` vs `AppPlatform`), ADR-0006 (capability links), `server/app/infrastructure/submissions.py`, `server/app/infrastructure/classes.py`, `docs/plans/11-teacher-app-2026-09-27.md`, `docs/plans/12-run-everything-remaining-2026-09-27.md` §2 WP1

## Context

The teacher client needs three nouns the server does not have, and each one is a
model question before it is a code question. This ADR settles them because WP2–WP5
of the handoff plan build directly on top, and because the repo's own rule is *ADR
first, UI second*.

**What exists today.** A submission is addressed by a 128-bit id minted with
`secrets.token_urlsafe(16)`; reading one needs nothing but that id, writing needs
the app token (`server/app/infrastructure/submissions.py`). Its `status` is
`submitted` or `reviewed`, and since the time-and-history work it also carries
`createdAt` / `updatedAt` / `history[]`. There is **no class**, **no teacher**, and
**no read state**.

**Why capability is the shape to follow, not a shortcut.** A roster is a list of
submissions a teacher should see. The id pattern for "one person may read this"
already exists twice (`/share/{id}`, `/submissions/{id}`) and is defended by tests.
The alternative — users, passwords, sessions — is a schema, an auth flow, a
recovery story, and a migration, for a capstone trial whose every user already
holds a link.

**Why read state is the sharp end.** A notification badge needs to know what a
given reader has already seen. Storing that server-side requires *naming* the
reader — and capability auth deliberately does not know who anyone is. Server-side
read state would mean minting a second, non-possession credential purely to count
unreads, which re-introduces the identity this design just avoided.

## Options considered

| # | Option | Pros | Cons | Answers which question |
|---|---|---|---|---|
| A | User table + login | revocable, nameable readers | schema + auth + recovery, with no consumer yet | identity |
| B | **Roster keyed by a `class_id` capability** | reuses a defended pattern; a class *is* the teacher's login | no revocation once a link leaks | identity |
| C | Signed, expiring tokens (HMAC) | revocable-ish via expiry | needs a signing key, a TTL policy, and clock discipline — machinery for a claim we have not got | identity |
| D | Teacher-only backend (an `X-Teacher` header) | trivial | a header is guessable; it is a lock with the key taped to the door | identity |
| E | Server-side `read_state` table | unread counts correct across devices | requires naming the reader, so it needs A or C first | read state |
| F | **App-side watermark `(submission_id, revision)`** | no new server concept; correct on the one device that matters | does not follow the teacher to a second phone | read state |
| G | Decisions overwrite `status` in place | simplest history | destroys "what round 1 was told" — the exact loss the non-overwriting revision design exists to prevent | decisions |

B, F, and "append, never overwrite" were chosen. The reasoning: the *expensive to
undo* parts are the ones that create a reader identity (A/C) or a per-reader server
state (E); the *cheap to tighten later* parts are the token widths, the status
vocabulary, and the read-state location.

## Decision

1. **A class is a `class_id` capability of 128 bits, minted by the server**, exactly
   as `SubmissionStore` mints submission ids. A teacher holds a class the way a
   student holds a submission link: possession is the credential. Writing (creating
   a class, filing a submission into it) takes the app token; reading takes nothing.
   **Consequence, written down so nobody mistakes it for a design: there is no
   revocation.** Once a class id has been seen, it cannot be withdrawn; the only
   mitigation available to this design is minting a new class. Anyone describing
   this as access control is describing something this ADR does not claim.
2. **A teacher decision appends; it never overwrites.** `decide()` adds
   `status: approved | changes_requested` plus `decidedAt` and a free-text `note`
   to the current round, and appends one `history` entry. It records no
   `decidedBy`: there is no account to name, and a free-text name field would be
   decoration pretending to be identity. A later round is a **new row** (revision
   N+1), so a decision is a fact about one round and is never rewritten by the next.
3. **The roster is a file, so correctness is conditional on a self-hosted server.**
   `ClassStore` and `SubmissionStore` are one JSON file per row on local disk. That
   is correct on a host with a real disk and **wrong on a serverless platform whose
   filesystem is ephemeral** (Vercel: a cold start starts empty). So: the teacher
   client must point at a self-hosted proxy. If deployment moves to a serverless
   platform, moving these two stores to a database is a **prerequisite**, not a
   follow-up — the same move ADR-0011 already made for the review cache.
4. **"Already read" is the phone's business, not the server's.** The app stores the
   highest `(submission_id, revision)` it has shown and derives unread from that.
   No `read_state` table, and **no per-reader identity on the server** is introduced
   to support one. Accepted consequence: marking things read on one device does not
   follow the teacher to another. For a single-teacher trial this is honest; for a
   shared staff account it is wrong, and the fix is a decision, not a patch.
5. **The activity feed is derived, not stored.** Unread/activity is computed from
   `history[]` on read, newest first. No second timeline to keep in sync, and a
   backfilled legacy row simply appears as old.

## Consequences

- **Good:** the teacher app needs no login screen, because the login *is* the link —
  the same promise the share feature already makes and already tests.
- **Good:** decisions are append-only, so "what was round 1 told?" survives — the
  property `next_revision()` was written to protect.
- **Good:** nothing new is stored that must be migrated when the host changes; the
  stores stay swappable behind the same routes, as `SubmissionStore` already is.
- **Debt, explicitly accepted:** capability ids cannot be revoked. This is
  defensible for a trial and indefensible for real coursework; ADR-0011's SQLite
  precedent means the migration path is known.
- **Debt:** unread state is per-device. Two teachers, or one teacher on two phones,
  will see each other's unread counts disagree — stated in the UI, not hidden.
- **Debt:** the status vocabulary is a closed set written down in one place, so the
  next status someone needs is an ADR amendment, not a string edit.
- **Not decided here:** who creates classes, and whether a class is ever invited,
  joined, or closed. Nothing in WP2–WP5 needs those, and inventing them is exactly
  the "thấy được app chạy" progress the plan warns against.

## Verification

- The store keeps a single read of the clock per write, so a decision cannot produce
  `updatedAt != decidedAt` from a second-boundary crossing; tests assert the
  equality rather than the presence of the fields.
- Tests read **through the route**, not the store: the read view is a whitelist, and
  a field that only the store knows is invisible to every reader while every test
  stays green.
- A malformed class id and a well-formed id that does not exist return the **same**
  response — a 404 that distinguishes them is an oracle for probing the filesystem.
- `docs/adr/README.md` gains this row, and the "next number" moves to 0017, so the
  index stays a fact rather than an intention.

