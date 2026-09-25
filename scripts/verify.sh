#!/bin/bash

# compare the sandbox account against the pristine mirror using a dry run of rsync

source "$(dirname "$0")/../config.sh"
trap 'echo; echo "Interrupted"; exit 130' INT TERM

for dir in pristine empty; do
	if [ ! -d "$MIRROR/$dir" ]; then
		echo "Missing mirror directory: $MIRROR/$dir"
		exit 1
	fi
done

echo "--- VERIFYING HOME ---"
HOME_DIFF=$(rsync -ainO --delete $EXCLUDES -e "$RSSH" "$MIRROR/pristine/" "$HOST:")
echo "$HOME_DIFF"

echo "--- VERIFYING SCRATCH ---"
SCRATCH_DIFF=$(rsync -ainO --no-perms --delete -e "$RSSH" "$MIRROR/empty/" "$HOST:scratch/")
echo "$SCRATCH_DIFF"

echo "--- VERIFYING PROJECT ---"
PROJECT_DIFF=$(rsync -ainO --no-perms --delete -e "$RSSH" "$MIRROR/empty/" "$HOST:$PROJECT/")
echo "$PROJECT_DIFF"

echo "--- VERIFYING PROCESSES ---"
PROC_DIFF=$($RSSH "$HOST" bash <<'EOF'
MY_SESSION=$(ps -o sid= -p $$)
ps -u "$USER" -o pid=,sid=,comm= \
	| awk -v me="$MY_SESSION" '$2 != me && $3 !~ /^sshd/ && $3 != "systemd" && $3 != "(sd-pam)"'
EOF
)
echo "$PROC_DIFF"

if [ -z "$HOME_DIFF" ] && [ -z "$SCRATCH_DIFF" ] && [ -z "$PROJECT_DIFF" ] && [ -z "$PROC_DIFF" ]; then
	echo "User account is pristine"
	exit 0
else
	echo "User account is NOT pristine"
	exit 1
fi
