# syntax=docker/dockerfile:1
# Production image for the FastAPI proxy.
#
# Runtime data lives under /data (one volume covers all five stores), so the
# container can be replaced without losing cache, rubric overrides, shares,
# submissions, or class rosters. The image itself is stateless.
#
# Build from the repository root:
#   docker build -f docker/server.Dockerfile -t srs-review-api .

FROM python:3.11-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# pymupdf ships manylinux wheels, so slim needs no build toolchain here.
COPY server/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY server/ ./

# One volume, five stores. These are the defaults the app reads from
# SERVER_ROOT at runtime; overriding them here keeps everything in /data.
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

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
