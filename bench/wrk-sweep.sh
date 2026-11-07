#!/bin/sh
# HTTP sweep with wrk (inside the loadgen container): endpoints x connections,
# rotating across logged-in users. Prints JSON lines for summarize.mjs.
#   sh wrk-sweep.sh [duration] [levels]
DUR=${1:-10s}
LEVELS=${2:-"16 64 256 512 1024"}
T=${WRK_THREADS:-10}
C=results/cookies.tsv
run() { # name path method [body]
  if [ -n "${ONLY:-}" ] && ! echo " $ONLY " | grep -q " $1 "; then return; fi
  for c in $LEVELS; do
    # "read": the cursor only moves while messages keep arriving, as in a
    # live room, so a light poster runs on every room alongside.
    if [ "$1" = read ]; then
      wrk -t2 -c32 -d"$DUR" -s wrk-users.lua "$TARGET" -- "$C" "/api/conversations/{room}/messages" POST > /dev/null 2>&1 &
      poster=$!
    fi
    out=$(wrk -t"$T" -c"$c" -d"$DUR" --latency -s wrk-users.lua "$TARGET" -- "$C" "$2" "$3" ${4:+"$4"} 2>&1 | grep RESULT)
    [ "$1" = read ] && wait "$poster"
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
run read "/api/conversations/{room}/read" POST '{"message_id":9000000000000}'
