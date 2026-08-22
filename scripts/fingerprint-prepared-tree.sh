#!/bin/sh

set -eu

usage() {
	echo "usage: $0 <prepared-wlan-ap-directory>" >&2
	exit 2
}

[ "$#" -eq 1 ] || usage

tree=$1
openwrt="$tree/openwrt"

for command in find git mktemp readlink rm sha256sum sort stat; do
	command -v "$command" >/dev/null 2>&1 || {
		echo "Missing required command: $command" >&2
		exit 1
	}
done

sha256_file() {
	result=$(sha256sum "$1") || return 1
	printf '%s\n' "${result%% *}"
}

hash_git_worktree() {
	repo=$1
	exclude=${2-}
	manifest=$(mktemp)
	paths=$(mktemp)

	if ! (
		head=$(git -C "$repo" rev-parse HEAD) || exit 1
		printf 'head\t%s\n' "$head"
		git -C "$repo" diff --binary --full-index --no-ext-diff HEAD -- || exit 1
		git -C "$repo" ls-files --others --exclude-standard >"$paths" || exit 1
		LC_ALL=C sort -o "$paths" "$paths" || exit 1
		while IFS= read -r path; do
			[ -n "$path" ] || continue
			[ "$path" = "$exclude" ] && continue
			if [ -L "$repo/$path" ]; then
				target=$(readlink "$repo/$path") || exit 1
				printf 'untracked-link\t%s\t%s\n' "$path" "$target"
			elif [ -f "$repo/$path" ]; then
				mode=$(stat -c '%a' "$repo/$path") || exit 1
				digest=$(sha256_file "$repo/$path") || exit 1
				printf 'untracked-file\t%s\t%s\t%s\n' \
					"$path" "$mode" "$digest"
			else
				echo "Refusing: unsupported untracked path: $repo/$path" >&2
				exit 1
			fi
		done <"$paths"
	) >"$manifest"; then
		rm -f "$manifest" "$paths"
		return 1
	fi

	digest=$(sha256_file "$manifest") || {
		rm -f "$manifest" "$paths"
		return 1
	}
	rm -f "$manifest" "$paths"
	printf '%s\n' "$digest"
}

hash_directory() {
	directory=$1
	manifest=$(mktemp)
	paths=$(mktemp)

	if ! (
		find "$directory" \( -type f -o -type l \) -printf '%P\n' >"$paths" || exit 1
		LC_ALL=C sort -o "$paths" "$paths" || exit 1
		while IFS= read -r path; do
			[ -n "$path" ] || continue
			if [ -L "$directory/$path" ]; then
				target=$(readlink "$directory/$path") || exit 1
				printf 'link\t%s\t%s\n' "$path" "$target"
			else
				mode=$(stat -c '%a' "$directory/$path") || exit 1
				digest=$(sha256_file "$directory/$path") || exit 1
				printf 'file\t%s\t%s\t%s\n' \
					"$path" "$mode" "$digest"
			fi
		done <"$paths"
	) >"$manifest"; then
		rm -f "$manifest" "$paths"
		return 1
	fi

	digest=$(sha256_file "$manifest") || {
		rm -f "$manifest" "$paths"
		return 1
	}
	rm -f "$manifest" "$paths"
	printf '%s\n' "$digest"
}

[ -d "$tree/.git" ]
[ -d "$openwrt/.git" ]
[ -f "$openwrt/.config" ]
[ -d "$openwrt/files" ]

printf 'format=1\n'
tip=$(hash_git_worktree "$tree" '.nwa50be-community-prepared') || exit 1
openwrt_hash=$(hash_git_worktree "$openwrt") || exit 1
printf 'tip=%s\n' "$tip"
printf 'openwrt=%s\n' "$openwrt_hash"
for feed in packages luci routing telephony video; do
	feed_hash=$(hash_git_worktree "$openwrt/feeds/$feed") || exit 1
	printf 'feed_%s=%s\n' "$feed" "$feed_hash"
done
config_hash=$(sha256_file "$openwrt/.config") || exit 1
overlay_hash=$(hash_directory "$openwrt/files") || exit 1
printf 'config=%s\n' "$config_hash"
printf 'overlay=%s\n' "$overlay_hash"
