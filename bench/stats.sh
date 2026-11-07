#!/bin/sh
# Samples container CPU/memory every 2s while a benchmark runs (host side).
out=${1:-results/docker-stats.csv}
mkdir -p "$(dirname "$out")"
echo "time,container,cpu,mem" > "$out"
while true; do
  docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}}' braxy-backend-1 braxy-pg-1 braxy-redis-1 2>/dev/null \
    | sed "s/^/$(date -u +%H:%M:%S),/" >> "$out"
  sleep 2
done
