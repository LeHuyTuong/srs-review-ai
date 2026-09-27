# ADR-0015 — `AppRole` is a separate concern from `AppPlatform`, and the bottom-sheet ban is scoped, not lifted

**Status:** Accepted
**Date:** 2026-09-26
**Deciders:** Amy
**Related:** ADR-0006 (desktop edition), ADR-0007 (M3 thresholds), ADR-0014 (full-screen surfaces), `app/lib/core/platform/app_platform.dart`, `app/lib/core/layout/app_breakpoint.dart`, `tools/check_guardrails.py` (rule 8), `docs/plans/9-consistency-first-2026-09-26.md` §6

## Context

The plan to add a teacher client on mobile hit two walls that cannot be decided by
inspection, because both look like implementation detail and are not.

**Wall 1 — there is no "who", only "where".** `AppPlatform` answers one
question: *which device am I on?* It returns `isDesktop`, `isWeb`,
`formFactor` and `usesCommandKey` from `kIsWeb` + `defaultTargetPlatform`, with
`dart:io` banned (ADR-0006 §1). The proposed teacher shell needs a second
question — *which role is this build?* — and the two have different lifetimes:
`formFactor` is a runtime property that changes when a window is dragged, while a
role is a property of the build and of the signed-in session. Folding role into
`AppPlatform` makes every layout call site re-derive identity, and makes a
role switch drag the platform with it.

**Wall 2 — the phone cannot have a bottom sheet.** ADR-0014 banned the entire
bottom-sheet family from `app/lib` and `check_guardrails.py` rule 8 enforces it
line-by-line, with a test (`qa_p1_adversarial_test.dart:547`) asserting the
absence. That decision is right for desktop: sheet height is negotiable, which
is how long content ends up under a lid. But on a phone the bottom sheet is the
Material norm, and a full-screen surface for every choice is measurably worse:
`docs/evidence/surface-audit-2026-09-26.md` measured 18/18 surfaces filling the
window, a decision taken while every target was a desktop window or a web
viewport.

So ADR-0014's ban is right and incomplete: it is a correct rule for the surfaces
it was written about, and the teacher client would either violate the spirit of it
or be visibly unidiomatic on a phone.

## Options considered

| Option | Pros | Cons | Đáp yêu cầu nào |
|---|---|---|---|
| A. Put `AppRole` in `AppPlatform` | one file to read | identity and device share a lifetime; a role change drags `isDesktop` with it; layout call sites grow a second `if` | — |
| B. `AppRole` in `core/platform`, `AppPlatform` unchanged | minimal diff | same file still answers two unrelated questions | — |
| C. **defer — do not build the teacher shell yet** | no risk, no debt | blocks P3 entirely; the plan's core move is the role split | — |
| D. **separate `core/role/`, and scope rule 8 to non-phone** | identity has its own home and its own tests; the ban survives where it was earned | a guardrail gets a condition it did not have | role split; phone idiom |

D was chosen over B because the separation is the part that is expensive to undo,
and the guardrail scope is the part that is cheap to tighten later.

## Decision

1. **`AppRole { student, teacher }` lives in its own module, not in
   `AppPlatform`.** `core/platform/app_platform.dart` keeps answering only "where
   am I"; a new role concept sits at the same layer but is read through a
   separate provider, and no layout code branches on it directly — it selects a
   shell, and the shell is what branches.
2. **Rule 8 keeps its ban; the ban gains an explicit phone exemption for
   *presentation* surfaces only.** `showFullScreenSurface` remains the only
   entrance for every dialog in `app/lib` on desktop, web and tablet. A phone may
   present a *choice list* as a bottom sheet, through one named entrance
   (`showPhoneChoiceSheet`), because its height is content-driven and it is
   dismissed by tapping outside. Rule 8 is amended, not disabled, and the
   amendment is stated in the rule's own message so a future reader sees it.

## Consequences

- **Good:** a role switch cannot perturb breakpoints; the existing 841 app tests
  keep passing unchanged, because `AppPlatform`'s contract is untouched.
- **Good:** the ban is now stated as "full-screen everywhere, sheets on phones",
  which is a rule a reviewer can check, rather than a ban that a future phone
  feature has to quietly route around.
- **Debt, explicitly accepted:** one new concept with no consumer yet. A
  `core/role/` module that nothing reads is a promise, not a feature — it must not
  be counted as P3 progress.
- **Debt:** rule 8's message grows, and a conditional rule is easier to misread
  than an absolute one. The exemption is therefore restricted to one named
  function so the scan can assert that no *other* sheet API appears.
- **Not decided here:** what makes the role change at runtime. That needs real
  identity, which is P4, and inventing a fake picker now would be the "thấy được
  app chạy" progress the plan explicitly warns against.

## Verification

- `app/test/` stays green with the role module added but unused — that is the
  proof the split changed nothing.
- A new test asserts `AppPlatform`'s public surface is byte-identical to
  ADR-0006's, so a later "just add a getter" is caught.
- Guardrail rule 8 continues to pass, with a probe file that uses a *different*
  sheet API still failing — the exemption must not become a blanket allow.
