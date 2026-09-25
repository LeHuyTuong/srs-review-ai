"""Review orchestration — everything between the HTTP layer and the provider.

Extracted from ``main.py`` so the route handlers stay thin (ADR-0013,
docs/architecture-refactored.md §2): the routes translate HTTP, this module
owns the use case. Dependencies arrive as plain callables/values, so nothing
here imports FastAPI.

Preserved invariants (tests pin all of these):

* the cache key covers every prompt input (requirement id, text, section,
  image, page index, provider, mock flag, model selection, prompt version,
  rubric version + fingerprints, fuzzy threshold);
* the batch prompt carries the same per-unit body as the single path, and
  every quote is verified against its own unit's text;
* split-on-failure only on STRUCTURAL failure — a dead provider is reported
  per unit, never fanned out (the retry-storm lesson, ADR-0010);
* per-unit caching so a re-run (or a partly failed batch) is free.
"""

from __future__ import annotations

import logging
from typing import Any, Protocol

from pydantic import ValidationError

from ..config.settings import Settings
from ..contracts.schemas import (
    LLM_BATCH_REVIEW_SCHEMA,
    LLM_REVIEW_SCHEMA,
    BatchReviewUnit,
    ReviewResult,
)
from ..domain.provider import LlmError
from ..domain.verification import review_issues
from ..infrastructure.cache import cache_key
from .prompt_assembly import (
    review_batch_user_prompt,
    review_system_prompt,
    review_user_prompt,
)

log = logging.getLogger("srs-proxy")

_UNIT_FAILED = "AI provider unavailable for this requirement."
_BATCH_FAILED = "AI provider unavailable for this batch of requirements."
_NO_RESULT = "No result was produced for this requirement."


class ReviewProvider(Protocol):
    """The slice of the provider protocol the review use case touches."""

    name: str

    async def generate_json(self, **kwargs: Any) -> Any: ...


class ReviewCache(Protocol):
    """The slice of the cache the review use case touches."""

    def get(self, key: str) -> ReviewResult | None: ...

    def put(self, key: str, value: ReviewResult) -> None: ...


def review_config(rubric: Any, criteria: Any) -> dict[str, Any]:
    """The rubric plus the criteria snapshot this request is scored against.

    One object on purpose. The prompt renders `criteria_block` and the cache key
    hashes `criteria_fingerprint` from the SAME read of the store, so a criterion
    edited between the cache lookup and the cache store cannot write a result
    under the key of the wording that produced it. The cached rubric dict is
    never mutated — `load_rubric` is `lru_cache`d and shared process-wide.
    """
    return {
        **rubric.current(),
        "rubric_fingerprint": rubric.fingerprint(),
        "criteria_fingerprint": criteria.fingerprint(),
        "criteria_block": criteria.prompt_block("unit"),
    }


def review_cache_key(
    *,
    requirement_id: str,
    text: str,
    section: str | None,
    image_b64: str | None,
    page_index: int | None,
    settings: Settings,
    rubric_cfg: dict[str, object],
    provider: ReviewProvider,
) -> str:
    """One key, used for BOTH the lookup and the store.

    Cache identity follows the configured model selection even in mock mode:
    switching the selected model must not reuse an older result, and provider
    identity keeps mock and online results isolated. Primary/fallback order is
    part of the identity, so swapping them invalidates the old result.

    Lookup and store used to be two hand-copied expressions over the same
    inputs. They agreed, but only by maintenance — and they disagreed in the
    one case where no model is configured, where the lookup fell back to the
    provider id and the store wrote an empty string, so that configuration
    could never get a cache hit at all. One function, one key.
    """
    models = [settings.gemini_model, settings.gemini_fallback_model]
    models = [model for model in models if model]
    if not models:
        models = [getattr(provider, "model_id", provider.name)]
    return cache_key(
        requirement_id,
        text,
        section or "",
        image_b64 or "",
        str(page_index) if page_index is not None else "",
        provider.name,
        str(settings.mock_mode),
        "|".join(models),
        settings.prompt_version,
        str(rubric_cfg["version"]),
        str(settings.fuzzy_threshold),
        # The marking scale reached the prompt through `quality_criteria` and
        # decides every score, so its fingerprint belongs in the key for the same
        # reason `rubric.version` does: reweight `testable` and the old scores are
        # not answers to the new question. The seed alone would not catch it —
        # an override leaves `version` alone.
        str(rubric_cfg.get("rubric_fingerprint", "")),
        # The editable criteria reach the prompt through `criteria_block`, so
        # their fingerprint belongs in the key for the same reason the rubric
        # version does: change the wording and the old result is not an answer
        # to the new question. Without this line, switching a criterion off
        # would keep serving the reviews it produced.
        str(rubric_cfg.get("criteria_fingerprint", "")),
    )


def cached_review(cache: ReviewCache, key: str) -> ReviewResult | None:
    hit = cache.get(key)
    return hit.model_copy(update={"cached": True}) if hit else None


def build_result(
    *,
    requirement_id: str,
    text: str,
    raw: dict[str, Any],
    model: str,
    provider: ReviewProvider,
    settings: Settings,
    usage: dict[str, Any] | None = None,
) -> ReviewResult:
    """Turn one provider payload into a verified, contract-shaped result.

    Shared by the single and batch paths so quote verification, score clamping
    and the `mock` flag can never drift between them.
    """
    kept, dropped = review_issues(
        [i for i in raw.get("issues", []) if isinstance(i, dict)],
        text,
        threshold=settings.fuzzy_threshold,
    )
    usage = usage or {}
    return ReviewResult(
        requirement_id=requirement_id,  # trust our own id, not the model's
        score=_clamp_score(raw.get("score")),
        issues=kept,
        context_note=raw.get("context_note"),
        dropped_issue_count=dropped,
        model=model,
        cached=False,
        mock=provider.name == "mock",
        prompt_tokens=usage.get("prompt_tokens"),
        completion_tokens=usage.get("completion_tokens"),
        total_tokens=usage.get("total_tokens"),
    )


def _clamp_score(value: object) -> int:
    try:
        return max(0, min(10, int(value)))  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return 0


async def review_uncached(
    *,
    requirement_id: str,
    text: str,
    section: str | None,
    page_index: int | None,
    image_b64: str | None,
    settings: Settings,
    rubric_cfg: dict[str, object],
    provider: ReviewProvider,
) -> ReviewResult:
    """One unit, one provider call — the path that has always worked."""
    res = await provider.generate_json(
        system=review_system_prompt(rubric_cfg),
        user=review_user_prompt(requirement_id, text, section, page_index),
        schema=LLM_REVIEW_SCHEMA,
        image_b64=image_b64,
    )
    raw, model = res[0], res[1]
    usage = getattr(res, "usage", None) or (res[2] if len(res) > 2 else {})
    return build_result(
        requirement_id=requirement_id,
        text=text,
        raw=raw,
        model=model,
        provider=provider,
        settings=settings,
        usage=usage,
    )


def index_batch_payload(raw: dict[str, Any]) -> dict[int, dict[str, Any]]:
    """Map `results[]` entries by unit_index, ignoring anything unusable.

    Duplicates keep the first entry: a model that answers twice for one unit has
    not earned the right to overwrite its own first answer mid-review.
    """
    entries = raw.get("results")
    if not isinstance(entries, list):
        return {}
    indexed: dict[int, dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        index = entry.get("unit_index")
        if isinstance(index, bool) or not isinstance(index, int):
            continue
        indexed.setdefault(index, entry)
    return indexed


async def review_group(
    units: list[tuple[int, BatchReviewUnit]],
    *,
    settings: Settings,
    rubric_cfg: dict[str, object],
    provider: ReviewProvider,
    cache: ReviewCache,
) -> tuple[dict[int, ReviewResult], dict[int, str]]:
    """Review [units] with as few calls as possible, never fewer results.

    Returns (results by unit_index, failures by unit_index). Every requested
    unit comes back in exactly one of the two maps.

    Split-on-failure, and deliberately only on STRUCTURAL failure: if the model
    answered but the payload did not cover every unit, the group is halved (or
    just the missing tail re-asked) and the units are retried — the model, not
    the provider, was the problem. If the provider call itself failed (the
    pacer already gave it the provider's own retry window), the whole group is
    reported failed rather than fanned out: splitting a dead provider into 8
    single calls is how 1 failure becomes a storm.
    """
    if not units:
        return {}, {}

    if len(units) == 1:
        index, unit = units[0]
        try:
            result = await review_uncached(
                requirement_id=unit.requirement_id,
                text=unit.text,
                section=unit.section,
                page_index=unit.page_index,
                image_b64=None,
                settings=settings,
                rubric_cfg=rubric_cfg,
                provider=provider,
            )
        except LlmError as exc:
            log.warning("batch unit %s failed: %s", unit.requirement_id, exc)
            return {}, {index: _UNIT_FAILED}
        except ValidationError as exc:
            log.warning(
                "batch unit %s returned an unexpected structure: %s",
                unit.requirement_id,
                exc,
            )
            return {}, {index: _UNIT_FAILED}
        store_review(cache, unit, result, settings, rubric_cfg, provider)
        return {index: result}, {}

    try:
        res = await provider.generate_json(
            system=review_system_prompt(rubric_cfg),
            user=review_batch_user_prompt(units),
            schema=LLM_BATCH_REVIEW_SCHEMA,
        )
        raw, model = res[0], res[1]
        usage = getattr(res, "usage", None) or (res[2] if len(res) > 2 else {})
    except LlmError as exc:
        log.warning("batched review of %d units failed: %s", len(units), exc)
        return {}, {index: _BATCH_FAILED for index, _ in units}

    prompt_tokens = usage.get("prompt_tokens")
    completion_tokens = usage.get("completion_tokens")
    total_tokens = usage.get("total_tokens")
    n = max(1, len(units))
    unit_usage = {
        "prompt_tokens": prompt_tokens // n if prompt_tokens is not None else None,
        "completion_tokens": completion_tokens // n if completion_tokens is not None else None,
        "total_tokens": total_tokens // n if total_tokens is not None else None,
    }

    indexed = index_batch_payload(raw)
    results: dict[int, ReviewResult] = {}
    failures: dict[int, str] = {}
    unresolved: list[tuple[int, BatchReviewUnit]] = []
    for index, unit in units:
        entry = indexed.get(index)
        if entry is None:
            unresolved.append((index, unit))
            continue
        try:
            result = build_result(
                requirement_id=unit.requirement_id,
                text=unit.text,
                raw=entry,
                model=model,
                provider=provider,
                settings=settings,
                usage=unit_usage,
            )
        except ValidationError as exc:
            log.warning("batched entry for %s was unusable: %s", unit.requirement_id, exc)
            unresolved.append((index, unit))
            continue
        store_review(cache, unit, result, settings, rubric_cfg, provider)
        results[index] = result

    if not unresolved:
        return results, failures

    if len(unresolved) == len(units):
        # Nothing usable at all: half the group, so the next attempt is a
        # smaller prompt. Recursion bottoms out at the single-unit path.
        middle = max(1, len(unresolved) // 2)
        halves = (unresolved[:middle], unresolved[middle:])
    else:
        halves = (unresolved,)
    for half in halves:
        sub_results, sub_failures = await review_group(
            half, settings=settings, rubric_cfg=rubric_cfg, provider=provider, cache=cache
        )
        results.update(sub_results)
        failures.update(sub_failures)
    return results, failures


def store_review(
    cache: ReviewCache,
    unit: BatchReviewUnit,
    result: ReviewResult,
    settings: Settings,
    rubric_cfg: dict[str, object],
    provider: ReviewProvider,
) -> None:
    """Cache per unit, so a re-run (or a partially failed batch) is free."""
    cache.put(
        review_cache_key(
            requirement_id=unit.requirement_id,
            text=unit.text,
            section=unit.section,
            image_b64=None,
            page_index=unit.page_index,
            settings=settings,
            rubric_cfg=rubric_cfg,
            provider=provider,
        ),
        result,
    )
