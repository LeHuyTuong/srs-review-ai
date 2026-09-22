"""Test-session setup.

`SRS_CACHE_DIR` is redirected to a throwaway directory *before* `app.main` is
imported, because the durable cache is opened at import time. Without this the
suite would read and — worse — `clear()` the real development cache under
`server/.cache/`, which on 2026-09-22 held 238 paid-for review results.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

_CACHE_DIR = Path(tempfile.mkdtemp(prefix="srs-review-test-cache-"))
os.environ["SRS_CACHE_DIR"] = str(_CACHE_DIR)
