#!/bin/sh

set -eu

project=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.."
	pwd
)
private_ipv4_pattern='10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}'
private_pattern='/home/[^/:[:space:]]+/|/Users/[^/:[:space:]]+/|[A-Za-z]:\\Users\\[^\\:[:space:]]+\\|BEGIN [A-Z0-9 ]*PRIVATE KEY|ssh-(rsa|ed25519) AAAA|tailscale|@omarchy|Galaxy S25|warranty-waiver token|github_pat_[[:alnum:]_]{20,}|gh[oprsu]_[[:alnum:]]{20,}'
mac_pattern='([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}'
unlock_token_pattern='[[:xdigit:]]{32}:[[:alnum:]+/]{80,}={0,2}\.[[:xdigit:]]{64}'

for command in find grep python3 sh; do
	command -v "$command" >/dev/null 2>&1 || {
		echo "Missing required command: $command" >&2
		exit 1
	}
done

python3 -c 'compile(open(__import__("sys").argv[1], "rb").read(), __import__("sys").argv[1], "exec")' \
	"$project/scripts/check-luci-mount-acl.py"

forbidden_files=$(find "$project" \
	\( -path "$project/.git" -o -path "$project/work" -o -path "$project/artifacts" \) \
	-prune -o -type f \( \
	-name '*.bin' -o -name '*.img' -o -name '*.ubi' -o -name '*.tar' \
	-o -name '*.tar.gz' -o -name 'authorized_keys' -o -name 'caldata.bin' \
	-o -name 'cal-ahb-*.bin' -o -iname '*art*backup*' -o -iname '*serial*capture*' \
	\) -print)

[ -z "$forbidden_files" ] || {
	echo 'Refusing: forbidden private or binary files found:' >&2
	printf '%s\n' "$forbidden_files" >&2
	exit 1
}

if grep -RIE --exclude-dir=.git --exclude-dir=work --exclude-dir=artifacts \
	--exclude='audit-public-tree.sh' \
	--exclude='verify-artifacts.sh' \
	"$private_pattern" \
	"$project" >/dev/null; then
	echo 'Refusing: private identity, key, path, or token material found.' >&2
	exit 1
fi

if grep -RIE --exclude-dir=.git --exclude-dir=work --exclude-dir=artifacts \
	--exclude='audit-public-tree.sh' "$private_ipv4_pattern" \
	"$project" >/dev/null; then
	echo 'Refusing: private IPv4 address found.' >&2
	exit 1
fi

if grep -RIE --exclude-dir=.git --exclude-dir=work --exclude-dir=artifacts \
	--exclude='audit-public-tree.sh' "$unlock_token_pattern" \
	"$project" >/dev/null; then
	echo 'Refusing: Zyxel-style unlock token found.' >&2
	exit 1
fi

if command -v git >/dev/null 2>&1 && \
	git -C "$project" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	if git -C "$project" log --all -p -- . \
		':(exclude)scripts/audit-public-tree.sh' \
		':(exclude)scripts/verify-artifacts.sh' | \
		grep -Ea "$private_pattern" >/dev/null; then
		echo 'Refusing: Git history contains private identity, key, path, or token material.' >&2
		exit 1
	fi

	if git -C "$project" log --all -p -- . \
		':(exclude)scripts/audit-public-tree.sh' | \
		grep -Ea "$private_ipv4_pattern" >/dev/null; then
		echo 'Refusing: Git history contains a private IPv4 address.' >&2
		exit 1
	fi

	if git -C "$project" log --all -p -- . \
		':(exclude)scripts/audit-public-tree.sh' | \
		grep -Ea "$unlock_token_pattern" >/dev/null; then
		echo 'Refusing: Git history contains a Zyxel-style unlock token.' >&2
		exit 1
	fi

	if git -C "$project" log --all -p -- . \
		':(exclude)scripts/audit-public-tree.sh' | \
		grep -Ea "$mac_pattern" >/dev/null; then
		echo 'Refusing: Git history contains a literal MAC address.' >&2
		exit 1
	fi

	if git -C "$project" rev-list --objects --all | \
		grep -Eai '\.(bin|img|ubi|tar|tar\.gz)$|(^|/)(authorized_keys|caldata\.bin|cal-ahb-[^ ]*\.bin)$' \
		>/dev/null; then
		echo 'Refusing: Git history contains a forbidden binary or private filename.' >&2
		exit 1
	fi
fi

if grep -RIE --exclude-dir=.git --exclude-dir=work --exclude-dir=artifacts \
	--exclude='audit-public-tree.sh' \
	"$mac_pattern" "$project" >/dev/null; then
	echo 'Refusing: literal MAC address found.' >&2
	exit 1
fi

large_files=$(find "$project" \
	\( -path "$project/.git" -o -path "$project/work" -o -path "$project/artifacts" \) \
	-prune -o -type f -size +1M -print)
[ -z "$large_files" ] || {
	echo 'Refusing: files larger than 1 MiB found in source tree:' >&2
	printf '%s\n' "$large_files" >&2
	exit 1
}

for license in Apache-2.0 BSD-3-Clause GPL-2.0-only GPL-2.0-or-later ISC; do
	test -s "$project/LICENSES/$license"
done

for patch in "$project"/patches/*.patch; do
	test "$(grep -c '^SPDX-License-Identifier:' "$patch")" -eq 1
	grep -Eq '^SPDX-License-Identifier: (Apache-2\.0|BSD-3-Clause|GPL-2\.0-only|ISC|\(GPL-2\.0-or-later OR BSD-3-Clause\))$' \
		"$patch"
done

if grep -Ev '^[[:space:]]*(#|$)' \
	"$project/overlay/etc/apk/repositories.d/distfeeds.list" >/dev/null; then
	echo 'Refusing: remote package feeds are enabled in the public overlay.' >&2
	exit 1
fi

find "$project/scripts" "$project/overlay" -type f \( \
	-name '*.sh' -o -path '*/etc/uci-defaults/*' -o -path '*/root/*' \
	-o -path '*/usr/libexec/*' -o -path '*/usr/sbin/*' \
	-o -path '*/usr/share/nwa50be/*' \
	\) -exec sh -n {} \;

if command -v shellcheck >/dev/null 2>&1; then
	find "$project/scripts" "$project/overlay" -type f \( \
		-name '*.sh' -o -path '*/etc/uci-defaults/*' -o -path '*/root/*' \
		-o -path '*/usr/libexec/*' -o -path '*/usr/sbin/*' \
		-o -path '*/usr/share/nwa50be/*' \
		\) -exec shellcheck -x {} +
fi

echo 'Public-tree audit passed.'
