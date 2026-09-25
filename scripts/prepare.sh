#!/bin/bash

# reset the pristine user account and pushes the task prompt
# prompt the user to run the experiment

source "$(dirname "$0")/../config.sh"
trap 'echo; echo "Interrupted"; exit 130' INT TERM
TASK="$1"

if [ -z "$TASK" ] || [ ! -f "tasks/$TASK/prompt.md" ]; then
  echo "usage: $0 <task_id>   (tasks/<task_id>/prompt.md must exist)"
  exit 1
fi

scripts/reset.sh   || exit 1
scripts/verify.sh  || exit 1

echo "--- PUSHING TASK $TASK ---"
bash -c 'source config.sh; echo "SUFFIX: $SUFFIX"'
{ cat "tasks/$TASK/prompt.md"; printf '\n\n%s\n' "$SUFFIX"; } | $RSSH "$HOST" "mkdir -p bench-run && cat > bench-run/prompt.md"
rsync -a -e "$RSSH" scripts/cluster/run.sh "$HOST:bench-run/"
rsync -a --no-perms -e "$RSSH" --exclude='prompt.md' "tasks/$TASK/" "$HOST:"
