#!/bin/sh

set -eu

usage() {
	echo "usage: $0 <prepared-wlan-ap-directory> <artifact-directory>" >&2
	exit 2
}

[ "$#" -eq 2 ] || usage

tree="$1"
stage="$2"
openwrt="$tree/openwrt"

initramfs="$stage/openwrt-ipq53xx-zyxel_nwa50be-initramfs-kernel.bin"
factory="$stage/openwrt-ipq53xx-zyxel_nwa50be-squashfs-nand-factory.bin"
ubi="$stage/openwrt-ipq53xx-zyxel_nwa50be-squashfs-nand-factory.ubi"
sysupgrade="$stage/openwrt-ipq53xx-zyxel_nwa50be-squashfs-sysupgrade.tar"

(
	cd "$stage"
	sha256sum -c SHA256SUMS
)

for file in "$initramfs" "$factory" "$ubi" "$sysupgrade"; do
	test -s "$file"
done

ubi_size=$(wc -c <"$ubi")
test "$ubi_size" -lt 62914560
test $((ubi_size % 131072)) -eq 0

mkimage="$openwrt/staging_dir/host/bin/mkimage"
dumpimage=$(find "$openwrt/build_dir/host" -path '*/tools/dumpimage' -type f | head -n 1)
unsquashfs=$(find "$openwrt/build_dir/host" -path '*/squashfs-tools/unsquashfs' -type f | head -n 1)
dtc=$(find "$openwrt/build_dir" -path '*/scripts/dtc/dtc' -type f | head -n 1)

for tool in "$mkimage" "$dumpimage" "$unsquashfs" "$dtc"; do
	test -x "$tool"
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

"$mkimage" -l "$initramfs" >"$tmp/initramfs.fit"
grep -Fq "Default Configuration: 'config@mi01.3'" "$tmp/initramfs.fit"
"$dumpimage" -T flat_dt -p 1 -o "$tmp/persistent.dtb" "$initramfs" >/dev/null
"$dtc" -I dtb -O dts -o "$tmp/persistent.dts" "$tmp/persistent.dtb" 2>/dev/null
grep -Fq 'qcom,wide_band = <0x02>;' "$tmp/persistent.dts"
grep -Fq 'bootargs-append = " mtdparts=qcom_nand.0:512k(0:TRAINING)ro,256k(0:LICENSE)ro,60m(rootfs),60m(rootfs_1)ro";' "$tmp/persistent.dts"
grep -A25 'spi@78b5000' "$tmp/persistent.dts" | grep -Fq 'status = "disabled";'
grep -A25 'nand@79b0000' "$tmp/persistent.dts" | grep -Fq 'status = "okay";'

tar xf "$sysupgrade" -C "$tmp" \
	sysupgrade-zyxel_nwa50be/CONTROL \
	sysupgrade-zyxel_nwa50be/kernel \
	sysupgrade-zyxel_nwa50be/root
"$unsquashfs" -no-exit-code -d "$tmp/rootfs" \
	"$tmp/sysupgrade-zyxel_nwa50be/root" >/dev/null 2>&1

for path in \
	etc/NWA50BE_PERSISTENT_BUILD \
	etc/config/network etc/config/firewall etc/config/dropbear \
	etc/uci-defaults/zzzz-nwa50be-community \
	etc/modules.d/ath12k etc/init.d/ath12k_dyn_dbg_enable.sh \
	root/nwa50be-setup usr/share/nwa50be/99-wireless-isolation \
	lib/firmware/ath12k/IPQ5332/hw1.0/caldata.bin \
	lib/firmware/ath12k/QCN6432/hw1.0/cal-ahb-soc@0:wifi2@c0000000.bin \
	sbin/sysupgrade usr/sbin/ubiformat usr/sbin/ubiupdatevol \
	www/cgi-bin/luci www/luci-static/bootstrap/cascade.css; do
	test -e "$tmp/rootfs/$path"
done

test ! -e "$tmp/rootfs/etc/dropbear/authorized_keys"
test -z "$(find "$tmp/rootfs" -type f -name authorized_keys -print -quit)"
test ! -e "$tmp/rootfs/sbin/mtd"
grep -Fq "option proto 'dhcp'" "$tmp/rootfs/etc/config/network"
grep -Fq "option enable '0'" "$tmp/rootfs/etc/config/dropbear"
grep -Fq 'for service in dnsmasq odhcpd dropbear rpcd uhttpd' \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'lldpd mpskd' \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"

cmp -s "$tmp/rootfs/lib/firmware/ath12k/IPQ5332/hw1.0/caldata.bin" \
	"$openwrt/files/lib/firmware/ath12k/IPQ5332/hw1.0/caldata.bin"
cmp -s "$tmp/rootfs/lib/firmware/ath12k/QCN6432/hw1.0/cal-ahb-soc@0:wifi2@c0000000.bin" \
	"$openwrt/files/lib/firmware/ath12k/QCN6432/hw1.0/cal-ahb-soc@0:wifi2@c0000000.bin"

"$dumpimage" -T flat_dt -p 0 -o "$tmp/factory.ubi" "$factory" >/dev/null
cmp -s "$tmp/factory.ubi" "$ubi"

bad_ec=0
peb_count=$((ubi_size / 131072))
for n in $(seq 0 $((peb_count - 1))); do
	magic=$(dd if="$ubi" bs=1 skip=$((n * 131072)) count=4 status=none | \
		od -An -tx1 | tr -d ' \n')
	[ "$magic" = '55424923' ] || bad_ec=$((bad_ec + 1))
done
test "$bad_ec" -eq 0

for name in kernel ubi_rootfs rootfs_data; do
	strings -a "$ubi" | grep -Fxq "$name"
done

if { strings -a "$initramfs" "$factory" "$sysupgrade"; \
	find "$tmp/rootfs" -type f -exec strings -a {} +; } | \
	grep -Ea '/home/[^/:[:space:]]+/|/Users/[^/:[:space:]]+/|[A-Za-z]:\\Users\\[^\\:[:space:]]+\\|@omarchy' \
	>/dev/null; then
	echo 'Refusing: artifact strings contain private build metadata.' >&2
	exit 1
fi

private_key_files=$(
	find "$tmp/rootfs" -type f \
		-exec grep -IlE '^-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----$' {} + || true
)
if [ -n "$private_key_files" ]; then
	echo 'Refusing: rootfs contains a text private-key file.' >&2
	printf '%s\n' "$private_key_files" >&2
	exit 1
fi

echo "Artifact verification passed: $peb_count PEBs, $ubi_size-byte UBI."
