# ADR 0010 — Who paces the provider: the proxy paces, the app batches

Status: accepted · 2026-09-22

## Context

The OTES run of 2026-09-22 (`reviews/`, snapshot 00:51) reviewed 238 of its 240
units and cost **1347 upstream Gemini calls, 1109 of them refused**
(582 × 429 on `gemini-3.5-flash-lite`, 522 × 429 plus 503s on the fallback).
The app sent 414 requests for 238 units; the server's own rate limit read
414/2000 — nowhere near exhausted. So the ceiling was never *quota*: it was the
provider's per-minute limit colliding with how the two sides retried.

Three multipliers, all of them ours:

1. **One provider call per unit.** 235 units = 235 calls, before any failure.
2. **In-place retries without jitter.** `GeminiProvider` backed off a fixed
   1s/2s/4s, up to `max_retries` (3) **per model** (2 models) — one unhappy unit
   could burn 6 calls. Four workers retried on the same rhythm, so every retry
   wave arrived as a single spike against a per-minute bucket.
3. **The app retried what the server had already given up on.** `_translate`
   marked 502 `isRetryable`, so each of those 176 failed requests was sent up to
   three more times, each triggering up to 6 upstream calls the proxy had already
   decided were hopeless.

The provider's own answer was being ignored too: Google returns `RetryInfo`
(`"retryDelay": "7s"`) and/or `Retry-After`, and the code guessed 1s/2s/4s
instead.

## Decision

**The proxy owns pacing; the app owns batching; a 502 means "already retried".**

- `server/app/llm/pacing.py` holds one `ProviderPacer` per provider **for the
  whole process** — not per provider instance, because `build_provider()` runs
  once per HTTP request and per-instance state would pace nothing. It combines a
  token bucket (12 calls/min, burst 4), a cooldown taken from the provider's own
  retry window, and jitter on every wait. Cooldowns are per model: Google meters
  per-minute quota per model, so a throttled primary must not stall a fallback
  with headroom; a 503 (service-wide) cools down every model. One request never
  waits more than `provider_max_cooldown_s` (45s) in total, so a throttled call
  still answers inside the app's 90s timeout.
- `POST /review/batch` reviews up to `max_batch_units` (8) text-only units in one
  call. Same per-unit prompt body, numbered by `unit_index`; the response is an
  array addressed by that index; every quote is verified against that unit's own
  text. A payload that does not cover every unit is re-split (halved, or just the
  missing tail re-asked); a *provider* failure is NOT fanned out, because
  splitting a dead provider into 8 single calls is how one failure becomes a
  storm.
- The app packs 6 text-only units per call (`AppConfig.reviewBatchSize`). A unit
  whose page raster is attached — or whose text is empty — travels alone.
- The app no longer retries 502. 503 (platform, in front of the proxy) still
  gets one attempt, because nothing was reviewed yet.
- `/review/batch` answers **200 with a `failed[]` list** rather than failing
  whole when some units fail: the units that were reviewed are already cached and
  paid for, and a 502 would make the client throw them away.

Measured reduction on the same shape of work: 1347 calls → ~240 (pacing alone)
→ ~40 (pacing + batches of 6). The 238-unit run becomes ~22 HTTP requests.

## Consequences

- **One call per unit is now the exception, not the rule.** Any new endpoint that
  reviews text should be batched; any new upstream call must go through the
  pacer, or it re-creates the storm on its own.
- **Latency moved from the client to the queue.** A throttled run is slower in
  wall time than a lucky one — deliberately. The old behaviour was not faster; it
  was 1109 refusals that looked like progress.
- Deployment skew is handled, not assumed away: a proxy without the endpoint
  answers 404 (and a too-small batch cap answers 413), and the app falls back to
  one call per unit for the rest of the run instead of failing every unit.
- Batching makes the daily request limit (`rate_limit_per_day`) count *requests*,
  which is now much larger than units reviewed per day. That is coherent — the
  limit exists to protect the provider quota, which is counted in calls — but it
  does mean the number in `/health` no longer reads as "units per day".
- Not addressed here (tracked separately): deterministic checks still run but
  every unit still reaches the LLM. Routing rule-decided units away from the
  model would cut calls further, but it changes what a score *means*, so it needs
  a product decision.
