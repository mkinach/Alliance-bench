#!/bin/bash

# capture the pristine state of the user account into the mirror directory
# run once after the account has been cleaned by hand

source "$(dirname "$0")/../config.sh"
trap 'echo; echo "Interrupted"; exit 130' INT TERM

if [ -d "$MIRROR" ]; then
	echo "$MIRROR already exists... remove it first if you want to re-mirror"
	exit 1
fi

mkdir -p "$MIRROR/empty"

echo "--- MIRRORING HOME ---"
rsync -a --info=progress2 -h $EXCLUDES -e "$RSSH" "$HOST:" "$MIRROR/pristine/"

echo "--- MIRROR CONTENTS ---"
find "$MIRROR" -printf '%P %y\n' | sort
