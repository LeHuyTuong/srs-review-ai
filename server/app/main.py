"""SRS Review AI — thin LLM proxy.

Bootstrap only (ADR-0013, docs/architecture-refactored.md §2): app factory,
CORS, router registration, and the composition root that creates the
singletons the routes share. The routes live in ``app.api.*`` (one router per
bounded context), the use cases in ``app.application`` and the backing
services in ``app.infrastructure``. Every endpoint path, status code and
response shape is unchanged from the single-module version.

The singletons are created at import time, exactly like the pre-refactor
module: ``tests/conftest.py`` redirects SRS_CACHE_DIR *before* importing this
module and relies on the cache being open by then. ``api.deps`` hands these
objects (and this module's ``build_provider``) to the routers as FastAPI
dependencies — it is the seam that keeps the routers from reaching back into
``main`` while tests keep patching ``main_module.build_provider`` /
``main_module._review_cache`` / ``main_module._upload_store`` as always.

Responsibilities of the proxy as a whole (and nothing else):
  1. hold the API key                    5. verify every quote  <-- the point
  2. build the rubric prompt             6. validate the response contract
  3. force structured JSON output        7. rate limit + cache
  4. pick provider / model               8. never leak provider errors verbatim
"""

from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import accounts, ask, classes, diagram, health, review, submissions, uploads
from .config.criteria import CriteriaStore
from .config.rubric_store import RubricStore
from .config.settings import get_settings
from .contracts.schemas import CONTRACT_VERSION, ReviewResult
from .infrastructure.accounts import AccountStore
from .infrastructure.classes import ClassStore
from .infrastructure.diagram import DiagramResponse
from .infrastructure.llm.router import build_provider
from .infrastructure.ratelimit import RateLimiter
from .infrastructure.share import ShareStore
from .infrastructure.store import SqliteCache
from .infrastructure.submissions import SubmissionStore
from .infrastructure.uploads import UploadStore

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("srs-proxy")

app = FastAPI(
    title="SRS Review AI proxy",
    version=CONTRACT_VERSION,
    description="Reviews one requirement at a time against a configurable rubric.",
)

_settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in _settings.cors_origins.split(",") if o.strip()],
    allow_methods=["GET", "POST", "PUT"],
    allow_headers=["*"],
)

# Durable, not in-memory: a restart used to discard a whole paid-for run. The
# key already carries every input that can change a result (prompt/rubric/model
# versions included), so a code or rubric change invalidates old rows by itself —
# the database needs no migration for it.
_cache_path = _settings.cache_dir / "cache.sqlite3"
_review_cache: SqliteCache[ReviewResult] = SqliteCache(
    _cache_path,
    namespace="review",
    encode=ReviewResult.model_dump_json,
    decode=ReviewResult.model_validate_json,
    max_entries=_settings.cache_max_entries,
)
_diagram_cache: SqliteCache[DiagramResponse] = SqliteCache(
    _cache_path,
    namespace="diagram",
    encode=DiagramResponse.model_dump_json,
    decode=DiagramResponse.model_validate_json,
    max_entries=_settings.cache_max_entries,
)
_limiter = RateLimiter()

_upload_store = UploadStore(
    _settings.upload_dir,
    _settings.max_upload_bytes,
    _settings.app_token,
)

_share_store = ShareStore(_settings.share_dir)
_submission_store = SubmissionStore(_settings.submission_dir, _settings.submission_max_bytes)

# Class rosters (plan 12 WP2, ADR-0017). One file per class; membership lives
# on the submission rows, so this store owns only the class's own fields.
_class_store = ClassStore(_settings.class_dir)

# Submission records (plan 9, P2). A group uploads through /uploads/presign,
# then names the blob here so the review that follows is addressable by one
# capability id — the same posture as /share, and with the same serverless
# caveat recorded in the store's docstring.

# The editable evaluation criteria. Its own sqlite file, NOT the review cache:
# the cache is pruned by an LRU cap, and a criterion the pruner evicted would be
# a criterion the user believes they configured.
_criteria = CriteriaStore(_settings.cache_dir / "criteria.sqlite3")

# Accounts and sessions (ADR-0020). Its own file, and NOT degraded to memory
# when the disk is unwritable — see the store's docstring: an auth store that
# silently forgets every account presents itself to every user as "wrong
# password" at once, which is the least debuggable failure a login can have.
_account_store = AccountStore(_settings.cache_dir / "accounts.sqlite3")

# The live rubric: seed + whatever leaves a user has overridden. Its own sqlite
# file for the same reason as the criteria — a marking scale a restart could
# quietly roll back is not an editable scale.
_rubric = RubricStore(_settings.cache_dir / "rubric.sqlite3")

app.include_router(health.router)
app.include_router(health.config_router)
app.include_router(review.router)
app.include_router(ask.router)
app.include_router(diagram.router)
app.include_router(diagram.documents_router)
app.include_router(uploads.router)
app.include_router(uploads.share_router)
app.include_router(submissions.router)
app.include_router(classes.router)
app.include_router(accounts.router)

__all__ = [
    "CONTRACT_VERSION",
    "_account_store",
    "_criteria",
    "_diagram_cache",
    "_limiter",
    "_review_cache",
    "_rubric",
    "_share_store",
    "_upload_store",
    "app",
    "build_provider",
    "get_settings",
    "log",
]
