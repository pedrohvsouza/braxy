#!/bin/sh
# HTTP sweep with wrk (inside the loadgen container): endpoints x connections,
# rotating across logged-in users. Prints JSON lines for summarize.mjs.
#   sh wrk-sweep.sh [duration] [levels]
DUR=${1:-10s}
LEVELS=${2:-"16 64 256 512 1024"}
T=${WRK_THREADS:-10}
C=results/cookies.tsv
run() { # name path method
  for c in $LEVELS; do
    out=$(wrk -t"$T" -c"$c" -d"$DUR" --latency -s wrk-users.lua "$TARGET" -- "$C" "$2" "$3" 2>&1 | grep RESULT)
    echo "$out" | awk -v ep="$1" -v c="$c" '{
      split($0, kv, " "); line = "{\"endpoint\":\"" ep "\",\"connections\":" c;
      for (i = 2; i <= length(kv); i++) { split(kv[i], p, "="); line = line ",\"" p[1] "\":" p[2] }
      print "POINT:" line "}" }'
    sleep 2
  done
}
run up /up GET
run session /api/session GET
run sidebar /api/sidebar GET
run messages "/api/conversations/{room}/messages" GET
run post "/api/conversations/{room}/messages" POST
