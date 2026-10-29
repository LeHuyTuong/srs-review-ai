# syntax=docker/dockerfile:1
# Production image for the FastAPI proxy — server only.
#
# Build context is server/ (not the repository root), so the daemon never
# receives desktop/, mobile/ (76 MB of docs) or the .git history:
#   docker build -t srs-review-api server
#
# origin/dev carries docker/server.Dockerfile with a repository-root context;
# this file is the server-only variant of the same image (same base, same /data
# layout, same non-root user), so the two can be reconciled when dev merges.
#
# Runtime data lives under /data (one volume covers all five stores), so the
# container can be replaced without losing cache, rubric overrides, shares,
# submissions or class rosters. The image itself is stateless.

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# pymupdf ships manylinux wheels, so slim needs no build toolchain here.
# requirements.txt only — pytest/ruff (requirements-dev.txt) stay out of the image.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Only the package: tests, tool_summarize_batch.py and the tracked .shares/
# samples are not runtime code.
COPY app ./app

# One volume, five stores. settings.py defaults these to SERVER_ROOT/.<name>;
# pointing them at /data keeps every store on the volume.
ENV SRS_UPLOAD_DIR=/data/.uploads \
    SRS_CACHE_DIR=/data/.cache \
    SRS_SHARE_DIR=/data/.shares \
    SRS_SUBMISSION_DIR=/data/.submissions \
    SRS_CLASS_DIR=/data/.classes

RUN mkdir -p /data/.uploads /data/.cache /data/.shares /data/.submissions /data/.classes \
 && useradd -m -u 10001 appuser \
 && chown -R appuser:appuser /data /app

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4).status==200 else 1)"

# ONE worker, on purpose. The provider pacer, the API-key ring and the daily
# rate limiter are process-global and in-memory (ADR-0010): N workers would be
# N independent pacers calling Gemini N times as fast, and N quotas per user —
# the retry-storm shape this repo already paid for. Scale up, not out.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
