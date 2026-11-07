#!/bin/sh
# Daily pg_dump for the production stack. Runs forever: dumps at BACKUP_AT
# (UTC, HH:MM) into /backups/braxy-<timestamp>.dump and deletes dumps older
# than BACKUP_KEEP_DAYS. `pg-backup now` takes one dump and exits.
#
# Restore: pg_restore --clean --if-exists -d braxy_production <file>
set -eu

dump() {
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  out="/backups/braxy-$ts.dump"
  pg_dump --format=custom --no-owner --file="$out.partial"
  mv "$out.partial" "$out"
  echo "[backup] wrote $out ($(du -h "$out" | cut -f1))"
  find /backups -name 'braxy-*.dump' -mtime "+${BACKUP_KEEP_DAYS:-14}" -print -delete
}

if [ "${1:-}" = "now" ]; then
  dump
  exit 0
fi

at=${BACKUP_AT:-03:30}
echo "[backup] daily at $at UTC, keeping ${BACKUP_KEEP_DAYS:-14} days"
while :; do
  now=$(date -u +%s)
  next=$(date -u -d "$(date -u +%Y-%m-%d) $at" +%s 2>/dev/null || echo 0)
  [ "$next" -gt "$now" ] || next=$((next + 86400))
  sleep $((next - now))
  dump || echo "[backup] FAILED" >&2
done
