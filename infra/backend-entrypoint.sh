#!/bin/sh
# Builds the Saci CLI from the mounted framework (/work/saci) when it is
# missing or older than the framework sources, then runs the given command.
set -e

SACI_SRC=/work/saci
SACI_OUT=/root/.cache/saci-cli/saci

if [ ! -x "$SACI_OUT" ] || [ -n "$(find "$SACI_SRC/src" -newer "$SACI_OUT" -name '*.cr' -print -quit 2>/dev/null)" ]; then
  echo "[braxy] building saci CLI from $SACI_SRC ..."
  mkdir -p "$(dirname "$SACI_OUT")"
  (cd "$SACI_SRC" && shards install --skip-postinstall >/dev/null && crystal build src/cli.cr -o "$SACI_OUT")
fi
ln -sf "$SACI_OUT" /usr/local/bin/saci

exec "$@"
