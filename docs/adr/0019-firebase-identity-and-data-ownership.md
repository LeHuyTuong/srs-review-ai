# ADR-0019 — The mobile app's identity is a Firebase Auth UID, and its data belongs to that UID

**Status:** Accepted (scope: `mobile/` for Lab 3 only; does not change `desktop/` or `server/`)
**Date:** 2026-11-04
**Deciders:** Amy
**Related:** ADR-0001 (D6: no LLM key in the app), ADR-0013 (View never calls an SDK), ADR-0016 (a class is a capability; decisions append), ADR-0017 (class write key; deleting a class never deletes work), `mobile/docs/mobile-firebase-contracts.md` (DEP-01..12), `mobile/docs/firebase-data-model.md`, `docs/lab3-audit.md` §4

## Context

ADR-0016 and ADR-0017 built access control on **possession**: a class id is a 128-bit
capability, a class `write_key` (stored as `sha256`) authorises rename/delete, and an
`X-Class-Key` header authorises a teacher decision. There is no user table and no
account. Both ADRs say so deliberately, and ADR-0016 §3 adds that the file store is only
correct when self-hosted.

The Lab 3 brief (PRM393) contradicts that model in three places:

- data must be created, read, updated and deleted for real and **belong to the signed-in
  user**, enforced by Firestore Security Rules that are not test mode;
- authentication is Firebase Authentication with Google Sign-In;
- custom backend servers are out of scope.

So the Python server cannot ship with the mobile submission, and "whoever holds the key
may act" has no equivalent in Security Rules, which see an identity and a document, not a
header secret.

## Decision

1. **Identity is `request.auth.uid`.** Every document the mobile app writes carries
   `ownerUid`; rules allow read/write only when `ownerUid == request.auth.uid`.
   `X-App-Token`, `class_id`-as-capability and `write_key` are not carried over.
2. **`write_key` → `ownerUid`.** Rename/delete of a class is "I own it", checked by rules.
   Nothing is shareable by link in this edition (`/share` is dropped), so the
   "irrevocable capability" problem in ADR-0016 does not arise; it is replaced by an
   ordinary revocable ownership check.
3. **Decisions stay append-only** (ADR-0016 holds on this point). `reviewDecisions`,
   `auditEvents` and `documentVersions` are create-only in rules; a second decision on a
   version is a new document keyed by its `commandId`, so a retry cannot create two.
4. **Decision vocabulary is the mobile one:** `approved | needsRevision | notAccepted`
   (the domain layer and its tests already implement it). The server's
   `approved | changes_requested` is **not** adopted here. This is a recorded divergence,
   not an oversight; reconcile it if the server and mobile ever share a store.
5. **Time is server time.** `createdAt`/`updatedAt` are `serverTimestamp()` and rules
   require `== request.time`, the equivalent of the server stamping the clock once per
   write (plan 12 WP3).
6. **Deleting a class never deletes work** (ADR-0017 holds): the batch detaches
   `classId` from dependants and leaves their documents. A Firestore batch is capped at
   500 operations; a class with more dependants than that is archived, not deleted.
7. **Not carried over, and why:**
   - LLM review, `/ask`, `/diagram`: there is no Firebase-only equivalent and no key may
     live in the app (ADR-0001 D6). The mobile app records a clearly labelled **simulated**
     AI result. Firebase AI Logic is the Final-assignment route, untested on Spark.
   - Quote verification, 50/day quota, provider pacing, PDF parsing, the SQLite cache:
     all server mechanisms for an LLM path this edition does not have. Rules cannot count
     requests and the quota is not enforced here.
   - Rubric weight sum: rules check shape, not that the weights add to 1.0.

## Consequences

- A teacher can no longer hand a colleague a link that lets them read or decide. If that
  returns (Final: role/assignment scope), `ownerUid`-only rules must be widened and this
  ADR superseded by 0020; collection names do not change.
- The mobile data and the server's `.classes/.submissions` stores are **separate**. Nothing
  migrates between them; the desktop app keeps using the Python server unchanged.
- Rules, not the client, are the security boundary. Every UI guard that exists today
  (session scope, role literal `supervisor`) is a convenience, not a control.
- `users/{uid}.role` is **not** an authorisation input in Lab 3. A user may create their
  own profile, so the field cannot be trusted until an Admin-set role exists (DEP-01).
