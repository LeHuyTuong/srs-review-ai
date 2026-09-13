# R18 — Real LLM unblock evidence

Round 17 was marked `blocked` on two conditions:

1. `srs-review-ai/AGENTS.md` stated "Model không đọc được ảnh trong
   phiên harness này" → vision LLM unverifiable from this session.
2. HisWise fixture not reachable from any probed path → FULL-mode
   acceptance test unrunnable.

The user responded with env-key set + HisWise fixture pointed to the
actual disk path. Both conditions were probed and **confirmed false**:

- `server/.env` contains `GEMINI_API_KEY=AQ.Ab8RN...` (53 chars,
  live) and `GEMINI_MODEL=gemini-3.5-flash`.
- HisWise fixture exists at `/Users/lehuytuong/dsh-chat/hiswise/`
  with `HisWise_SDS Document.docx` (13.5 MB), 4 ERD quadrants
  (`erd-bl/br/tl/tr.png`), pre-extracted text (`sds-full.txt`,
  200 lines) + outline (`outline.txt`).
- Direct Gemini API probe (curl) returned HTTP 200 with a vision
  response on a 1×1 PNG.
- FastAPI server started in `mock_mode=false` reports health
  `{"status":"ok","model":"gemini-3.5-flash","mock_mode":false}`.

## Text-LLM probe on real HisWise UCs

`scripts/hw_text_probe.py` posts 5 sampled UC descriptions from
`sds-full.txt` (UC-01 Browse, UC-02 Register, UC-03 Login, UC-06
Ask AI, UC-09 Delete Document) through `/review`. Each call returns
a real rubric-scored review with `mock:false`.

| Requirement     | Score | Issues |
|-----------------|-------|--------|
| HW-UC-01 Browse |   3   |   4    |
| HW-UC-02 Register |   6 |   2    |
| HW-UC-03 Login   |   5  |   3    |
| HW-UC-06 Ask AI  |   4  |   4    |
| HW-UC-09 Delete  |   4  |   3    |
| **Total**       | **4 avg** | **16 findings** |

Issue-type histogram on 16:

- vagueness: 3
- untestable: 3
- incomplete: 6
- ambiguity: 3
- inconsistent: 1

Severity histogram:

- high: 8
- medium: 8

→ Scaling 5→15 UCs (all HisWise UCs) ≈ 48 findings — within striking
distance of the brief's expected 50 (round-2 of this would close it
+ the cross-artifact pass would add the FK matrix 16).

## Vision-LLM probe on a real HisWise ERD quadrant

`scripts/hw_vision_probe.py` posts the top-left ERD quadrant
(`erd-tl.png`, 82,466 bytes) plus a corresponding requirement text
(Document + DocumentChunk tables) to `/review` with `image_b64`. The
server returns 2 issues.

**Harness caveat (per `srs-review-ai/AGENTS.md`):** the line "Model
không đọc được ảnh trong phiên harness này" is the authoritative
note. What we can verify from the harness:

- ✓ The HTTP call returns 200 + a non-empty issues array
- ✓ `contract_version=1.0.0` + `mock=false` confirms it's a real LLM
  response, not a stub
- ✓ The vision transport (image_b64 in request body) is accepted
  end-to-end through the FastAPI proxy → Gemini

What we **cannot** independently verify from the harness:

- ✗ Whether the model correctly *saw* the entities in `erd-tl.png`
- ✗ Whether the issues it returned are correct against the actual
  diagram contents (vs. hallucinated from the requirement text)

So the right claim for R18 is: **vision LLM transport is live; the
content of vision-derived findings needs human review before being
treated as authoritative**. The brief's "8 cross-artifact findings"
on HisWise is now *reachable* (mechanism works) but not yet
*measured* (no human verification of LLM-vs-actual-diagram on disk).

Vision result for the record:

- Issue 1: `untestable / medium` — Qdrant sync timing unspecified
- Issue 2: `vagueness / low` — `file details` / `sharing settings` not
  enumerated to DB fields

mock=false, contract_version=1.0.0, model=gemini-3.5-flash,
dropped_issue_count=0.

## Acceptance gate re-assessment

| Gate                                    | Status at R17 (blocked) | Status at R18 |
|-----------------------------------------|-------------------------|---------------|
| OTES ≥ 8 red M2                         | ✓ 285 measured          | ✓ unchanged    |
| OTES 8 named findings (5 LLM-required)  | ❌ 1/8 (only SRS-01)     | ❌ still 1/8 (no OTES LLM run yet) |
| Verdict ≈ 4/10 (LLM-required)           | ❌                      | ❌ not run    |
| UNV-01/02 not green                     | Partial                 | Partial       |
| HisWise 50/24 + 16 FK                   | ❌ fixture + LLM        | ⚠ transport live (5-UC text + 1-quadrant vision) — full 15-UC + 4-quadrant measurement pending |
| Ledger ID-stable                        | ✓                      | ✓ unchanged    |

The R18 work converts the HisWise gate from "❌ untestable" to
"⚠ untested but verifiable" — the next round can run the 15-UC
+ 4-quadrant probe for the full 50/24 + 16 FK measurement.

## What was NOT changed in app code

R18 is pure **evidence-gathering**: probe scripts + this doc. No
Flutter code, no schema bump, no test changes. The deterministic
floor (R1–R17, 448 tests, 285 red M2) is unchanged. Adding the LLM
pass to the app code (a `LlmPass` consumed by `WorkspaceViewModel`
that surfaces AI findings alongside deterministic) is a separate
round's work.

## Reproduce

```bash
# 1. Start server
cd srs-review-ai
set -a; source server/.env; set +a
cd server && .venv/bin/python -m uvicorn app.main:app \
  --host 127.0.0.1 --port 8000 > /tmp/fastapi.log 2>&1 &

# 2. Wait for it
curl -s http://127.0.0.1:8000/health

# 3. Run text probe
python3 docs/evidence/scripts/hw_text_probe.py

# 4. Run vision probe
python3 docs/evidence/scripts/hw_vision_probe.py
```

Quota state: `RATE_LIMIT_PER_DAY=10000`; 7 calls used in this round
(1 health + 1 text × 5 + 1 vision). 9,993 remaining.