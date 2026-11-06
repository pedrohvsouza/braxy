# Multi-stage build: compile with the official Crystal image, then
# ship only the release binaries in a slim, non-root runtime.
FROM crystallang/crystal:1.22.0 AS build
WORKDIR /app

# Dependencies first so source edits do not invalidate the cache.
# NOTE: the generated shard.yml uses a local `path:` for saci. Make
# that path available in the build context (or vendor/publish Saci)
# before building the image.
COPY shard.yml ./
RUN shards install --production

COPY . .
# -Dexecution_context makes SACI_THREADS/config/server.yml `threads`
# effective; without it Crystal stays single-threaded (a no-op).
RUN crystal build src/backend.cr --release --no-debug -Dexecution_context -o bin/backend
RUN crystal build db/migrate.cr --release --no-debug -o bin/saci-migrate
RUN crystal build script/doctor.cr --release --no-debug -o bin/saci-doctor

FROM debian:bookworm-slim AS runtime
# Runtime libraries required by the release binary (verified with
# `ldd`). crystal-pg/crystal-mysql speak the wire protocol in pure
# Crystal, so no libpq/libmysqlclient is needed.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl libgcc-s1 libpcre2-8-0 libsqlite3-0 libssl3 \
      libstdc++6 libyaml-0-2 libzstd1 tzdata zlib1g \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 --shell /usr/sbin/nologin saci \
 && mkdir -p /app/bin /app/config/locales /app/db /app/log /app/public \
             /app/storage /app/tmp/pids \
 && chown -R saci:saci /app

WORKDIR /app
ENV APP_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000

COPY --from=build --chown=saci:saci /app/bin/backend /app/bin/backend
COPY --from=build --chown=saci:saci /app/bin/saci-migrate /app/bin/saci-migrate
COPY --from=build --chown=saci:saci /app/bin/saci-doctor /app/bin/saci-doctor
COPY --from=build --chown=saci:saci /app/bin/docker-entrypoint /app/bin/docker-entrypoint
COPY --from=build --chown=saci:saci /app/config/locales /app/config/locales
COPY --from=build --chown=saci:saci /app/config/database.yml /app/config/database.yml
COPY --from=build --chown=saci:saci /app/config/cache.yml /app/config/cache.yml
COPY --from=build --chown=saci:saci /app/config/queue.yml /app/config/queue.yml
COPY --from=build --chown=saci:saci /app/config/cable.yml /app/config/cable.yml
COPY --from=build --chown=saci:saci /app/config/recurring.yml /app/config/recurring.yml
COPY --from=build --chown=saci:saci /app/config/storage.yml /app/config/storage.yml
COPY --from=build --chown=saci:saci /app/config/server.yml /app/config/server.yml
COPY --from=build --chown=saci:saci /app/public /app/public

USER saci
EXPOSE 3000
# SIGTERM triggers Saci::Deploy::GracefulShutdown (drain + hooks).
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD curl -fsS http://127.0.0.1:3000/up || exit 1

ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["/app/bin/backend"]
