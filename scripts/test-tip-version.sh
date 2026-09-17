#!/bin/sh

set -eu

[ "$#" -eq 1 ] || { echo "usage: $0 <prepared-getver.sh>" >&2; exit 2; }
getver=$(realpath -- "$1")
test -x "$getver"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/tip/openwrt"
git init -q -b main "$tmp/tip"
git -C "$tmp/tip" config user.name 'NWA50BE version test'
git -C "$tmp/tip" config user.email 'noreply@invalid.example'
git -C "$tmp/tip" -c commit.gpgsign=false commit -q --allow-empty -m 'Synthetic release'

expect_version() {
	actual=$(TOPDIR="$tmp/tip/openwrt" "$getver" wlan-ap-version)
	if [ "$actual" != "$1" ]; then
		printf 'TIP version mismatch: expected <%s>, got <%s>\n' "$1" "$actual" >&2
		exit 1
	fi
}

git -C "$tmp/tip" -c tag.gpgsign=false tag v5.1.0-rc2
expect_version v5.1.0-rc2
git -C "$tmp/tip" -c tag.gpgsign=false tag v5.1.0
expect_version v5.1.0
# Even an annotated prerelease at this commit must not supersede its final tag.
git -C "$tmp/tip" -c tag.gpgsign=false tag -a v5.1.0-rc3 -m 'Synthetic prerelease'
expect_version v5.1.0
git -C "$tmp/tip" -c commit.gpgsign=false commit -q --allow-empty -m 'Synthetic development'
expect_version ''
git -C "$tmp/tip" -c tag.gpgsign=false tag deployment-test
expect_version ''

echo 'TIP version tests passed (5 cases).'
