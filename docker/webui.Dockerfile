# syntax=docker/dockerfile:1
# Production image for the web-ui SPA: vite build -> nginx static.
#
# The nginx config arrives through a named build context (`cfg`), so this file
# can stay next to server.Dockerfile in docker/ without copying nginx.conf into
# the repository root or fighting the build context.
#
# Build from the repository root:
#   docker build -f docker/webui.Dockerfile \
#     --build-context cfg=docker \
#     -t srs-review-web .

FROM node:22-alpine AS build

WORKDIR /app

COPY web-ui/package.json web-ui/pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile

COPY web-ui/ ./
RUN pnpm build

FROM nginx:1.27-alpine AS serve

COPY --from=build /app/dist /usr/share/nginx/html
COPY --from=cfg nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
