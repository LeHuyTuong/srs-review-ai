# syntax=docker/dockerfile:1

# Comments are provided throughout this file to help you get started.
# If you need more help, visit the Dockerfile reference guide at
# https://docs.docker.com/go/dockerfile-reference/

# Want to help us make this template better? Share your feedback here: https://forms.gle/ybq9Krt8jtBL3iCk7

# Published as anhvietanh1123/srs-review-ai:latest — the name lives in
# compose.yaml (`image:`), so `docker compose build` tags it and
# `docker compose push` uploads it.

ARG PYTHON_VERSION=3.12.10
FROM python:${PYTHON_VERSION}-slim AS base

# Prevents Python from writing pyc files.
ENV PYTHONDONTWRITEBYTECODE=1

# Keeps Python from buffering stdout and stderr to avoid situations where
# the application crashes without emitting any logs due to buffering.
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Create a non-privileged user that the app will run under.
# See https://docs.docker.com/go/dockerfile-user-best-practices/
ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    appuser

# Download dependencies as a separate step to take advantage of Docker's caching.
# Leverage a cache mount to /root/.cache/pip to speed up subsequent builds.
# Leverage a bind mount to requirements.txt to avoid having to copy them into
# into this layer.
RUN --mount=type=cache,target=/root/.cache/pip \
    --mount=type=bind,source=requirements.txt,target=requirements.txt \
    python -m pip install -r requirements.txt

# Writable data lives on ONE volume, /data. settings.py otherwise defaults
# every store to /app/.<name>, which appuser cannot write (COPY leaves /app
# owned by root) — the cache would silently fall back to memory and uploads
# would fail. Point all five stores at /data and hand that directory to
# appuser.
ENV SRS_UPLOAD_DIR=/data/.uploads \
    SRS_CACHE_DIR=/data/.cache \
    SRS_SHARE_DIR=/data/.shares \
    SRS_SUBMISSION_DIR=/data/.submissions \
    SRS_CLASS_DIR=/data/.classes
RUN mkdir -p /data/.uploads /data/.cache /data/.shares /data/.submissions /data/.classes \
 && chown -R appuser:appuser /data

# Switch to the non-privileged user to run the application.
USER appuser

# Copy the source code into the container. .dockerignore keeps .env and
# local runtime data out — this image is public on Docker Hub.
COPY . .

# Expose the port that the application listens on.
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4).status==200 else 1)"

# Run the application. Exec form, so uvicorn is PID 1 and receives SIGTERM
# directly (the shell form wraps it in /bin/sh and `docker stop` waits 10 s).
# ONE worker on purpose: the Gemini pacer, the API-key ring and the daily
# quota are in-memory and per process (ADR-0010).
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
