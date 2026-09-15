# ADR 0009 — Rubric v3: reweight the four quality criteria, drop the use-case ceiling

**Status:** Accepted · 2026-09-15
**Supersedes:** the weight table and `uc_count.max` in rubric v2 (introduced in ADR-0001's scope, never given an ADR of its own)
**Driver:** rulebook decisions Q1 and Q6, signed by the document owner 2026-09-15 (`review-rules/RULEBOOK.md` §9)

## Context

`server/app/rubric.json` is the single piece of grading configuration both the
server prompt and the Flutter client read. Two of its numbers were set in the
first week from the syllabus text alone, before any real document had been
graded. Four documents have now been graded against `review-rules/` — OTES SRS
and SDS, HisWise SDS, CarbonX SRS — and both numbers turned out to be wrong in
a way that measurably hid defects.

**The weights.** v2 used `clear .30 / testable .30 / complete .25 /
consistent .15`. On OTES, **44 of 44** functional and non-functional
requirements had no writable test case — not a minority failure, a total one.
"Testable" is also load-bearing in a way the other three are not: a tester who
cannot tell when a requirement is satisfied gets no value from that requirement
being clear, complete or consistent. Weighting it the same as "clear" said the
opposite.

**The use-case ceiling.** v2 fired a finding when the count fell outside
`20–25`. OTES has 63 use cases, so it failed the check. But 63 is not the
defect — **45 of those 63 hold a single transaction**, which is the F9
(use-case size) criterion, and F9's finding was drowned out by a count warning
the team could not act on without deleting work. Count and size are different
questions; one threshold covering both hid the one that mattered. The syllabus
itself sets a floor ("≥ 20 completed use cases to defend"), not a band — the
upper number was our inference.

## Decision

1. **Reweight to `clear .25 / testable .40 / complete .20 / consistent .15`.**
   Still summing to 1.0, still enforced by `test_rubric_json_is_valid_and_weights_sum_to_one`.
2. **Set `uc_count.max` to `null`** rather than deleting the key. `RubricConfig.ucCountMax`
   becomes `int?`. Keeping the key present and explicitly null means an older
   client that casts it to non-nullable `int` **fails loudly** instead of
   silently falling back to a hard-coded 25 — a silent wrong ceiling is worse
   than a crash we can see.
3. **A count above any recommended maximum is no longer a failed check.** It
   still produces an informational finding pointing at F9, so the signal is not
   lost, but `passed` is true.
4. **Bump `version` v2 → v3.** Mandatory, not cosmetic: the server's review
   cache key hashes the rubric version (`main.py _review_cache_keys`). Editing
   weights without bumping would serve every verdict computed under the old
   weights as if it had been computed under the new ones.

## Consequences

- Every cached verdict is invalidated on deploy. Intended.
- Three test pins move together with the config, by design — they are
  tripwires, and each must be red before the change and green after:
  `test_rubric_pins.py` (version + weight dict), `test_api.py`
  (`/health` rubric_version), `test_contract.py` (`uc_count.max is None`).
- `app/test/syllabus_checks_test.dart` loses its "warns above 25" case and
  gains "63 use cases pass" — the OTES case, stated as a regression test so the
  ceiling cannot come back by accident.
- `prompt.py` needs no edit: it generates the rubric text from `rubric.json`
  precisely so the prompt cannot drift from the configured weights.
- **Verified 2026-09-15.** `server/.venv/bin/python -m pytest tests/` → **90
  passed, 1 skipped**; `flutter test test/quality_checks_test.dart` → **20
  passed**. The three server tripwires went red on the old config and green on
  the new one, which is what they exist for.
- The change was authored with no working shell (virtiofs mount failure, whole
  session) and reviewed by reading instead of compiling. That caught the one
  defect that mattered — `idFormat` grading our own normalisation, see below —
  and missed a stray `});` that broke the test file's brace balance. Reading
  substitutes for a logic review; it does not substitute for a compiler.

## Alternatives considered

- **Wait for the supervisor's real marking sheet.** Rejected for now: FPTU does
  not publish the per-item criteria, and `provenance` in `rubric.json` already
  says these are a proposal. When the real sheet appears it replaces the
  numbers with no code change — that is why the rubric is data.
- **Keep `max: 25` but stop firing on it.** Rejected: a threshold nobody
  enforces is a lie sitting in the config waiting for someone to re-enable it.
- **Delete the `max` key entirely.** Rejected in favour of explicit `null`, per
  decision 2 — a missing key and a deliberately-absent bound look identical to
  a reader, and only one of them is intentional.

## Landed alongside, in the same change set

`CheckId.nfrUnquantified` — rulebook hard rule 6, an NFR with no figure AND no
measurement condition. Not wired into `floorCriteria`: hard rule 6 is measured
by the NFR score component, and double-counting it in the floor is the exact
defect `scoring.md` §1b exists to prevent.

`CheckId.idFormat` was written and then **removed before shipping**. A static
review found that `requirement_splitter._canonicalId` rewrites every parsed id
to `PREFIX-NN` before any check sees it, so the check would have been grading
our own normalisation: every FR and NFR from a real document would fail, and
the malformed ids the rule targets (`UC01`, `NFR01`) would already have been
silently repaired. A check that is wrong every time is worse than a missing
one. It needs the splitter to carry the raw source id first.

## Note on scope

This ADR covers the **app's** per-requirement 0–10 scoring. It does not cover
the artifact-level 0–10 scale in `review-rules/references/scoring.md`, which is
a different unit and versioned separately (`RULEBOOK.md` §10). The two must not
be added together — see `docs/evidence/rubric-vs-skills-map.md` §D.
