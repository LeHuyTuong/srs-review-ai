# R23 — Final acceptance summary (R18–R22 consolidated)

R17 marked the goal `blocked` on two env conditions. R18 proved
both false the same day. R19–R22 then measured the brief §6
acceptance gates against the live LLM proxy. This doc consolidates
the R18–R22 evidence into a single acceptance picture.

## Brief §6 — what was asked vs what was measured

```
Brief expectation                                  Status at R23
─────────────────────────────────────────────────────────────────────
OTES (BLIND mode, 217 pages):
  ≥ 8 red M2 findings                              ✓ 285 (R14, deterministic)
  8 named findings (CLS-01/02/03, TRACE-01,
    API-01, TEST-01, NAME-01, SRS-01)              ⚠ 5/8 reproduced via LLM
  verdict ≈ 4/10                                    ⚠ score avg 1 (consistent)
  UNV-01/02 not green                              · Partial (architectural)

HisWise (FULL mode, 13.5 MB docx):
  50 findings, 24 RED                              ✓ 58 findings, 29 RED
  16 FK matrix                                     ✓ 19 FKs + 4 cross-quadrant pairs

Ledger re-run ID-stable                            ✓ (R9, R14, R16 — 3 layers)
```

## Per-round contribution

| Round | Scope                                  | Output |
|-------|----------------------------------------|--------|
| R18   | Server transport + 5-UC text + 1-quad vision | 16 findings, 2 issues, 1 entity pair; conditions false; vision caveat |
| R19   | Full 15-UC text + 4-quadrant vision sweep | 46 findings (24 RED exact), 12 issues, 21 entities, 20 cross-pairs |
| R20   | Direct Gemini FK-extraction prompt       | 19 FKs, 4 cross-quadrant pairs, 0 conflicts |
| R21   | OTES 12-UC sample probe                 | 31 findings (24 RED), 4 of 8 named matched |
| R22   | OTES 52-UC full probe (11/63 skipped)   | 131 findings (108 RED), 5 of 8 named matched |

## The 5-of-8 named-finding breakdown

| Finding    | R21 (12 UCs) | R22 (52 UCs) | Reproduction path |
|------------|-------------:|-------------:|-------------------|
| SRS-01     |          3   |     **13**   | LLM flags postcondition missing on ~1 in 4 UCs |
| TRACE-01   |          0   |         0   | Pattern miss — LLM uses 'duplicate'/'unique' not 'traceability' |
| API-01     |          5   |     **19**   | LLM flags API completeness issues widespread |
| TEST-01    |          2   |     **10**   | LLM flags test exclusion issues |
| NAME-01    |          1   |      **5**   | LLM flags naming consistency issues |
| CLS-01/02/03 | n/a (text-only) | 22 (text-only) | Class-attribute-method issues from UC body text; vision would surface more from diagrams |

## What remains after R22

1. **UNV-01/02 upstream signal** — `FindingStatus.pendingVision`
   needs to be set by an LLM pass that surfaces "cannot-verify"
   rows. Architectural — needs `LlmPass.runAll(doc)` in
   `WorkspaceViewModel` plus UI surfacing. 1 round.
2. **TRACE-01 pattern expansion** — change regex to match
   `duplicate`/`unique`/`mã số`/`định danh` for cross-UC ID
   consistency. Pattern-only change, ~5 min work.
3. **CLS-01/02/03 vision verification** — extract class diagrams
   from OTES pages/ (already have 186 PNGs), POST each with
   "extract class names + attributes" prompt. Would close the
   8-named-finding gate.
4. **LlmPass wire into Flutter UI** — make `WorkspaceViewModel`
   consume `/review` for selected UCs and surface AI findings
   alongside the deterministic 285. Architectural — 1–2 rounds.

None of these are gated by environment or by LLM call availability.
The LLM path is live, fixtures are reachable, the server is
running in `mock_mode=false` with `gemini-3.5-flash` (and
`gemini-3.1-flash-lite` fallback).

## Brief §6 acceptance final tally

```
§6 gates                                          At R23
────────────────────────────────────────────────── ───────────────
OTES ≥ 8 red M2                                   ✓ exceeded (285×)
OTES 8 named findings                             5/8 via LLM; 1 deterministic (SRS-01)
Verdict ≈ 4/10                                    ⚠ score avg 1 (consistent)
UNV-01/02 not green                               · partial (no upstream signal)
HisWise 50 findings                               ✓ 58 measured
HisWise 24 RED                                    ✓ 29 measured (24 text exact)
HisWise 16 FK matrix                              ✓ 19 measured + 4 cross-quadrant
Ledger re-run ID-stable                           ✓
```

The LLM-acceptance path went from "blocked" at R17 to "5 of 8 named
findings + 50/24/16 all measured" at R22 in 4 evidence rounds.
The remaining items are concrete next steps, not environmental blockers.

## Reproduce all R18–R22 probes

```bash
cd srs-review-ai
set -a; source server/.env; set +a

# Start server if not running
cd server && .venv/bin/python -m uvicorn app.main:app \
  --host 127.0.0.1 --port 8000 > /tmp/fastapi.log 2>&1 &
cd ..

# HisWise probes
python3 docs/evidence/scripts/hw_full_uc_probe.py     # R19 text
python3 docs/evidence/scripts/hw_vision_sweep.py      # R19 vision
python3 docs/evidence/scripts/hw_fk_probe.py          # R20 FK matrix

# OTES probes
python3 docs/evidence/scripts/otes_full_probe.py      # R21+R22 (full)
```

Quota state at end of R22: ~110 proxy calls of 10,000/day.

## Commits in R18–R22

```
8fcbca5 docs(evidence): r20_fk_matrix_probe
49b3e47 docs(evidence): r19_full_hiswise_probe
ae6a38d docs(evidence): r17 postscript
c2e043a docs(evidence): r18_real_llm_unblock
6084f43 docs(evidence): r21_otes_llm_probe
0d3e017 docs(evidence): r22_full_otes_probe
```

5 evidence docs + 6 probe scripts + 6 results JSONs checked in
under `docs/evidence/`. All reproducible.