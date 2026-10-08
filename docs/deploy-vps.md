# Deploying the proxy to a self-managed VPS

One host, one `docker compose up -d --build`. The compose file and both
Dockerfiles live in the repository (`docker-compose.yml`, `docker/server.Dockerfile`,
`docker/webui.Dockerfile`, `docker/nginx.conf`) — nothing has to be rebuilt by hand
on the server, and the two images are the same ones CI builds.

## What runs

| Service | Image | Host port | Purpose |
|---|---|---|---|
| `api` | `srs-review-api:repo` | `8000` | FastAPI proxy (`uvicorn app.main:app`) |
| `web` | `srs-review-web:repo` | `8080` | nginx serving the built web-ui SPA |

All five stores (uploads, cache, shares, submissions, classes) live under `/data`
in the named volume `srs-review-data`, so replacing a container never drops them.
The image itself is stateless.

## Before the first `up`

Two variables are read from the **compose environment**, not from `server/.env`,
because their defaults are unsafe on a public host:

- `PUBLIC_ORIGIN` — the origin the browser will call, e.g. `https://review.example.com`.
  It becomes `CORS_ORIGINS`. The settings default is `"*"`, which lets any origin
  call the API; compose refuses to start without this set.
- `APP_TOKEN` — the shared secret the app sends as `X-App-Token`. It is also the
  HMAC signing key for presigned-upload capability tokens. The settings default is
  `""`, which disables auth entirely (`settings.py`: "Empty => auth disabled
  (localhost demo)"). Compose refuses to start without this set.

`server/.env` still supplies the model and quota settings (`GEMINI_API_KEY`,
`GEMINI_MODEL`, `PROMPT_VERSION`, `RATE_LIMIT_PER_DAY`, …). Copy
`server/.env.example` to `server/.env` on the host and fill it in; it is
git-ignored and must stay that way.

```sh
export PUBLIC_ORIGIN=https://review.example.com
export APP_TOKEN=$(openssl rand -hex 32)
docker compose up -d --build
docker compose ps
curl -s http://127.0.0.1:8000/health
```

## Note on the auth model (do not build against the wrong ADR)

As of 2026-10-08, `docs/adr/0020-real-accounts-replace-the-capability-posture.md`
**supersedes ADR-0016/0017**: the plan is a `users` table with sessions in an
`HttpOnly` cookie, and `X-App-Token`/`X-Class-Key` stop being credentials and become
foreign keys. Until that lands, `APP_TOKEN` above is still the auth switch described
by `settings.py`. When ADR-0020 merges, this file's auth section has to change with
it — the deployment shape (two images, one volume, one origin) does not.

## Verifying a deployment

```sh
curl -s http://127.0.0.1:8000/health          # expect status:ok, criteria 13/13
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/            # expect 200
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/reviews/x   # expect 200 (SPA fallback)
```

The second and third prove nginx's `try_files ... /index.html` fallback, which a
deep link needs on first load. `docker inspect --format '{{.State.Health.Status}}' \$(docker compose ps -q api)`
should read `healthy`.
