# Dev image for the Braxy backend: Crystal toolchain + libpq + the Saci CLI.
# The CLI is built from the mounted framework checkout at container start
# (see infra/backend-entrypoint.sh) so it always matches ../saci.
FROM crystallang/crystal:1.22.0

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends libpq-dev libsqlite3-dev curl \
 && rm -rf /var/lib/apt/lists/*

COPY infra/backend-entrypoint.sh /usr/local/bin/backend-entrypoint
RUN chmod +x /usr/local/bin/backend-entrypoint

ENTRYPOINT ["backend-entrypoint"]
