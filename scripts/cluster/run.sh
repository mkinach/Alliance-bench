#!/bin/bash

# run and capture data from a benchmark experiment on the cluster

RUN_DIR="$HOME/bench-run"
OUT="$RUN_DIR/out"
MAX_TURNS=50
TIMEOUT_SECONDS=1800

export PATH="$HOME/.local/bin:$PATH"

SAMPLER_PID=""
cleanup() {
  echo
  echo "Interrupted, stopping agent and sampler"
  pkill -u "$USER" -f 'claude -p' 2> /dev/null
  kill "$SAMPLER_PID" 2> /dev/null
  echo "interrupted" > "$OUT/exit_code"
  date +%s > "$OUT/end_epoch"
  exit 130
}
trap cleanup INT TERM

mkdir -p "$OUT"
cd "$HOME" || exit 1

# metadata
date +%s > "$OUT/start_epoch"
{
  echo "host: $(hostname)"
  echo "user: $USER"
  echo "claude_version: $(claude --version)"
  echo "max_turns: $MAX_TURNS"
  echo "timeout_seconds: $TIMEOUT_SECONDS"
} > "$OUT/meta.txt"

# resource sampling
if command -v pidstat > /dev/null; then
  pidstat -u -r -h -U "$USER" 1 > "$OUT/pidstat.log" 2>&1 &
else
  top -b -d 1 -u "$USER" > "$OUT/top.log" 2>&1 &
fi
SAMPLER_PID=$!

# the agent
TIMEFORMAT='wall_seconds %R
user_cpu_seconds %U
sys_cpu_seconds %S'

{ time \
  timeout "$TIMEOUT_SECONDS" \
  claude -p \
    --output-format stream-json --verbose \
    --max-turns "$MAX_TURNS" \
    --permission-mode bypassPermissions \
    --append-system-prompt "Do not ask for help or guidance." \
    --disallowedTools "WebSearch,WebFetch" \
    < "$RUN_DIR/prompt.md" \
    > "$OUT/transcript.jsonl" \
    2> "$OUT/stderr.txt"
} 2> "$OUT/time.txt"
echo $? > "$OUT/exit_code"

kill "$SAMPLER_PID" 2> /dev/null
date +%s > "$OUT/end_epoch"

START_TIME=$(date -d "@$(cat "$OUT/start_epoch")" +%Y-%m-%dT%H:%M:%S)
sacct -u "$USER" -S "$START_TIME" \
-o JobID,JobName,Partition,State,ExitCode,Elapsed,ReqTRES,NodeList -P \
> "$OUT/sacct.txt" 2>&1

# Claude Code's own session log (as backup)
cp -r "$HOME/.claude/projects" "$OUT/claude_projects" 2> /dev/null

find "$HOME" "$HOME/scratch/" -xdev -not -path "$RUN_DIR/*" \
-printf '%y %s %TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null > "$OUT/files.txt"
du -sh "$HOME" "$HOME/scratch/" 2>/dev/null > "$OUT/du.txt"
touch "$OUT/done"
echo "Run complete"
