# ADR 0012 — A finding names two things: its criterion and its defect class

Status: accepted · 2026-09-25

## Context

The AI checklist became editable data on 2026-09-25 (commit `e856aab`): rows in
`criteria.json`, CRUD through `/criteria`, and the prompt renders whatever rows
are enabled. That made a new kind of value possible for the first time — a
criterion id that only exists in *one user's* marking sheet.

It could not come back. The criteria block ended with:

> When a criterion is violated, name its id in the issue `type` so the row can
> be traced back to this list.

and `type` is `$defs/IssueType`, a **closed enum of six ISO defect names** — also
pinned into `LLM_REVIEW_SCHEMA`, where Gemini enforces `enum` on the model. So
the instruction asked for the one string the response schema could not carry. The
user's own criterion was exactly the value that could never be returned, and
"trace this finding back to the criterion I wrote" was unachievable by
construction.

Two failure modes lived in the same three lines of `verify.py`:

```python
Issue(
    type=raw["type"],            # ValidationError when it is not an enum member
    severity=raw["severity"],    # ... same
    suggestion=raw["suggestion"] # KeyError when the model omits it
)
```

Neither is caught by the single-unit path. A finding with a **perfectly verified
quote** therefore produced:

- `/review`: an uncaught `ValidationError` → **500**, one unit lost, a traceback
  in the log that reads like a proxy bug;
- `/review/batch`: `ValidationError` caught as "entry unusable" → the unit is
  retried, split, and finally reported `failed` — paid work discarded over a
  label.

The app's stance is the opposite and deliberately so: `IssueType.fromWire`
throws `ContractException`, and `contract_test.dart` pins that ("an unknown enum
value is rejected instead of silently degrading"). Strictness is a tripwire
worth keeping. It just cannot be the *server's* posture, because the server sits
between a model that guesses and a user who paid for the answer.

## Decision

**Separate the two dimensions, keep the enum closed, and coerce labels instead of
validating them. The contract version stays `1.0.0`.**

- `Issue.criterion_id` (optional, additive) carries the criterion row the finding
  answers — the prompt now asks for the id *there*, and the LLM response schema
  declares the field. `type` keeps its six ISO members and gains one:
  `other`.
- `verify.review_issues` never raises over a label. An unrecognised `type`
  becomes `IssueType.other` **and** its raw string is kept as the criterion
  reference; an explicit `criterion_id` outranks it. An invented `severity`
  becomes `medium` — the same middle the prompt names as a criterion's default.
  A missing `suggestion` becomes `NO_SUGGESTION`.
- The **quote gate is unchanged**: an unverifiable quote is still dropped. The
  tolerance is about labels, never evidence.
- `IssueType.other` is the honest value for "no ISO class fits". Guessing a
  plausible class would put a wrong badge on a real finding, and the app would
  reject an undeclared value outright — so the fallback is also what keeps the
  wire inside the closed vocabulary.
- The single-unit path gains the `ValidationError → 502` guard the batch path has
  carried since it was written. The labels are coerced now, so it is the belt to
  that braces: a future unusable field must answer a readable 502, not a 500.
- `prompt_version` p3 → **p4**. The instruction that names `criterion_id` is
  prompt *template* text, not a criterion row, so `criteria_fingerprint` does not
  cover it; without the bump a cached p3 result — produced by a prompt that could
  not name a criterion at all — would keep answering the new question.
- Both offline providers (the proxy's `MockProvider`, the app's `MockReviewApi`)
  cite the seed criterion their rule implements, and the proxy's reads the
  enabled ids back out of the prompt it was handed, so disabling `unambiguous`
  stops it being named there too.

## Consequences

- **`criterion_id` is a lookup key, never prose.** It stays untranslated in all
  four report formats and travels next to the other tokens in the JSON twin;
  only the word around it (`criterion:` / `tiêu chí:`) follows the report
  language.
- The contract is extended, not broken: an optional property plus one enum
  member. `x-contract-version` stays `1.0.0` because a reader that ignores
  unknown keys is unaffected, and because a version bump would break the
  deployed-proxy skew the repo already lives with
  (`ReviewResult.fromJson` rejects a mismatched version outright — see ADR 0010's
  batching fallback for the same reasoning). An *older app* meeting
  `type: "other"` can only do what it does today: fail that one unit. It cannot
  do worse.
- The Dart enum and the schema enum are now compared in `test/contract_test.dart`
  (they never were): a member added on one side only used to be invisible until
  it reached the field.
- Two vocabularies coexist on purpose and must not be merged: a **criterion**
  (`nfr_quantified`, user-editable) and a **CheckId** (`nfr_unquantified`,
  rule-based and offline) are different things, and a deterministic finding never
  carries a `criterion_id`.
- Still open: five seed criteria have `scope: "document"` and `_review_config()`
  renders only `prompt_block("unit")`, so those rows reach no prompt at all. That
  is a separate change — it needs a document-level call, not a field on an issue.
