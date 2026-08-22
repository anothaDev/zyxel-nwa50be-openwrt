#!/bin/sh

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
[ "$(cat "$tree/.nwa50be-community-prepared")" = '122d893d88a6762bffeac54c5f87b37407cefe7a' ]
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
git -C "$openwrt" apply --check --reverse "$project/patches/0002-openwrt-refresh-initramfs-payload.patch"
git -C "$openwrt" apply --check --reverse "$project/patches/0010-openwrt-neutralize-external-apk-origin.patch"
git -C "$tree" diff --check
git -C "$openwrt" diff --check

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
grep -Fq "option proto 'dhcp'" "$overlay/etc/config/network"
grep -Fq "option enable '0'" "$overlay/etc/config/dropbear"
grep -Fq 'for service in dnsmasq odhcpd dropbear rpcd uhttpd' \
	"$overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'lldpd mpskd' "$overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'sha256sum 2>/dev/null | cut -c1-8' \
	"$overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fxq 'ath12k frame_mode=1 cold_boot_cal=0 mlo_capable=0' \
	"$overlay/etc/modules.d/ath12k"

grep -q '^CONFIG_TARGET_ROOTFS_INITRAMFS=y$' "$openwrt/.config"
grep -q '^CONFIG_TARGET_ROOTFS_SQUASHFS=y$' "$openwrt/.config"
grep -q '^CONFIG_PACKAGE_luci-ssl-openssl=y$' "$openwrt/.config"
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

find "$project/overlay" -type f \( -name '*.sh' -o -path '*/etc/uci-defaults/*' -o -path '*/root/*' \) \
	-exec sh -n {} \;

echo 'Prepared tree verification passed.'
