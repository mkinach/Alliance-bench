#!/bin/bash

# reset the user account to the pristine state by rsyncing from the mirror

source "$(dirname "$0")/../config.sh"
trap 'echo; echo "Interrupted"; exit 130' INT TERM

for dir in pristine empty; do
	if [ ! -d "$MIRROR/$dir" ]; then
		echo "missing mirror directory: $MIRROR/$dir"
		exit 1
	fi
done

echo "--- RESETTING HOME ---"
rsync -aO --delete \
	$EXCLUDES \
	-e "$RSSH" "$MIRROR/pristine/" "$HOST:"

echo "--- RESETTING SCRATCH ---"
rsync -aO --no-perms --delete \
	-e "$RSSH" "$MIRROR/empty/" "$HOST:scratch/"

echo "--- REMOVING LINGERING JOBS, PROCESSES, AND FILES ---"
$RSSH "$HOST" bash <<'EOF'
scancel -u "$USER"
find /tmp -user "$USER" -delete 2>/dev/null
MY_SESSION=$(ps -o sid= -p $$)
ps -u "$USER" -o pid=,sid=,comm= \
	| awk -v me="$MY_SESSION" '$2 != me && $3 !~ /^sshd/ && $3 != "systemd" && $3 != "(sd-pam)" {print $1}' \
	| xargs -r kill
EOF

echo "Reset complete"
