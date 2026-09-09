# ADR 0004 — Model choice, and three REST details that would break the demo

Status: accepted · 2026-09-09 · revises D7 of [ADR 0001](0001-architecture.md)

## Context

The research behind this project chose `gemini-2.5-flash-lite` with
`gemini-2.5-flash` as a fallback, and quoted 2.5-series pricing and free-tier
limits. Checking ai.google.dev directly before writing the client turned up
four things that change the implementation.

## Findings

**1. The 2.5 series is legacy.** The current lineup is `gemini-3.8-flash` (GA
flagship Flash), `gemini-3.7-flash`, `gemini-3.6-flash`, `gemini-3.5-flash`,
plus the lite tier: `gemini-3.5-flash-lite` and `gemini-3.1-flash-lite`. There
is no `gemini-3.8-flash-lite`. `gemini-3.1-flash-lite-preview` was shut down on
2026-05-25.

**2. Gemini 3+ removed generation parameters.** `temperature`, `top_p`,
`top_k` and `candidate_count` are no longer part of `generationConfig`, and
`thinking_budget` was replaced by the `thinking_level` enum.

**3. The REST Schema uses the uppercase protobuf Type enum** — `OBJECT`,
`STRING`, `ARRAY`, `INTEGER`, `BOOLEAN` — not the lowercase spelling of plain
JSON Schema. Field names in `generationConfig` are camelCase
(`responseMimeType`, `responseSchema`), and the key travels in the
`x-goog-api-key` header.

**4. Free-tier quotas moved.** Google cut free limits around December 2025 and
they differ per model, so the "15 RPM / 1,000 RPD" figure attached to
2.5-flash-lite should not be planned against. Effective quota is visible per
project in AI Studio.

## Decisions

- Primary model **`gemini-3.5-flash-lite`**: current, low cost, multimodal
  (text/image/PDF), and its model page names document parsing as a target
  workload — which is literally this app's job.
- Fallback **`gemini-3.1-flash-lite`**: explicitly the stable long-term
  low-cost option, so a 429 on the primary degrades to something that will not
  disappear mid-semester.
- Not `gemini-3.8-flash`: introductory pricing is $0.75/$3.75 per 1M tokens
  versus the lite tier, and reviewing one requirement at a time does not need a
  long-horizon agentic model.
- `temperature` is sent **only to 1.x/2.x models**, decided by parsing the
  generation out of the model id (`_supports_temperature` in `llm/gemini.py`).
  An unrecognised or alias name is treated as modern, because omitting
  temperature costs a little determinism while sending it can be rejected.
- Model ids are **pinned in configuration, never hardcoded**, so switching is
  one line in `server/.env`. Avoid `-latest` aliases: they hot-swap under you,
  which is the last thing you want the week of a defense.

## What still needs checking with a real key

The team must confirm, in AI Studio, that their project's free-tier quota
covers a demo run (≈25 requirements per document). If it does not, the cache
plus offline mock mode already cover the demo; a paid Tier 1 top-up is the
fallback of last resort.

## Sources

- [Models](https://ai.google.dev/gemini-api/docs/models) · [Gemini 3.5 Flash-Lite](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite) · [Gemini 3.1 Flash-Lite](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite) · [Gemini 3.8 Flash](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash)
- [Structured outputs](https://ai.google.dev/gemini-api/docs/structured-output) · [Generating content (REST reference)](https://ai.google.dev/api/generate-content)
- [Rate limits](https://ai.google.dev/gemini-api/docs/rate-limits) · [Pricing](https://ai.google.dev/gemini-api/docs/pricing)
