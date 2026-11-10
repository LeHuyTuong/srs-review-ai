#!/usr/bin/env bash
# Runs ON the VPS, piped over SSH stdin (see .github/workflows/cd.yml). Nothing
# is written into the project directory: this script never copies a compose
# file, an .env or a Caddyfile onto the host, so the hand-maintained layout in
# ~/srs-review-ai keeps running exactly as it was.
#
# Positional args (passed by `ssh ... bash -s -- <args>`):
#   1  IMAGE_NAME    e.g. anhvietanh1123/srs-review-ai
#   2  PROJECT_DIR   e.g. /root/srs-review-ai
#   3  SERVICE       compose service name, default "server"
#   4  HEALTH_PORT   port the service answers on inside the container, default 8000
#   5  SOURCE_REF    full image reference to deploy, default "<IMAGE_NAME>:latest".
#                    A different ref (e.g. ":sha-abc123") is pulled and re-tagged
#                    to :latest, which is what makes "roll back to that build"
#                    and the manual redeploy button actually mean something.
#
# Exit codes are distinct on purpose, so a red job names the failing layer:
#   10 compose unreadable / service unknown / no .env
#   11 pull failed
#   12 migration failed
#   13 container did not come up
#   14 health probe never returned 200

set -Eeuo pipefail

IMAGE_NAME="${1:?image name required}"
PROJECT_DIR="${2:?project dir required}"
SERVICE="${3:-server}"
HEALTH_PORT="${4:-8000}"
SOURCE_REF="${5:-${IMAGE_NAME}:latest}"
HEALTH_URL="http://127.0.0.1:${HEALTH_PORT}/health"

BACKUP_TAG="${IMAGE_NAME}:prev"

# Declared before any trap can fire: `set -u` would otherwise abort inside the
# exit handler when a preflight failure happens before the running image is
# inspected.
CURRENT_IMAGE_ID=""
DEPLOY_SUCCEEDED=0

log() { printf '\n[deploy] %s\n' "$*"; }
fail() {
  local code="$1"
  shift
  printf '\n[deploy] FAILED (%s): %s\n' "$code" "$*" >&2
  exit "$code"
}

cd "$PROJECT_DIR" || fail 10 "cannot cd into $PROJECT_DIR"

# ---------------------------------------------------------------- preflight
log "preflight in $PROJECT_DIR"
docker compose version || fail 10 "docker compose is missing on the VPS"
docker compose config --services >/dev/null 2>&1 \
  || fail 10 "docker compose config is unreadable in $PROJECT_DIR"

AVAILABLE_SERVICES="$(docker compose config --services 2>/dev/null | tr '\n' ' ')"
case " $AVAILABLE_SERVICES " in
  *" $SERVICE "*)
    log "service '$SERVICE' found (all: $AVAILABLE_SERVICES)"
    ;;
  *)
    fail 10 "service '$SERVICE' not in compose (found: $AVAILABLE_SERVICES)"
    ;;
esac

# The compose file in the repo reads ./server/.env. The VPS copy is hand-edited
# and may point at ./.env instead, so accept either and say which one is used.
if [ -f "$PROJECT_DIR/server/.env" ]; then
  log "env file: server/.env"
elif [ -f "$PROJECT_DIR/.env" ]; then
  log "env file: .env (compose must reference this path)"
else
  fail 10 "no .env found at server/.env or .env — compose has nothing to read"
fi

# ------------------------------------------------------------------ rollback
# Remember what is serving right now. Inspecting the container is more reliable
# than trusting :latest, which may already have been overwritten by a pull.
CURRENT_CONTAINER_ID="$(docker compose ps -q "$SERVICE" 2>/dev/null || true)"
if [ -n "$CURRENT_CONTAINER_ID" ]; then
  CURRENT_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$CURRENT_CONTAINER_ID" 2>/dev/null || true)"
fi

if [ -n "$CURRENT_IMAGE_ID" ]; then
  docker tag "$CURRENT_IMAGE_ID" "$BACKUP_TAG" \
    || fail 11 "could not tag the running image as $BACKUP_TAG"
  log "rollback point: $BACKUP_TAG -> $CURRENT_IMAGE_ID"
else
  log "no running '$SERVICE' container; nothing to keep as a rollback point"
fi

rollback() {
  if [ -z "$CURRENT_IMAGE_ID" ]; then
    printf '[deploy] no previous image to roll back to\n' >&2
    return 0
  fi
  printf '\n[deploy] rolling back to %s\n' "$BACKUP_TAG" >&2
  # Re-point :latest at the previous image and bring the service back. This is
  # a tag move: no rebuild, no network, no `docker rm`, and no `image prune` --
  # the previous image IS the rollback path, deleting it removes the way back.
  docker tag "$BACKUP_TAG" "${IMAGE_NAME}:latest" || return 1
  docker compose up -d --no-build --wait "$SERVICE" || return 1
  printf '[deploy] rollback finished; the previous image is serving again\n' >&2
}

# EXIT, not ERR. Measured on 2026-11-10: a shell `trap ... ERR` does NOT fire
# when a function calls `exit` explicitly, which is exactly what `fail` does --
# so the health-gate failure left the broken image serving and the rollback
# never ran. The EXIT trap fires for every non-zero exit however it was reached.
on_exit() {
  local code=$?
  if [ "$DEPLOY_SUCCEEDED" -eq 1 ] || [ "$code" -eq 0 ]; then
    return 0
  fi
  printf '\n[deploy] failed with exit %s; starting rollback\n' "$code" >&2
  rollback || printf '[deploy] ROLLBACK FAILED — manual action required\n' >&2
  return 0
}
trap on_exit EXIT

# --------------------------------------------------------------------- pull
# The compose file on the VPS points at :latest, so any other ref has to be
# pulled explicitly and re-tagged; `compose pull` would silently replace it
# with whatever :latest is on the registry.
if [ "$SOURCE_REF" = "${IMAGE_NAME}:latest" ]; then
  log "pulling ${IMAGE_NAME}:latest"
  docker compose pull "$SERVICE" || fail 11 "docker compose pull failed"
else
  log "pulling pinned ref ${SOURCE_REF}"
  docker pull "$SOURCE_REF" || fail 11 "docker pull $SOURCE_REF failed"
  docker tag "$SOURCE_REF" "${IMAGE_NAME}:latest" \
    || fail 11 "could not re-tag $SOURCE_REF as ${IMAGE_NAME}:latest"
fi

# ---------------------------------------------------------------- migration
# The image's CMD is uvicorn only, so schema changes land here and nowhere
# else. Running them with the NEW image and before the container swap means new
# code never serves a request against an old schema.
log "running migrations with the new image"
docker compose run --rm --no-deps -T "$SERVICE" alembic upgrade head \
  || fail 12 "alembic upgrade head failed — the container was NOT swapped"

# --------------------------------------------------------------------- swap
log "recreating '$SERVICE' with the new image"
docker compose up -d --no-build --wait "$SERVICE" \
  || fail 13 "docker compose up --wait failed"

# -------------------------------------------------------------- health gate
# `--wait` honours the compose healthcheck, but the VPS compose file is
# hand-maintained and may define none. Ask the container itself: every image
# built here ships python, curl does not.
log "probing $HEALTH_URL from inside the container"
probe_ok=0
for attempt in $(seq 1 10); do
  if docker compose exec -T "$SERVICE" python -c \
    "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('${HEALTH_URL}', timeout=5).status == 200 else 1)" \
    >/dev/null 2>&1; then
    probe_ok=1
    break
  fi
  printf '[deploy] health probe attempt %s/10 not ready yet\n' "$attempt"
  sleep 3
done

[ "$probe_ok" -eq 1 ] || fail 14 "health probe never returned 200"
log "health OK"

# Past this point the new image is serving and healthy, so a later failure must
# NOT roll back: the checksum step below only reads files.
DEPLOY_SUCCEEDED=1

# ------------------------------------------------------ integrity evidence
# Proof that this deploy rewrote nothing on the host. If these numbers ever
# change between runs, something started copying config onto the VPS.
log "checksums of the hand-maintained files (must not change across deploys)"
for relative_path in docker-compose.yml .env Caddyfile server/.env; do
  absolute_path="$PROJECT_DIR/$relative_path"
  if [ -f "$absolute_path" ]; then
    printf '  %s  %s\n' "$(sha256sum "$absolute_path" | cut -d' ' -f1)" "$relative_path"
  else
    printf '  %s  %s\n' "(absent)" "$relative_path"
  fi
done

log "deployed ${IMAGE_NAME}:latest (from ${SOURCE_REF})"
