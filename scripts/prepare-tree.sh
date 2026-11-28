#!/bin/sh

set -eu

usage() {
	echo "usage: $0 <new-or-exact-upstream-wlan-ap-directory> <private-art.bin>" >&2
	exit 2
}

[ "$#" -eq 2 ] || usage

project=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.."
	pwd
)
tree="$1"
art="$2"

tip_url='https://github.com/Telecominfraproject/wlan-ap.git'
tip_commit='f18e1f560b50998b759a3d837a320d911d7d8584'
openwrt_patched_tree='6dce2f66f457d2f4de0046da03bfd0d85577aba0'

verify_upstream_state() {
	[ ! -e "$tree/.nwa50be-community-prepared" ]
	[ "$(git -C "$tree" rev-parse HEAD)" = "$tip_commit" ]
	[ "$(git -C "$tree/openwrt" rev-parse 'HEAD^{tree}')" = "$openwrt_patched_tree" ]
	[ "$(git -C "$tree/openwrt" rev-list --count a5652f421c6f6e548fb801a93b2cd2ae13eca631..HEAD)" -eq 125 ]

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
	0009-qca-nss-phy-ignore-empty-package-probe.patch \
	0015-qca-ssdk-qca-keep-profile-files-read-only.patch \
	0021-ath12k-balance-stale-peer-lock.patch \
	0024-hostapd-backport-w1fi-2026-1-mlo-validation.patch \
	0025-hostapd-backport-w1fi-2026-5-radius-msg-auth.patch \
	0038-ipq53xx-keep-pstore-disabled.patch \
	0046-ipq53xx-kernel-ipv4-options-rcu-free.patch \
	0049-zyxel-validate-hwaddr-keep-hostname.patch \
	0052-ipq53xx-kernel-network-fixes.patch \
	0061-hostapd-indicate-11be-build-feature.patch \
	0062-ipq53xx-kernel-tcp-lookup-and-accept-queue-followups.patch; do
	git -C "$tree" apply --check "$project/patches/$patch"
	git -C "$tree" apply "$project/patches/$patch"
done

for patch in \
	0002-openwrt-refresh-initramfs-payload.patch \
	0010-openwrt-neutralize-external-apk-origin.patch \
	0011-openwrt-update-uhttpd-security.patch \
	0012-openwrt-update-openssl-3.5.8.patch \
	0013-openwrt-remove-default-root-password.patch \
	0016-openssl-disable-unused-quic.patch \
	0019-openwrt-update-umdns-security.patch \
	0022-openwrt-select-one-tip-release-label.patch \
	0026-openwrt-update-openssl-3.5.9.patch \
	0027-openwrt-update-uhttpd-security.patch \
	0028-openwrt-update-umdns-memory-safety.patch \
	0029-openwrt-backport-dropbear-security.patch \
	0030-openwrt-busybox-security-backports.patch \
	0031-openwrt-update-dnsmasq-2.93.patch \
	0032-openwrt-update-mbedtls-3.6.7.patch \
	0033-openwrt-update-libpcap-1.10.7.patch \
	0036-openwrt-update-libevent2-security.patch \
	0040-toolchain-musl-backport-cve-2026-6042-40200.patch \
	0041-openwrt-dnsmasq-october-2026-security.patch \
	0042-openwrt-dropbear-2026-92-93-security.patch \
	0043-openwrt-busybox-udhcpc-and-tar-fixes.patch \
	0044-openwrt-zlib-reject-negative-crc32-combine.patch \
	0045-openwrt-dnsmasq-post-2.93-security-fixes.patch \
	0047-openwrt-dropbear-2026.94.patch \
	0048-openwrt-dnsmasq-november-2026-security.patch \
	0050-openwrt-rpcd-update-2026-10-04.patch \
	0051-openwrt-ca-certificates-20260816.patch \
	0053-toolchain-musl-regcomp-cve-2026-107891.patch \
	0054-openwrt-uhttpd-update-2026-11-05.patch \
	0056-openwrt-libubox-update-2026-11-03.patch \
	0058-openwrt-dnsmasq-cache-soa-and-non-address-records.patch \
	0059-openwrt-busybox-nslookup-length-checks.patch \
	0060-openwrt-mbedtls-update-3.6.8.patch; do
	git -C "$tree/openwrt" apply --check "$project/patches/$patch"
	git -C "$tree/openwrt" apply "$project/patches/$patch"
done

mkdir -p "$tree/openwrt/package/utils/ucode/patches"
cp "$project/patches/0007-ucode-fix-const-string-pointers.patch" \
	"$tree/openwrt/package/utils/ucode/patches/130-fix-const-string-pointers.patch"

(
	cd "$tree/openwrt"
	./scripts/gen_config.py zyxel_nwa50be
	for patch in \
		0017-packages-update-cgi-io-security.patch \
		0034-packages-update-curl-security.patch \
		0035-packages-update-nghttp2-security.patch \
		0037-packages-update-libssh-security.patch; do
		git -C feeds/packages apply --check "$project/patches/$patch"
		git -C feeds/packages apply "$project/patches/$patch"
	done
	for patch in \
		0014-luci-remove-package-manager-dependency.patch \
		0018-luci-remove-mount-crontab-grant.patch \
		0020-luci-escape-dhcp-lease-fields.patch \
		0039-luci-use-private-ubus-connection-in-workers.patch \
		0055-luci-rpcd-symlink-acls-and-log-escaping.patch \
		0057-luci-session-token-from-urandom.patch \
		0063-luci-rpcd-acls-for-bridge-ports-and-busybox-links.patch; do
		git -C feeds/luci apply --check "$project/patches/$patch"
		git -C feeds/luci apply "$project/patches/$patch"
	done
	./scripts/feeds install \
		luci-ssl-openssl luci-theme-bootstrap luci-mod-admin-full \
		luci-mod-network luci-mod-status luci-mod-system \
		luci-app-firewall
)

"$project/scripts/apply-config-seed.sh" \
	"$tree/openwrt" "$project/config/nwa50be.seed"

mkdir -p "$tree/openwrt/files"
rsync -a --delete "$project/overlay/" "$tree/openwrt/files/"
"$project/scripts/inject-calibration.sh" "$art" "$tree/openwrt/files"

state_file="$tree/.nwa50be-community-prepared"
state_tmp=$(mktemp)
trap 'rm -f "$state_tmp"' EXIT HUP INT TERM
"$project/scripts/fingerprint-prepared-tree.sh" "$tree" >"$state_tmp"
mv "$state_tmp" "$state_file"
trap - EXIT HUP INT TERM

"$project/scripts/verify-prepared-tree.sh" "$tree"

echo "Prepared pinned build tree: $tree"
