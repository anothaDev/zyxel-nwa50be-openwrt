#!/bin/sh

set -eu

usage() {
	echo "usage: $0 <openwrt-directory> <log-directory>" >&2
	exit 2
}

[ "$#" -eq 2 ] || usage

openwrt="$1"
log_dir="$2"
max_attempts=6

[ -d "$openwrt" ]
mkdir -p "$log_dir"

attempt=1
while [ "$attempt" -le "$max_attempts" ]; do
	log="$log_dir/qca-ssdk-shell-attempt-$attempt.log"
	if make -C "$openwrt" -j1 package/qca-ssdk-shell/compile V=s \
		>"$log" 2>&1; then
		echo "qca-ssdk-shell bootstrap completed on attempt $attempt."
		exit 0
	fi

	if ! grep -Eq "No rule to make target '.*\.d', needed by '.*\.o'" "$log" || \
		grep -Eqi 'fatal error:|undefined reference|collect2: error' "$log"; then
		cat "$log"
		echo "Refusing: unexpected qca-ssdk-shell failure on attempt $attempt." >&2
		exit 1
	fi

	error=$(grep -E "No rule to make target '.*\.d', needed by '.*\.o'" \
		"$log" | tail -n 1)
	printf 'qca-ssdk-shell bootstrap attempt %s/%s: %s\n' \
		"$attempt" "$max_attempts" "$error"
	attempt=$((attempt + 1))
done

echo "Refusing: qca-ssdk-shell did not build after $max_attempts attempts." >&2
exit 1
