# syntax=docker/dockerfile:1.7
#
# Braxy production images (multi-stage). Two targets:
#
#   backend  release build of the API + Cable server, run as N single-thread
#            processes on one port (bin/multi, SO_REUSEPORT)
#   web      Caddy with the built SPA: serves the static files, proxies
#            /api, /cable and /up to the backend and terminates TLS
#
# Saci is a path dependency (../../saci from backend/), so it comes in as a
# named build context. Pin it to a commit for reproducible builds:
#
#   docker build -f infra/prod.Dockerfile --target backend -t braxy-prod:local \
#     --build-context saci=https://github.com/pedrohvsouza/saci.git#master .
#   docker build -f infra/prod.Dockerfile --target web -t braxy-prod-web:local .
#
# (`--build-context saci=../saci` builds against the local checkout instead.)

ARG CRYSTAL_VERSION=1.22.0
ARG NODE_VERSION=22
ARG CADDY_VERSION=2.10

# --- frontend: static SPA bundle ---------------------------------------------
FROM node:${NODE_VERSION}-alpine AS frontend
WORKDIR /app
COPY frontend/package.json frontend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --no-fund
COPY frontend/ ./
# Shown in the footer (vite.config.ts reads it; there is no .git here).
ARG BRAXY_GIT_SHA=dev
ENV BRAXY_GIT_SHA=${BRAXY_GIT_SHA}
RUN npm run build

# --- build: release binaries -------------------------------------------------
FROM crystallang/crystal:${CRYSTAL_VERSION} AS build
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends libsqlite3-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work/braxy/backend

# Saci sources only (its lib/, .git and specs stay out of the image).
COPY --from=saci shard.yml /work/saci/shard.yml
COPY --from=saci src /work/saci/src

# Dependencies first so app edits do not invalidate the shards layer.
COPY backend/shard.yml backend/shard.lock ./
RUN shards install --production

COPY backend/ ./
# Single-threaded on purpose: production runs several processes (bin/multi)
# instead of -Dexecution_context, which is not stable under load yet (C7).
RUN --mount=type=cache,target=/root/.cache/crystal \
    mkdir -p bin \
 && crystal build src/backend.cr --release --no-debug -o bin/backend \
 && crystal build db/migrate.cr --release --no-debug -o bin/saci-migrate \
 && crystal build script/doctor.cr --release --no-debug -o bin/saci-doctor

# --- backend runtime ---------------------------------------------------------
# Same distribution as the Crystal image, so the shared libraries match.
FROM ubuntu:26.04 AS backend
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      ca-certificates curl libgcc-s1 libgmp10 libpcre2-8-0 libsqlite3-0 \
      libssl3t64 libyaml-0-2 libzstd1 tzdata zlib1g \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 10001 --shell /usr/sbin/nologin braxy

WORKDIR /app
COPY --from=build /work/braxy/backend/bin/backend /work/braxy/backend/bin/saci-migrate /work/braxy/backend/bin/saci-doctor /app/bin/
COPY backend/bin/docker-entrypoint backend/bin/multi /app/bin/
COPY backend/config/server.yml /app/config/server.yml
COPY backend/config/locales /app/config/locales
COPY backend/public /app/public
# db/ is created by the migrator; storage/ holds uploads when S3 is not set.
RUN mkdir -p /app/db /app/tmp /app/log /app/storage \
 && chown braxy:braxy /app/db /app/tmp /app/log /app/storage

# SACI_THREADS=1 overrides `threads: 4` in config/server.yml (one thread per
# process); WEB_CONCURRENCY processes share the port (default: nproc).
ENV APP_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000 \
    SACI_THREADS=1 \
    SACI_LOG_FORMAT=json

USER braxy
EXPOSE 3000
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3000/up || exit 1
# The entrypoint runs pending migrations unless SKIP_DB_PREPARE=1 (the prod
# compose file migrates once in a separate service and skips it here).
ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["/app/bin/multi", "/app/bin/backend"]

# --- web: Caddy + SPA --------------------------------------------------------
FROM caddy:${CADDY_VERSION}-alpine AS web
COPY infra/Caddyfile /etc/caddy/Caddyfile
COPY --from=frontend /app/dist /srv/braxy
