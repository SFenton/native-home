#!/usr/bin/env bash
# Waits (no polling) for a lane's running tools/bg_run.py job whose label starts with PREFIX, then prints its digest.
#   tools/wait_lane.sh PREFIX WORKTREE
PREFIX="$1"; WT="$2"; PID=""; LABEL=""
for p in $(pgrep -f "bg_run.py $PREFIX"); do
  args=$(ps -o args= -p "$p" | head -1)
  [[ "$args" == *Python* || "$args" == python3* ]] || continue
  PID=$p; LABEL=$(echo "$args" | sed -E 's/.*bg_run.py ([^ ]+).*/\1/'); break
done
[[ -z "$PID" ]] && { echo "no running job for $PREFIX"; exit 0; }
caffeinate -w "$PID"
echo "== $LABEL"; head -12 "$WT/build/runs/$LABEL.digest"
