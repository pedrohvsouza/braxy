#!/usr/bin/env bash
# Runs the HTTP sweep and the WebSocket ramp for one server topology, each on
# a freshly started backend (so one test's heap does not skew the other).
#   bench/run-config.sh <slug> "<BENCH_CMD>" [SACI_MT]
set -euo pipefail
cd "$(dirname "$0")/.."
slug=$1; cmd=$2; mt=${3:-0}
# WS_ONLY=1 skips the HTTP sweep; WS_STEPS overrides the ramp steps.
steps_arg=${WS_STEPS:+--steps $WS_STEPS}
export COMPOSE_FILE=docker-compose.yml:docker-compose.bench.yml COMPOSE_PROJECT_NAME=braxy-bench

restart() {
  BENCH_CMD="$cmd" SACI_MT="$mt" docker compose up -d --force-recreate backend >/dev/null 2>&1
  docker compose exec -T redis redis-cli FLUSHDB >/dev/null
  for _ in $(seq 1 60); do
    docker compose exec -T loadgen wget -qO- http://backend:3000/up 2>/dev/null | grep -q OK && return 0
    sleep 2
  done
  echo "backend did not come up" >&2; exit 1
}

if [ "${WS_ONLY:-0}" != "1" ]; then
echo "[$slug] http sweep"
restart
./bench/stats.sh "bench/results/sweep-$slug-stats.csv" & sp=$!
docker compose exec -T loadgen node http-sweep.mjs --duration 10 > "bench/results/http-sweep-$slug.txt" 2>&1 || true
kill $sp
fi

echo "[$slug] websocket ramp"
restart
./bench/stats.sh "bench/results/ws-$slug-stats.csv" & sp=$!
docker compose exec -T loadgen node ws.mjs --procs 10 $steps_arg > "bench/results/ws-$slug.txt" 2>&1 || true
kill $sp
docker inspect braxy-bench-backend-1 --format "[$slug] backend running={{.State.Running}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}"
