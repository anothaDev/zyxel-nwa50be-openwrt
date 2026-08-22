#!/bin/sh

# Fixed-string probes below intentionally match shell source without expansion.
# shellcheck disable=SC2016

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
fdtget=$(command -v fdtget || true)
readelf=$(command -v readelf || true)

for tool in "$mkimage" "$dumpimage" "$unsquashfs" "$fdtget" "$readelf"; do
	test -x "$tool"
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

tar xf "$sysupgrade" -C "$tmp" \
	sysupgrade-zyxel_nwa50be/CONTROL \
	sysupgrade-zyxel_nwa50be/kernel \
	sysupgrade-zyxel_nwa50be/root
grep -Fxq 'BOARD=zyxel_nwa50be' "$tmp/sysupgrade-zyxel_nwa50be/CONTROL"

verify_partition() {
	dtb="$1"
	node="$2"
	label="$3"
	reg="$4"
	readonly="$5"

	test "$("$fdtget" "$dtb" "$node" label)" = "$label"
	test "$("$fdtget" -t x "$dtb" "$node" reg)" = "$reg"
	if [ "$readonly" = 1 ]; then
		"$fdtget" "$dtb" "$node" read-only >/dev/null
	elif "$fdtget" "$dtb" "$node" read-only >/dev/null 2>&1; then
		echo "Refusing: writable partition is marked read-only: $node" >&2
		exit 1
	fi
}

verify_fit_dtb() {
	name="$1"
	fit="$2"
	dtb="$tmp/$name.dtb"
	partitions='/soc@0/nand@79b0000/nandcs@0/partitions'

	"$mkimage" -l "$fit" >"$tmp/$name.fit"
	grep -Fq "Default Configuration: 'config@mi01.3'" "$tmp/$name.fit"
	"$dumpimage" -T flat_dt -p 1 -o "$dtb" "$fit" >/dev/null

	test "$("$fdtget" "$dtb" /soc@0/spi@78b5000 status)" = 'disabled'
	test "$("$fdtget" "$dtb" /soc@0/nand@79b0000 status)" = 'okay'
	test "$("$fdtget" -t x "$dtb" /soc@0/wifi2@c0000000 qcom,wide_band)" = '2'
	test "$("$fdtget" "$dtb" /chosen bootargs-append)" = \
		' mtdparts=qcom_nand.0:512k(0:TRAINING)ro,256k(0:LICENSE)ro,60m(rootfs),60m(rootfs_1)ro'

	partition_nodes=$("$fdtget" -l "$dtb" "$partitions" | LC_ALL=C sort)
	test "$partition_nodes" = "partition@0
partition@3cc0000
partition@80000
partition@c0000"

	verify_partition "$dtb" "$partitions/partition@0" \
		'0:TRAINING' '0 80000' 1
	verify_partition "$dtb" "$partitions/partition@80000" \
		'0:LICENSE' '80000 40000' 1
	verify_partition "$dtb" "$partitions/partition@c0000" \
		'rootfs' 'c0000 3c00000' 0
	verify_partition "$dtb" "$partitions/partition@3cc0000" \
		'rootfs_1' '3cc0000 3c00000' 1
}

verify_fit_dtb initramfs "$initramfs"
verify_fit_dtb persistent "$tmp/sysupgrade-zyxel_nwa50be/kernel"
cmp -s "$tmp/initramfs.dtb" "$tmp/persistent.dtb"

"$unsquashfs" -no-exit-code -d "$tmp/rootfs" \
	"$tmp/sysupgrade-zyxel_nwa50be/root" >/dev/null 2>&1

for path in \
	etc/NWA50BE_PERSISTENT_BUILD \
	etc/sysupgrade.conf \
	etc/apk/repositories.d/distfeeds.list \
	etc/init.d/qca-ssdk \
	etc/config/network etc/config/firewall etc/config/dropbear \
	etc/uci-defaults/zzzz-nwa50be-community \
	etc/modules.d/ath12k etc/init.d/ath12k_dyn_dbg_enable.sh \
	root/nwa50be-setup usr/libexec/nwa50be-management-state \
	usr/share/nwa50be/99-wireless-isolation \
	usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft \
	lib/firmware/ath12k/IPQ5332/hw1.0/caldata.bin \
	lib/firmware/ath12k/QCN6432/hw1.0/cal-ahb-soc@0:wifi2@c0000000.bin \
	sbin/sysupgrade usr/sbin/ubiformat usr/sbin/ubiupdatevol \
	www/cgi-bin/luci www/luci-static/bootstrap/cascade.css; do
	test -e "$tmp/rootfs/$path"
done

for path in \
	etc/sysupgrade.conf \
	etc/uci-defaults/zzzz-nwa50be-community \
	root/nwa50be-setup \
	usr/libexec/nwa50be-management-state; do
	cmp -s "$tmp/rootfs/$path" "$openwrt/files/$path"
done

test -e "$tmp/rootfs/usr/lib/libssl.so.3"
if "$readelf" -Ws "$tmp/rootfs/usr/lib/libssl.so.3" | \
	grep -Fq 'OSSL_QUIC_server_method'; then
	echo 'Refusing: OpenSSL QUIC server support is present.' >&2
	exit 1
fi

test ! -e "$tmp/rootfs/etc/dropbear/authorized_keys"
test -z "$(find "$tmp/rootfs" -type f -name authorized_keys -print -quit)"
test ! -e "$tmp/rootfs/sbin/mtd"
test "$(grep -c '^root:' "$tmp/rootfs/etc/shadow")" -eq 1
test -z "$(awk -F: '$1 == "root" { print $2 }' "$tmp/rootfs/etc/shadow")"
grep -Fq "option proto 'dhcp'" "$tmp/rootfs/etc/config/network"
grep -Fq "option enable '0'" "$tmp/rootfs/etc/config/dropbear"
grep -Fq "option input 'REJECT'" "$tmp/rootfs/etc/config/firewall"
grep -Fq 'for service in dnsmasq odhcpd; do' \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'for service in rpcd uhttpd; do' \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'if [ -s "$root/etc/dropbear/authorized_keys" ]; then' \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'management_state="$root/usr/libexec/nwa50be-management-state"' \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'firewall.$zone.input=REJECT' \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"
test -x "$tmp/rootfs/usr/libexec/nwa50be-management-state"
grep -Fq '[ "$prefix" -eq 32 ]' "$tmp/rootfs/root/nwa50be-setup"
grep -Fq '[ "$prefix" -eq 32 ]' \
	"$tmp/rootfs/usr/libexec/nwa50be-management-state"
grep -Fxq '/etc/nwa50be-management-cidr' \
	"$tmp/rootfs/etc/sysupgrade.conf"
grep -Fxq '/etc/nwa50be-setup-complete' \
	"$tmp/rootfs/etc/sysupgrade.conf"
grep -Fxq '/etc/dropbear/authorized_keys' \
	"$tmp/rootfs/etc/sysupgrade.conf"
grep -Fxq '/etc/shadow' "$tmp/rootfs/etc/sysupgrade.conf"
test ! -e "$tmp/rootfs/etc/nwa50be-management-cidr"
test ! -e "$tmp/rootfs/etc/nwa50be-setup-complete"
grep -Fq 'lldpd mpskd' \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq "uhttpd.main.http_keepalive='0'" \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"
if grep -Fq 'uhttpd.main.listen_http=' \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"; then
	echo 'Refusing: first-boot policy still configures cleartext HTTP.' >&2
	exit 1
fi
grep -Fq 'iifname "phy6g-ap*" drop' \
	"$tmp/rootfs/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"

grep -Eq '^uhttpd - 2026\.06\.16~7b1bec45-r1$' \
	"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"
grep -Eq '^libopenssl3 - 3\.5\.7-r1$' \
	"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"
if grep -Eq '^luci-app-package-manager ' \
	"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"; then
	echo 'Refusing: unsupported LuCI package manager is installed.' >&2
	exit 1
fi
if grep -Ev '^[[:space:]]*(#|$)' \
	"$tmp/rootfs/etc/apk/repositories.d/distfeeds.list" >/dev/null; then
	echo 'Refusing: remote package feeds are enabled.' >&2
	exit 1
fi

cmp -s "$tmp/rootfs/lib/firmware/ath12k/IPQ5332/hw1.0/caldata.bin" \
	"$openwrt/files/lib/firmware/ath12k/IPQ5332/hw1.0/caldata.bin"
cmp -s "$tmp/rootfs/lib/firmware/ath12k/QCN6432/hw1.0/cal-ahb-soc@0:wifi2@c0000000.bin" \
	"$openwrt/files/lib/firmware/ath12k/QCN6432/hw1.0/cal-ahb-soc@0:wifi2@c0000000.bin"
cmp -s "$tmp/rootfs/etc/init.d/qca-ssdk" \
	"$tree/feeds/qca-wifi-7/qca-ssdk-qca/files-zyxel_nwa50be/qca-ssdk"

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
