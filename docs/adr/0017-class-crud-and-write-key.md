# ADR-0017 — A class is full CRUD, its write key is its own, and deleting it never deletes work

**Status:** Accepted
**Date:** 2026-09-27
**Deciders:** Amy
**Related:** ADR-0016 (a class is a capability, decisions append, read state is the phone's), ADR-0011 (persistence), ADR-0012 (issue/criterion identity), `server/app/infrastructure/submissions.py`, `server/app/infrastructure/classes.py`, `docs/plans/11-teacher-app-2026-09-27.md` §1, `docs/plans/12-run-everything-remaining-2026-09-27.md` §2 WP2

## Context

ADR-0016 decided what a class *is* and explicitly left two things open: who creates
classes, and whether a class is ever joined or closed. The answer given to the first
is that the teacher does it **in the app**, with the rest of the CRUD surface —
create, rename, delete, and filing submissions in and out. That answer is not
neutral, and this ADR exists because of three consequences that are only visible
once "full CRUD" is written down.

**A shared secret is not ownership.** The app already holds `X-App-Token` (it is
what lets a student file a submission), and it is a *shared* secret, not a per-person
one. So if class rename and delete authenticated on the app token, then **every
client that can file a submission could also delete any teacher's class.** That is a
new capability handed to every existing install, and it would arrive silently.

**Two files that must agree will drift.** A class could hold `submissions: [ids]`
*and* a submission could hold `class_id`. Nothing forces the two to agree after a
partial write, and nothing prevents one submission appearing in two classes.

**The delete button is aimed at other people's work.** The roster is a teacher's own
bookkeeping; the submissions inside it are groups' work, addressable by their own
capability ids and shared with other teachers. Deleting a class must not be able to
delete a group's artifact — or leave rows pointing at a class that no longer exists.

## Options considered

| # | Option | Pros | Cons | Answers which question |
|---|---|---|---|---|
| A | CRUD authenticated on the app token alone | fewest fields, one secret already in the app | any app install can delete any class | who may write |
| B | **Create on the app token; rename/delete on a per-class `write_key` minted with the class** | matches "possession is authority"; a teacher cannot edit a class they were not given | a second secret to store and to lose | who may write |
| C | Per-class signed token with expiry | revocable | needs a signing key and clock policy for a trial | who may write |
| D | Class file owns `submissions[]` as the roster | one read gives the whole list | second source of truth; two classes can claim one submission | membership |
| E | **Submission carries `class_id`; the class file carries only its own fields** | one source of truth; one class per submission for free | listing a class scans submissions | membership |
| F | DELETE cascades to submissions | "delete really deletes" | destroys other people's work through a teacher's button | delete semantics |
| G | **DELETE unfiles submissions and drops the class row** | groups keep their work and their own links | the roster is gone for good; no trash | delete semantics |

B, E, and G were chosen. E over D because the two-source version needs a repair
path that nothing would ever run, and G over F because the delete button is owned by
one teacher and aimed at another person's submission.

## Decision

1. **Full CRUD, and each verb carries its own credential.** `POST /classes` (app
   token) mints the class and returns **both** `class_id` and `write_key`.
   `GET /classes/{class_id}` reads with no token — the id is the credential, as in
   ADR-0016. `PATCH /classes/{class_id}` (rename) and `DELETE /classes/{class_id}`
   require the class's own `write_key` in `X-Class-Key`, **not** the app token.
   The server stores only `sha256(write_key)` and compares with
   `secrets.compare_digest`, so a copy of the store's files does not yield write
   authority.
2. **Membership lives on the submission.** Filing a submission into a class writes
   `class_id` on the submission row; removing it clears that field. The class file
   holds no list. Consequences accepted: listing a class scans submissions (238
   rows on the OTES run — a scan is not the bottleneck, and a wrong index is), and a
   submission is in **at most one** class, which is what a class *is*.
3. **`PATCH` renames, and only renames.** The `class_id` is the credential: a route
   that let a caller change it would invalidate the teacher's link while looking
   like an update. Attempts to send it are rejected by the request model, not
   ignored.
4. **`DELETE` unfiles; it never deletes work.** It clears `class_id` on the class's
   submissions — they stay readable through their own ids and their own share links
   — and removes the class row. **There is no trash and no undo**, and the ADR says
   so rather than the API pretending otherwise. A file on local disk is the whole
   persistence story (ADR-0016 §3), so this is a real, irreversible operation; the
   app must confirm it in the UI, and the UI must not offer a one-tap path.
5. **A class submitted to with an unknown `class_id` is rejected, not filed.**
   `POST /submissions` with a `class_id` that does not exist answers 422 naming the
   field. A group holds its class id from the teacher, so this leaks nothing they
   could not already know, and silently dropping the field would file work into a
   void the teacher can never see.

## Consequences

- **Good:** a teacher cannot destroy another teacher's class, and the app needs no
  new secret beyond one it is handed at creation time and stores like the class id.
- **Good:** no second copy of the roster, so there is no way for a submission to be
  in two classes or in none while appearing in both.
- **Good:** deleting a class is a bookkeeping undo, not data loss — the exact
  failure mode a shared roster makes easy and a per-teacher one makes rare.
- **Debt:** the write key can be lost. A lost write key means a class that can still
  be *read* by everyone holding it but can no longer be renamed or deleted by the
  app; recovery is minting a new class. Stated rather than hidden behind a "recover
  by email" that does not exist here.
- **Debt:** deleting a class is a write-many operation over its submissions. At this
  scale that is a loop over files, and a failure halfway leaves some submissions
  still pointing at a class that is gone. The listing tolerates that by ignoring
  dangling `class_id`s rather than erroring — but the tolerance is deliberate and
  must not become silent data loss.
- **Debt:** `PATCH` renames only. Anything else a teacher might want on a class
  (term, year, description) is an ADR amendment, not a parameter.
- **Not decided here:** inviting people into a class, a class-level membership
  beyond its submissions, and archive/restore. Nothing in WP2–WP5 needs them, and
  each is a new noun rather than a new parameter.

## Verification

- Two clients: one holding class A's write key can rename A, and gets the **same**
  404-shaped failure on B as a stranger does — a write path must not become an
  existence oracle either.
- Renaming does not change `class_id`, and a `PATCH` carrying an id change is
  rejected rather than ignored.
- After `DELETE`, each submission is still readable by its own id, reports no
  `class_id`, and appears in no class listing.
- The read view is tested **through the route**, because a field only the store
  knows is invisible to every reader while every test stays green.

