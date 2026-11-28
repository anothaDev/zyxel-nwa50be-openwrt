#!/bin/sh

# Fixed-string probes below intentionally match shell source without expansion.
# shellcheck disable=SC2016

set -eu

usage() {
	echo "usage: $0 <prepared-wlan-ap-directory>" >&2
	exit 2
}

[ "$#" -eq 1 ] || usage

project=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.."
	pwd
)
tree="$1"
openwrt="$tree/openwrt"
dts="$tree/feeds/qca-wifi-7/ipq53xx/dts/ipq5332-zyxel-nwa50be.dts"
overlay="$openwrt/files"

[ -f "$tree/.nwa50be-community-prepared" ]
[ "$(git -C "$tree" rev-parse HEAD)" = 'f18e1f560b50998b759a3d837a320d911d7d8584' ]
[ "$(git -C "$openwrt" rev-parse 'HEAD^{tree}')" = '6dce2f66f457d2f4de0046da03bfd0d85577aba0' ]
[ "$(git -C "$openwrt" rev-list --count a5652f421c6f6e548fb801a93b2cd2ae13eca631..HEAD)" -eq 125 ]

for feed_pin in \
	'packages:a3bd79d5bc1bcbc1edb7053fc7d4d75e3e93e1d1' \
	'luci:650a6ca36d786059aa7f85fbe0816c015c7134c1' \
	'routing:b2097c85bef85251364f59a6b2a3ed1f9f5c0c21' \
	'telephony:2618106d5846a4a542fdf5809f0d3ed228ce439b' \
	'video:094bf58da6682f895255a35a84349a79dab4bf95'; do
	feed=${feed_pin%%:*}
	pin=${feed_pin#*:}
	[ "$(git -C "$openwrt/feeds/$feed" rev-parse HEAD)" = "$pin" ]
done

actual_state=$(mktemp)
trap 'rm -f "$actual_state"' EXIT HUP INT TERM
"$project/scripts/fingerprint-prepared-tree.sh" "$tree" >"$actual_state"
if ! cmp -s "$tree/.nwa50be-community-prepared" "$actual_state"; then
	echo 'Refusing: prepared build inputs changed after preparation.' >&2
	diff -u "$tree/.nwa50be-community-prepared" "$actual_state" >&2 || true
	exit 1
fi
rm -f "$actual_state"
trap - EXIT HUP INT TERM

grep -Fq 'qcom,wide_band = <2>;' "$dts"
grep -Fq '#define __RPROC_DISABLE_MPD_SUPPORT__' "$dts"
grep -Fq 'qcom,pci_slot_id = <2>;' "$dts"
grep -Fq 'bootargs-append = " mtdparts=qcom_nand.0:512k(0:TRAINING)ro,256k(0:LICENSE)ro,60m(rootfs),60m(rootfs_1)ro";' "$dts"
grep -A2 '^&blsp1_spi0' "$dts" | grep -Fq 'status = "disabled";'
grep -A2 '^&qpic_nand' "$dts" | grep -Fq 'status = "okay";'
for entry in \
	'label = "0:TRAINING";' 'reg = <0x00000000 0x00080000>;' \
	'label = "0:LICENSE";' 'reg = <0x00080000 0x00040000>;' \
	'label = "rootfs";' 'reg = <0x000c0000 0x03c00000>;' \
	'label = "rootfs_1";' 'reg = <0x03cc0000 0x03c00000>;'; do
	grep -Fq "$entry" "$dts"
done

git -C "$tree" apply --check --reverse "$project/patches/0003-ipq53xx-fix-initramfs-extra-files-path.patch"
git -C "$tree" apply --check --reverse "$project/patches/0004-wifi-scripts-require-explicit-mlo.patch"
git -C "$tree" apply --check --reverse "$project/patches/0006-ath12k-preserve-local-module-policy.patch"
git -C "$tree" apply --check --reverse "$project/patches/0008-qca-ssdk-shell-keep-nested-build-serial.patch"
git -C "$tree" apply --check --reverse "$project/patches/0009-qca-nss-phy-ignore-empty-package-probe.patch"
git -C "$tree" apply --check --reverse "$project/patches/0015-qca-ssdk-qca-keep-profile-files-read-only.patch"
git -C "$tree" apply --check --reverse "$project/patches/0021-ath12k-balance-stale-peer-lock.patch"
git -C "$tree" apply --check --reverse "$project/patches/0024-hostapd-backport-w1fi-2026-1-mlo-validation.patch"
git -C "$tree" apply --check --reverse "$project/patches/0025-hostapd-backport-w1fi-2026-5-radius-msg-auth.patch"
git -C "$tree" apply --check --reverse "$project/patches/0038-ipq53xx-keep-pstore-disabled.patch"
git -C "$tree" apply --check --reverse "$project/patches/0046-ipq53xx-kernel-ipv4-options-rcu-free.patch"
git -C "$tree" apply --check --reverse "$project/patches/0049-zyxel-validate-hwaddr-keep-hostname.patch"
git -C "$tree" apply --check --reverse "$project/patches/0052-ipq53xx-kernel-network-fixes.patch"
git -C "$tree" apply --check --reverse "$project/patches/0061-hostapd-indicate-11be-build-feature.patch"
git -C "$tree" apply --check --reverse "$project/patches/0062-ipq53xx-kernel-tcp-lookup-and-accept-queue-followups.patch"
# Patch 0061: LuCI asks "hostapd -v11be" before it offers the BE mode.
grep -Fq '!strcmp(feat, "11be")' "$tree/feeds/qca-wifi-7/hostapd/src/src/utils/build_features.h"
# Later roll-forwards edit the same Makefiles as 0011, 0012, and 0019, so
# check the OpenWrt stack as a whole: replay it onto HEAD in a private index
# and require the work tree to match.
stack_index=$(mktemp)
trap 'rm -f "$stack_index"' EXIT HUP INT TERM
GIT_INDEX_FILE=$stack_index git -C "$openwrt" read-tree HEAD
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
	GIT_INDEX_FILE=$stack_index git -C "$openwrt" apply --cached \
		--whitespace=nowarn "$project/patches/$patch"
done
GIT_INDEX_FILE=$stack_index git -C "$openwrt" diff --quiet
rm -f "$stack_index"
trap - EXIT HUP INT TERM
sh "$project/scripts/test-tip-version.sh" "$openwrt/scripts/getver.sh"
git -C "$openwrt/feeds/packages" apply --check --reverse \
	"$project/patches/0017-packages-update-cgi-io-security.patch"
git -C "$openwrt/feeds/packages" apply --check --reverse \
	"$project/patches/0034-packages-update-curl-security.patch"
git -C "$openwrt/feeds/packages" apply --check --reverse \
	"$project/patches/0035-packages-update-nghttp2-security.patch"
git -C "$openwrt/feeds/packages" apply --check --reverse \
	"$project/patches/0037-packages-update-libssh-security.patch"
git -C "$openwrt/feeds/luci" apply --check --reverse \
	"$project/patches/0014-luci-remove-package-manager-dependency.patch"
git -C "$openwrt/feeds/luci" apply --check --reverse \
	"$project/patches/0018-luci-remove-mount-crontab-grant.patch"
git -C "$openwrt/feeds/luci" apply --check --reverse \
	"$project/patches/0020-luci-escape-dhcp-lease-fields.patch"
git -C "$openwrt/feeds/luci" apply --check --reverse \
	"$project/patches/0039-luci-use-private-ubus-connection-in-workers.patch"
git -C "$openwrt/feeds/luci" apply --check --reverse \
	"$project/patches/0055-luci-rpcd-symlink-acls-and-log-escaping.patch"
git -C "$openwrt/feeds/luci" apply --check --reverse \
	"$project/patches/0057-luci-session-token-from-urandom.patch"
git -C "$openwrt/feeds/luci" apply --check --reverse \
	"$project/patches/0063-luci-rpcd-acls-for-bridge-ports-and-busybox-links.patch"
git -C "$tree" diff --check
git -C "$openwrt" diff --check
git -C "$openwrt/feeds/packages" diff --check
git -C "$openwrt/feeds/luci" diff --check
git -C "$tree" diff --quiet HEAD -- \
	feeds/qca-wifi-7/qca-ssdk-qca/files/qca-ssdk

cmp -s "$project/patches/0007-ucode-fix-const-string-pointers.patch" \
	"$openwrt/package/utils/ucode/patches/130-fix-const-string-pointers.patch"
diff -qr "$project/overlay" "$overlay" -x lib
for script in 99-ucentral-network zzz-ucentral; do
	test -f "$overlay/etc/uci-defaults/$script"
	cmp -s "$project/overlay/etc/uci-defaults/$script" \
		"$overlay/etc/uci-defaults/$script"
done
test -z "$(find "$overlay" -type l -print -quit)"

calibration_files=$(find "$overlay/lib" -type f -printf '%P\n' | sort)
[ "$calibration_files" = "firmware/ath12k/IPQ5332/hw1.0/caldata.bin
firmware/ath12k/QCN6432/hw1.0/cal-ahb-soc@0:wifi2@c0000000.bin" ]

test "$(wc -c <"$overlay/lib/firmware/ath12k/IPQ5332/hw1.0/caldata.bin")" -eq 131072
test "$(wc -c <"$overlay/lib/firmware/ath12k/QCN6432/hw1.0/cal-ahb-soc@0:wifi2@c0000000.bin")" -eq 184320
test ! -e "$overlay/etc/dropbear/authorized_keys"
grep -Eq '^root::[0-9]+:' "$openwrt/package/base-files/files/etc/shadow"
grep -Fq "option proto 'dhcp'" "$overlay/etc/config/network"
grep -Fq "option enable '0'" "$overlay/etc/config/dropbear"
grep -Fq "option input 'REJECT'" "$overlay/etc/config/firewall"
grep -Fq 'for service in dnsmasq odhcpd; do' \
	"$overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'for service in rpcd uhttpd; do' \
	"$overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'if [ -s "$root/etc/dropbear/authorized_keys" ]; then' \
	"$overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'management_state="$root/usr/libexec/nwa50be-management-state"' \
	"$overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'firewall.$zone.input=REJECT' \
	"$overlay/etc/uci-defaults/zzzz-nwa50be-community"
test -x "$overlay/usr/libexec/nwa50be-management-state"
test -x "$overlay/usr/sbin/nwa50be-sysupgrade"
grep -Fq '"$sysupgrade_bin" -T -f "$backup" "$image"' \
	"$overlay/usr/sbin/nwa50be-sysupgrade"
grep -Fq '[ "$prefix" -eq 32 ]' "$overlay/root/nwa50be-setup"
grep -Fq '[ "$prefix" -eq 32 ]' \
	"$overlay/usr/libexec/nwa50be-management-state"
grep -Fxq '/etc/nwa50be-management-cidr' "$overlay/etc/sysupgrade.conf"
grep -Fxq '/etc/nwa50be-setup-complete' "$overlay/etc/sysupgrade.conf"
grep -Fxq '/etc/dropbear/authorized_keys' "$overlay/etc/sysupgrade.conf"
grep -Fxq '/etc/shadow' "$overlay/etc/sysupgrade.conf"
grep -Fq 'printf '\''%s\n'\'' "$management_cidr" >/etc/nwa50be-management-cidr' \
	"$overlay/root/nwa50be-setup"
grep -Fq 'lldpd mpskd' "$overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'sha256sum 2>/dev/null | cut -c1-8' \
	"$overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'if [ -n "$soc_serial" ]; then' \
	"$overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq "uhttpd.main.http_keepalive='0'" \
	"$overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq "uhttpd.main.ucode_prefix='/cgi-bin/luci=/usr/share/ucode/luci/uhttpd.uc'" \
	"$overlay/etc/uci-defaults/zzzz-nwa50be-community"
test -f "$overlay/etc/apk/repositories.d/distfeeds.list"
if grep -Ev '^[[:space:]]*(#|$)' \
	"$overlay/etc/apk/repositories.d/distfeeds.list" >/dev/null; then
	echo 'Refusing: remote package feeds are enabled.' >&2
	exit 1
fi
test -f "$overlay/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fq 'hook ingress device eth0 priority -500' \
	"$overlay/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fq 'meta mark set meta mark | 0x40000000' \
	"$overlay/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fq 'hook input priority -10' \
	"$overlay/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fq 'meta mark & 0x40000000 == 0 drop' \
	"$overlay/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fxq 'destroy table bridge nwa50be_management' \
	"$overlay/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fxq 'ath12k frame_mode=1 cold_boot_cal=0 mlo_capable=0' \
	"$overlay/etc/modules.d/ath12k"

grep -q '^PKG_SOURCE_VERSION:=93b05e0b65d91c23c5aa8fdde378df1f174ec71d$' \
	"$openwrt/package/network/services/uhttpd/Makefile"
grep -q '^PKG_VERSION:=3.5.9$' "$openwrt/package/libs/openssl/Makefile"
grep -q '^PKG_SOURCE_VERSION:=d99f703e4035d03fbcfbada3cb697db346c2b984$' \
	"$openwrt/package/system/rpcd/Makefile"
grep -q '^PKG_SOURCE_VERSION:=ff13b89e82e64cdd7853419504e51ec0c7e487e0$' \
	"$openwrt/package/libs/libubox/Makefile"
grep -q '^PKG_VERSION:=20260816$' "$openwrt/package/system/ca-certificates/Makefile"
test -f "$openwrt/toolchain/musl/patches/008-regex-avoid-int-overflow-in-regcomp.patch"
if grep -q 'cipher_aes_gcm_siv' \
	"$openwrt/package/libs/openssl/patches/010-fix-aes-gcm-siv-cipher.patch" 2>/dev/null; then
	echo 'Refusing: OpenSSL patch 010 still reverts the 3.5.8 AES-GCM-SIV fix.' >&2
	exit 1
fi
grep -q '^OPENSSL_OPTIONS:= shared no-tests no-quic$' \
	"$openwrt/package/libs/openssl/Makefile"
grep -q '^PKG_SOURCE_VERSION:=31cb3c89f02d918d7f17bf62a80c852fc38a1ca1$' \
	"$openwrt/feeds/packages/net/cgi-io/Makefile"
grep -q '^PKG_SOURCE_VERSION:=defe7ccfd20281b9ef4dfa45437813386a64f8ba$' \
	"$openwrt/package/network/services/umdns/Makefile"
grep -q '^PKG_SOURCE_VERSION:=58eb263d5abe03f8c1280bdfa65a3b052614215d$' \
	"$openwrt/package/system/procd/Makefile"
grep -q '^PKG_SOURCE_VERSION:=b9034210bd331749673416c6bf389cccd4e23610$' \
	"$openwrt/package/utils/jsonfilter/Makefile"
grep -q '^PKG_SOURCE_VERSION:=e2934931479fe732f076e8e32d551b4042bd06d6$' \
	"$tree/feeds/ucentral/ucentral-schema/Makefile"
grep -Fq 'config_add_string uci_section' \
	"$tree/feeds/qca-wifi-7/wifi-scripts/files/lib/netifd/hostapd.sh"

test -f "$tree/feeds/qca-wifi-7/hostapd/openwrt-patches/services/hostapd/patches/zz-001-hostapd-w1fi-2026-1-mlo-validation.patch"
if grep -q '^CONFIG_PSTORE' "$tree/feeds/qca-wifi-7/ipq53xx/config-6.6"; then
	echo 'Refusing: pstore is enabled in the ipq53xx kernel configuration.' >&2
	exit 1
fi

"$project/scripts/check-luci-mount-acl.py" \
	"$openwrt/feeds/luci/modules/luci-mod-system/root/usr/share/rpcd/acl.d/luci-mod-system.json"
test "$(grep -Fo "'%h'.format(host || '-')" \
	"$openwrt/feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/dhcp.js" | \
	wc -l)" -eq 2
test "$(grep -Fo "'%h'.format(host || '-')" \
	"$openwrt/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/40_dhcp.js" | \
	wc -l)" -eq 2
grep -Fq 'document.createTextNode(`${res?.ssid}`)' \
	"$openwrt/feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js"

grep -q '^CONFIG_TARGET_ROOTFS_INITRAMFS=y$' "$openwrt/.config"
grep -q '^CONFIG_TARGET_ROOTFS_SQUASHFS=y$' "$openwrt/.config"
grep -q '^# CONFIG_PACKAGE_odhcpd is not set$' "$openwrt/.config"
grep -q '^# CONFIG_PACKAGE_odhcpd-ipv6only is not set$' "$openwrt/.config"
grep -q '^CONFIG_PACKAGE_luci-ssl-openssl=y$' "$openwrt/.config"
grep -q '^# CONFIG_PACKAGE_luci-app-package-manager is not set$' "$openwrt/.config"
grep -q '^# CONFIG_PACKAGE_mtd is not set$' "$openwrt/.config"
grep -q '^# CONFIG_PACKAGE_uboot-envtools is not set$' "$openwrt/.config"
grep -q '^CONFIG_KERNEL_BUILD_USER="nwa50be"$' "$openwrt/.config"
grep -q '^CONFIG_KERNEL_BUILD_DOMAIN="local"$' "$openwrt/.config"
for symbol in \
	CONFIG_PACKAGE_kmod-qca-nss-ecm-premium \
	CONFIG_PACKAGE_kmod-qca-nss-ecm-wifi-plugin \
	CONFIG_PACKAGE_cig-device-boot \
	CONFIG_PACKAGE_kmod-usb-serial-xr; do
	if grep -q "^${symbol}=y$" "$openwrt/.config"; then
		echo "Refusing: unsupported package is selected: $symbol" >&2
		exit 1
	fi
done
for symbol in \
	CONFIG_PACKAGE_bridger \
	CONFIG_PACKAGE_kmod-sched-bpf \
	CONFIG_PACKAGE_lldpd \
	CONFIG_PACKAGE_qosify \
	CONFIG_PACKAGE_spotfilter \
	CONFIG_PACKAGE_ucode-mod-bpf \
	CONFIG_PACKAGE_udevstats \
	CONFIG_PACKAGE_ufp \
	CONFIG_PACKAGE_uspot; do
	grep -q "^# ${symbol} is not set$" "$openwrt/.config"
done

find "$project/overlay" -type f \( \
	-name '*.sh' -o -path '*/etc/uci-defaults/*' -o -path '*/root/*' \
	-o -path '*/usr/libexec/*' -o -path '*/usr/share/nwa50be/*' \
	\) -exec sh -n {} \;

echo 'Prepared tree verification passed.'
