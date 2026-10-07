# ADR-0019 — web-ui is a mock; its vocabulary syncs to the server's, and the wire stays for a later step

**Status:** Accepted
**Date:** 2026-10-08
**Deciders:** Amy
**Related:** ADR-0016 (a class is a capability, decisions append), ADR-0017 (class CRUD, write key), ADR-0015 (`AppRole` vs `AppPlatform`), `web-ui/README.md`, `web-ui/src/data/store.ts`, `web-ui/src/types/index.ts`, `contracts/review.schema.json`, `server/app/api/submissions.py`

## Context

The teacher↔student conversation exists twice, in two vocabularies, and only one
of them is real.

**Server (real).** `POST /submissions/{id}/decision` takes `X-Class-Key` and not the
app token (a group must not be able to approve its own work). The decision
vocabulary is a **closed set**: `approved | changes_requested`, plus a free-text
`note` of at most 500 characters. `GET /classes/{id}/activity` derives the feed
from each submission's `history[]` (ADR-0016 decision 5).

**web-ui (mock).** `web-ui/README.md` says it straight: this prototype does not
call the server. It keeps everything in `localStorage` under
`project-review:state:v1` (`web-ui/src/data/store.ts`), and its session is a mock
in `web-ui/src/app/auth.ts` (the value `"1"` reads as teacher, for a session an
older teacher-only build wrote). The mock is the **behavioural specification** the
goal points at: `addComment`, `reply`, `toggleResolved`, `decide`, `resubmit`,
`markNotificationsRead`.

**The drift.** `web-ui/src/types/index.ts` declares
`ReviewEventKind = "approved" | "needsRevision" | "rejected" | "resubmitted"`.
The server has two decision values, not three, and the third one is not a
synonym: `"rejected"` is a state the server **refuses to record**. Two of the
mock's event kinds are, in fact, `DocumentStatus` values — the state of a
document — wearing the name of an event kind. `needsRevision` and `rejected` are
used both ways in the prototype, which is why the drift stayed invisible: the
strings are the same, so nothing failed.

## Options considered

| # | Option | Pros | Cons | Answers which question |
|---|---|---|---|---|
| A | Wire web-ui to the server now, `X-Class-Key` and all | one live system | the browser would need the app token or a class key, and ADR-0017 decision 1 deliberately made the app token shared-and-student-held; a large change on a prototype that has no HTTP layer | scope |
| B | **Keep web-ui a mock; sync its vocabulary and the contract, and write the boundary down** | small; does not break the capability posture; makes the mock honest about what the server accepts | the two systems still do not talk | scope |
| C | Leave the drift, record it as debt | zero work now | the mock keeps rendering `rejected`, a state the server will never produce, and the next reader trusts the wrong vocabulary | vocabulary |
| D | Add `rejected` to the server | the mock needs no change | a decision vocabulary grown to fit a prototype — a string edit where ADR-0016 §Consequences says the next status is an ADR amendment | vocabulary |
| E | Move the decision vocabulary into `contracts/review.schema.json` | one source of truth for both sides, tested in `test_contract.py` | a second place the vocabulary must be kept true — a real cost, accepted | contract |

B, C (resolved as "fix it, not as debt"), and E were chosen. C's question is
answered by rejecting it: the vocabulary is cheap to correct now and expensive to
trust later.

## Decision

1. **web-ui stays a mock.** It does not call the server, and this ADR does not
   change that. `web-ui/README.md` keeps saying so, and ADR-0019 is the record that
the boundary is a decision rather than an unfinished wire.
2. **`ReviewEventKind` is the server's closed set plus the student's own verb.**
   It becomes `"approved" | "changes_requested" | "resubmitted"`. `"needsRevision"`
   and `"rejected"` are **removed** from the event kind. They remain
   `DocumentStatus` values, which is the vocabulary they actually belong to — the
   state of a document, not an event in a conversation. The two concepts stay
   separate types, because a decision names one of two things and a document can
   be in more states than a conversation can contain.
3. **`contracts/review.schema.json` gains a `DecisionStatus` definition and its
   version moves `1.1.0` → `1.2.0`.** The vocabulary lives in one place each side
   can test against, and `x-contract-version` is bumped because the previous
   version did not carry it at all — it is an addition, and the version says so.
4. **The vocabulary is a closed set, in both places.** `approved |
   changes_requested` is what the server records and what the contract declares;
   a third value is an ADR amendment (ADR-0016 §Consequences), not a string edit
   in the mock.
5. **The wire is a later step, and the gates it must open are named here.** Doing
   it for real requires resolving where a browser gets a credential: the app token
   is the shared secret ADR-0017 decision 1 refuses to hand every client, and a
   class `write_key` is per-class and returned exactly once. Neither is a browser
   session. Until that is decided, the mock is the frontend, and its job is to be
   an honest specification of the server it will eventually call.

## Consequences

- **Good:** the mock no longer renders a state the server cannot produce. What a
   reader sees in web-ui is a subset of what the server will accept.
- **Good:** the vocabulary is now checkable by the same suite that checks the
   JSON schema, so the next drift fails a test instead of reading plausibly.
- **Debt, accepted:** `contracts/review.schema.json` is a second home for a
   vocabulary whose first home is `server/app/api/submissions.py`. The two are
   kept true by a test, not by construction; a vocabulary added to one and not the
   other is exactly the drift the `IssueType`/`CheckId` definitions already warn
   about.
- **Debt, accepted:** web-ui and the server do not talk, so a decision made in the
   mock goes nowhere and a decision made on the server never appears in the mock.
   This is honest for a prototype and would be a defect in a product.
- **Not decided here:** when, or whether, web-ui is wired to the server, and what
   credential a browser would hold when that happens. Naming it is step 5; doing it
   is a later ADR.

## Verification

- `test_contract.py` asserts the `DecisionStatus` enum equals the server's
  `DECISION_STATUSES`, so a value added on one side and not the other turns red.
- `test_schema_declares_the_same_contract_version` asserts `x-contract-version`
  matches `CONTRACT_VERSION`, so the version bump cannot be forgotten on one side.
- `web-ui` type-checks with `ReviewEventKind` at three values and no page
  referencing `"needsRevision"` or `"rejected"` as an event kind.
