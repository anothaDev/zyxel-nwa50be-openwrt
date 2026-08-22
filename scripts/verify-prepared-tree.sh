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
[ "$(git -C "$tree" rev-parse HEAD)" = '122d893d88a6762bffeac54c5f87b37407cefe7a' ]
[ "$(git -C "$openwrt" rev-parse 'HEAD^{tree}')" = 'a0fa511453f26becffbde594f46103ab9bad57a7' ]
[ "$(git -C "$openwrt" rev-list --count a5652f421c6f6e548fb801a93b2cd2ae13eca631..HEAD)" -eq 124 ]

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
git -C "$openwrt" apply --check --reverse "$project/patches/0002-openwrt-refresh-initramfs-payload.patch"
git -C "$openwrt" apply --check --reverse "$project/patches/0010-openwrt-neutralize-external-apk-origin.patch"
git -C "$openwrt" apply --check --reverse "$project/patches/0011-openwrt-update-uhttpd-security.patch"
git -C "$openwrt" apply --check --reverse "$project/patches/0012-openwrt-update-openssl-3.5.7.patch"
git -C "$openwrt" apply --check --reverse "$project/patches/0013-openwrt-remove-default-root-password.patch"
git -C "$openwrt" apply --check --reverse "$project/patches/0016-openssl-disable-unused-quic.patch"
git -C "$openwrt/feeds/luci" apply --check --reverse \
	"$project/patches/0014-luci-remove-package-manager-dependency.patch"
git -C "$tree" diff --check
git -C "$openwrt" diff --check
git -C "$openwrt/feeds/luci" diff --check
git -C "$tree" diff --quiet HEAD -- \
	feeds/qca-wifi-7/qca-ssdk-qca/files/qca-ssdk

cmp -s "$project/patches/0007-ucode-fix-const-string-pointers.patch" \
	"$openwrt/package/utils/ucode/patches/130-fix-const-string-pointers.patch"
diff -qr "$project/overlay" "$overlay" -x lib
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
test -f "$overlay/etc/apk/repositories.d/distfeeds.list"
if grep -Ev '^[[:space:]]*(#|$)' \
	"$overlay/etc/apk/repositories.d/distfeeds.list" >/dev/null; then
	echo 'Refusing: remote package feeds are enabled.' >&2
	exit 1
fi
test -f "$overlay/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fq 'iifname "phy6g-ap*" drop' \
	"$overlay/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fxq 'ath12k frame_mode=1 cold_boot_cal=0 mlo_capable=0' \
	"$overlay/etc/modules.d/ath12k"

grep -q '^PKG_SOURCE_VERSION:=7b1bec45826bd78c8afc993435bdc0f1df2fe399$' \
	"$openwrt/package/network/services/uhttpd/Makefile"
grep -q '^PKG_VERSION:=3.5.7$' "$openwrt/package/libs/openssl/Makefile"
grep -q '^OPENSSL_OPTIONS:= shared no-tests no-quic$' \
	"$openwrt/package/libs/openssl/Makefile"

grep -q '^CONFIG_TARGET_ROOTFS_INITRAMFS=y$' "$openwrt/.config"
grep -q '^CONFIG_TARGET_ROOTFS_SQUASHFS=y$' "$openwrt/.config"
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
