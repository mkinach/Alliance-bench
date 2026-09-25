#!/bin/bash

# pull data from a completed benchmark experiment on the cluster

source "$(dirname "$0")/../config.sh"
trap 'echo; echo "Interrupted"; exit 130' INT TERM
TASK="$1"
LABEL="$2"

if [ -z "$TASK" ] || [ -z "$LABEL" ]; then
	echo "usage: $0 <task_id> <label>"
	exit 1
fi

RUN_ID="${TASK}_${LABEL}_$(date +%Y%m%d-%H%M%S)"
DEST="results/$RUN_ID"
mkdir -p "$DEST"

echo "--- PULLING RUN DATA ---"
rsync -a -e "$RSSH" "$HOST:bench-run/out/" "$DEST/out/"
rsync -a -e "$RSSH" "$HOST:bench-run/prompt.md" "$DEST/prompt.md"

if [ ! -f "$DEST/out/done" ]; then
	echo "WARNING: no completion marker, run may not have finished"
fi

echo "--- SNAPSHOTTING ACCOUNT ---"
rsync -a -e "$RSSH" --max-size=1M --exclude='/nearline' --exclude='/projects' --exclude='/.local' --exclude='/bench-run' --exclude='/.cache' --exclude='site-packages' --exclude='__pycache__' --exclude='*.so' --exclude='*.whl' "$HOST:" "$DEST/home_after/"
rsync -a -e "$RSSH" --max-size=1M "$HOST:scratch/" "$DEST/scratch_after/"

echo "--- CHECKING SOLUTION ---"
EXPECTED="tasks_solutions/$TASK/solution.md"
ACTUAL="$DEST/home_after/solution.md"
if [ ! -f "$EXPECTED" ]; then
  STATUS="NO_REFERENCE"
elif [ ! -f "$ACTUAL" ]; then
  STATUS="MISSING"
elif diff -Bw "$EXPECTED" "$ACTUAL" > "$DEST/solution.diff"; then
  STATUS="PASS"
else
  STATUS="FAIL"
fi
echo "$STATUS" > "$DEST/status.txt"
echo "Solution check: $STATUS"

echo "Collection complete in $DEST"
