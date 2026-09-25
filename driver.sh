#!/bin/bash

# main driver script for the benchmark

source "$(dirname "$0")/config.sh"
trap 'echo; echo "Interrupted"; exit 130' INT TERM

N="$1"; shift
[ -z "$N" ] || [ $# -eq 0 ] && { echo "usage: $0 <repeats> <task_id> [task_id ...]"; exit 1; }

for EXP in "$@"; do
  for i in $(seq -f "%02g" 1 "$N"); do
    LABEL="run${i}"
    echo "===== $EXP $LABEL ====="
    scripts/prepare.sh "$EXP" || exit 1
    if [ -n "$MANUAL" ]; then  # invoke with MANUAL=1 ./driver.sh ...
      echo "Log in to $HOST and run:  bash ~/bench-run/run.sh"
      echo "Press enter here when it prints 'Run complete'"
      read -r
    else
      $RSSH "$HOST" "bash -l ~/bench-run/run.sh" || exit 1
    fi
    scripts/collect.sh "$EXP" "$LABEL" || exit 1
    RUN_DIR=$(ls -d results/${EXP}_${LABEL}_* | tail -1)
    python3 scripts/report.py "$RUN_DIR"
    scripts/reset.sh
    echo "$EXP $LABEL: $(cat "$RUN_DIR/status.txt")"
  done
done

python3 scripts/aggregate.py
