# ADR 0005 — Run cap 60 sits above the 50/day/person quota, and what carries the load

Status: accepted · 2026-09-12

## Context

The `fix/run-review-cta` merge (2026-09-12) raised the per-run cap from 40 to
60 (`app/lib/core/app_config.dart` `maxRequirementsPerRun`). The server quota
is unchanged: `server/app/config.py` `rate_limit_per_day: int = 50` requests
per person per day. Cache hits do not consume quota.

So a run that selects 60 *distinct, never-reviewed* requirements must issue 60
requests — 10 past the daily quota. The failure mode is a 429 part-way through
a run, not up front: the user clicks "Review 60 units", everything looks
fine, and requests 51+ start failing.

This is the same failure shape audit-2026-09-11 P0-2/P0-4 warned about when
the cap was a hard rejection; the 40-cap ADR reasoning (keep 10 spare requests
per day for re-runs) still describes real behavior — the cap no longer
enforces it.

## Why 60 was kept anyway

- The raise came in with the CTA fix as one user decision; reverting the cap
  to satisfy the quota would undo work that was deliberately merged.
- Runs are rarely worst-case: 60 distinct requirements is the ceiling, and any
  requirement reviewed earlier today is a free cache hit. A 60-unit selection
  on a document reviewed yesterday issues far fewer live requests.
- Mid-run 429 is handled, not silent: the repository's review loop treats
  quota errors as per-unit failure, the run completes with partial results,
  and the failure is visible in findings.

## Decision

Keep the 60 cap. Accept that a worst-case first-run of 60 fresh requirements
will hit the daily quota — the app degrades to partial results with the
reason visible, rather than refusing to start.

## Consequences / follow-ups

- The 10-spare-request property the old cap enforced is now advisory, not
  guaranteed. If mid-run 429s become a real complaint, the cheap fix is a
  pre-flight check: surface remaining daily quota before the run starts and
  warn when `selected > remaining`. (Server would need a quota-remaining
  endpoint; both sides are small.)
- This ADR is the flag the M4 roadmap asked for; no code changes here.
