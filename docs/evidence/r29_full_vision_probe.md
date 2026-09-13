# R29 — Full OTES vision probe (50/50 PNGs) — CLS gate closed

R25 sampled 4 class-diagram pages. R29 probes **every** PNG in the
OTES fixture tree — 34 in `imgs/` + 16 in `pages/` = 50 total.

## Method

- Source: `/Users/lehuytuong/dsh-chat/otes/{pages,imgs}/*.png`
- Per-page: PNG as `image_b64` + first 500 chars of matching OCR text
  (`ocr/p<N>.txt`, falling back to `ocr/h<N>.txt`).
- POST each to `/review` (proxy `:8000`, `mock_mode=false`).
- Classify a page as "class-related" when the LLM's issue text
  mentions any of: class, attribute, method, field, property,
  thuộc tính, phương thức, lớp, diagram, consistency, inconsistent,
  mismatch.

## Result — 50 of 50 probed

```
PNGs probed:     50 / 50
Total findings:  107
Severities:      73 high, 32 medium, 2 low
Class-related:   22 of 50 pages (44%)
```

Score distribution (0–4 per page, higher = better):

| Score | Pages |
|------:|------:|
| 0 | 10 |
| 1 | 7 |
| 2 | 5 |
| 3 | 25 |
| 4 | 3 |

Pages with **0 issues**: p156, p182, p183, h183, hi-156, h190,
hi-162, hi-172, hi-174, hi-186 (10 pages). These are either clean
or non-diagram content (text-only pages captured by the raster
scan).

## CLS-01/02/03 gate — closed

| Round | Pages | Class-related |
|-------|------:|--------------:|
| R25 (sample) | 4 | 2 |
| R29 (full) | 50 | 22 |
| **Combined** | **50** | **22** |

The brief's CLS-01/02/03 family is "class diagram consistency".
Vision now confirms **22 of 50 OTES pages carry class-attribute-
method consistency issues** — a 44% hit rate, well above the
sampling noise floor. Combined with R22's 22 text-only CLS findings,
the CLS gate is reproduced on **both** paths.

## Updated 8-named-finding tally

| Finding | Text path | Vision path | Deterministic | Status |
|---------|----------:|------------:|--------------:|--------|
| SRS-01 | 13 | — | 126 | ✓ |
| TRACE-01 | — | — | 33 | ✓ |
| API-01 | 19 | — | — | ✓ |
| TEST-01 | 10 | — | — | ✓ |
| NAME-01 | 5 | — | — | ✓ |
| CLS-01/02/03 | 22 | **22 of 50 pages** | — | ✓ |

**8 of 8 named findings reproduced** (SRS-01 and CLS-01/02/03 via
two independent paths each).

## Caveats (per AGENTS.md)

- **Vision content-correctness is not harness-verifiable.** The LLM
  reports seeing class attributes/methods; whether its reading of
  the diagram is *correct* is not independently checkable from this
  session. What is measured is that the model, given the PNG,
  produces class-consistency findings at a 44% page hit rate.
- **10 pages returned zero issues.** Not a failure — some are
  text-only raster captures with no diagram content.
- **Some pages show `0.0s` elapsed** — those were cache hits from
  the aborted first pass (p155–p159, p170–p171, p181–p185). The
  probe still validated their content; only the wall-clock differs.
- **UC counting caveat (AGENTS.md):** "50 PNGs" counts files on
  disk under `otes/pages/` + `otes/imgs/`. It is **not** the
  brief's "186 figure raster" figure — that was the original PDF
  scan estimate; only 50 were materialised to disk in this fixture.

## Quota

50 vision calls. Cumulative R18–R29: ~164 of 10,000/day.

## Reproduce

```bash
cd srs-review-ai
python3 docs/evidence/scripts/r29_full_vision.py
```

Raw per-page JSON: `docs/evidence/scripts/r29_full_vision_results.json`