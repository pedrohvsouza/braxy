#!/usr/bin/env bash
# HTTP sweep with wrk for one topology, rotating 2,000 logged-in users.
#   bench/run-wrk.sh <slug> "<BENCH_CMD>" [levels] [duration]
set -euo pipefail
cd "$(dirname "$0")/.."
slug=$1; cmd=$2; levels=${3:-"16 64 256 512 1024"}; dur=${4:-10s}
export COMPOSE_FILE=docker-compose.yml:docker-compose.bench.yml
docker compose exec -T pg psql -q -U braxy -d braxy_development < bench/reset.sql >/dev/null
BENCH_CMD="$cmd" SACI_MT="${SACI_MT:-0}" docker compose up -d --force-recreate backend >/dev/null 2>&1
docker compose exec -T redis redis-cli FLUSHDB >/dev/null
for _ in $(seq 1 60); do
  docker compose exec -T loadgen wget -qO- http://backend:3000/up 2>/dev/null | grep -q OK && break
  sleep 2
done
docker compose exec -T loadgen sh -c 'node cookies.mjs 2000 > results/cookies.tsv && wc -l < results/cookies.tsv'
./bench/stats.sh "bench/results/wrk-$slug-stats.csv" & sp=$!
[ -n "${BEFORE_SWEEP:-}" ] && sh "$BEFORE_SWEEP"
docker compose exec -T -e ONLY="${ONLY:-}" loadgen sh wrk-sweep.sh "$dur" "$levels" > "bench/results/wrk-$slug.txt" 2>&1 || true
kill $sp
grep POINT "bench/results/wrk-$slug.txt" | sed 's/^POINT://' | node -e '
let rows=require("fs").readFileSync(0,"utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
for (const r of rows) console.log(`${r.endpoint.padEnd(9)} c=${String(r.connections).padStart(5)} ${String(r.rps).padStart(7)} req/s p50=${r.p50}ms p95=${r.p95}ms p99=${r.p99}ms err=${r.errors}+${r.sockerr}`)'
