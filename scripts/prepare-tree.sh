#!/bin/sh

set -eu

usage() {
	echo "usage: $0 <new-or-exact-upstream-wlan-ap-directory> <private-art.bin>" >&2
	exit 2
}

[ "$#" -eq 2 ] || usage

project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tree="$1"
art="$2"

tip_url='https://github.com/Telecominfraproject/wlan-ap.git'
tip_commit='122d893d88a6762bffeac54c5f87b37407cefe7a'
openwrt_patched_tree='a0fa511453f26becffbde594f46103ab9bad57a7'

verify_upstream_state() {
	[ ! -e "$tree/.nwa50be-community-prepared" ]
	[ "$(git -C "$tree" rev-parse HEAD)" = "$tip_commit" ]
	[ "$(git -C "$tree/openwrt" rev-parse HEAD^{tree})" = "$openwrt_patched_tree" ]
	[ "$(git -C "$tree/openwrt" rev-list --count a5652f421c6f6e548fb801a93b2cd2ae13eca631..HEAD)" -eq 124 ]

	root_status=$(git -C "$tree" status --porcelain --untracked-files=all)
	[ -z "$root_status" ] || {
		echo 'Refusing: TIP checkout is not clean.' >&2
		printf '%s\n' "$root_status" >&2
		exit 1
	}

	openwrt_status=$(git -C "$tree/openwrt" status --porcelain --untracked-files=all)
	[ "$openwrt_status" = '?? profiles' ] || {
		echo 'Refusing: nested OpenWrt checkout has unexpected changes.' >&2
		printf '%s\n' "$openwrt_status" >&2
		exit 1
	}
	[ -L "$tree/openwrt/profiles" ]
	[ "$(readlink "$tree/openwrt/profiles")" = '../profiles' ]
}

for command in git python3 rsync make readlink sha256sum; do
	command -v "$command" >/dev/null 2>&1 || {
		echo "Missing required command: $command" >&2
		exit 1
	}
done

python3 -c 'import yaml' >/dev/null 2>&1 || {
	echo 'Missing required Python module: yaml (PyYAML)' >&2
	exit 1
}

if [ -e "$tree" ]; then
	[ -d "$tree/.git" ]
	[ -d "$tree/openwrt/.git" ]
	verify_upstream_state
	echo "Resuming exact prepared upstream state: $tree"
else
	mkdir -p "$(dirname "$tree")"
	git clone --filter=blob:none --no-checkout "$tip_url" "$tree"
	git -C "$tree" checkout --detach "$tip_commit"

	(
		cd "$tree"
		export GIT_COMMITTER_NAME='NWA50BE build import'
		export GIT_COMMITTER_EMAIL='noreply@invalid.example'
		python3 setup.py --setup
	)
fi

verify_upstream_state

for patch in \
	0001-nwa50be-ramtest-disable-flash.patch \
	0003-ipq53xx-fix-initramfs-extra-files-path.patch \
	0004-wifi-scripts-require-explicit-mlo.patch \
	0005-nwa50be-enable-nand-keep-spi-locked.patch \
	0006-ath12k-preserve-local-module-policy.patch \
	0008-qca-ssdk-shell-keep-nested-build-serial.patch \
	0009-qca-nss-phy-ignore-empty-package-probe.patch; do
	git -C "$tree" apply --check "$project/patches/$patch"
	git -C "$tree" apply "$project/patches/$patch"
done

for patch in \
	0002-openwrt-refresh-initramfs-payload.patch \
	0010-openwrt-neutralize-external-apk-origin.patch; do
	git -C "$tree/openwrt" apply --check "$project/patches/$patch"
	git -C "$tree/openwrt" apply "$project/patches/$patch"
done

mkdir -p "$tree/openwrt/package/utils/ucode/patches"
cp "$project/patches/0007-ucode-fix-const-string-pointers.patch" \
	"$tree/openwrt/package/utils/ucode/patches/130-fix-const-string-pointers.patch"

(
	cd "$tree/openwrt"
	./scripts/gen_config.py zyxel_nwa50be
	./scripts/feeds install \
		luci-ssl-openssl luci-theme-bootstrap luci-mod-admin-full \
		luci-mod-network luci-mod-status luci-mod-system \
		luci-app-firewall luci-app-package-manager
)

"$project/scripts/apply-config-seed.sh" \
	"$tree/openwrt" "$project/config/nwa50be.seed"

mkdir -p "$tree/openwrt/files"
rsync -a --delete "$project/overlay/" "$tree/openwrt/files/"
"$project/scripts/inject-calibration.sh" "$art" "$tree/openwrt/files"

printf '%s\n' "$tip_commit" >"$tree/.nwa50be-community-prepared"

"$project/scripts/verify-prepared-tree.sh" "$tree"

echo "Prepared pinned build tree: $tree"
