#!/bin/sh

# Fixed-string probes below intentionally match shell source without expansion.
# shellcheck disable=SC2016

set -eu

project=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.."
	pwd
)

usage() {
	echo "usage: $0 <prepared-wlan-ap-directory> <artifact-directory>" >&2
	exit 2
}

[ "$#" -eq 2 ] || usage

tree="$1"
stage="$2"
openwrt="$tree/openwrt"

# Execute the reviewed collision block from the actual prepared driver source.
# This models lock/BH balance, not firmware timing or complete station teardown.
python3 "$project/scripts/test-ath12k-peer-lock.py" \
	"$openwrt/build_dir/target-aarch64_cortex-a53+neon-vfpv4_musl/linux-ipq53xx_generic/backports-6.6.15/drivers/net/wireless/ath/ath12k/peer.c"

# Patch 0061: the feature query must know 802.11be in the source the wpad
# binary was built from, and the build must have 802.11be enabled.
grep -Fq '!strcmp(feat, "11be")' \
	"$openwrt/build_dir/target-aarch64_cortex-a53+neon-vfpv4_musl/hostapd-wpad-full-openssl/hostapd-2025.03.10~95ad7115/src/utils/build_features.h"
grep -Fxq 'CONFIG_IEEE80211BE=y' \
	"$openwrt/build_dir/target-aarch64_cortex-a53+neon-vfpv4_musl/hostapd-wpad-full-openssl/hostapd-2025.03.10~95ad7115/hostapd/.config"

# Patches 0040 to 0045: check the sources the binaries were built from.
btarget="$openwrt/build_dir/target-aarch64_cortex-a53+neon-vfpv4_musl"
musl="$openwrt/build_dir/toolchain-aarch64_cortex-a53+neon-vfpv4_gcc-14.3.0_musl/musl-1.2.5"
grep -Fq 'if (p[0] != 1) return ntz(p[0] - 1);' "$musl/src/stdlib/qsort.c"
grep -Fq 'c<gb18030utf[i][1]' "$musl/src/locale/iconv.c"
test "$(grep -Fc 'if (len2 < 0)' "$btarget/zlib-1.3.1/crc32.c")" -eq 2
# Patch 010 adds a fifth restore of the stashed query (pristine 2.93 has four).
test "$(grep -Fc 'blockdata_retrieve(forward->stash, forward->stash_len, (void *)header)' \
	"$btarget/dnsmasq-full/dnsmasq-2.93/src/forward.c")" -eq 5
# Patch 0048: upstream 021 (DS loop), 022 (accept() spin) and our 026
# (CVE-2026-93010, leasequery fails closed without a permitted source).
dnsmasq_src="$btarget/dnsmasq-full/dnsmasq-2.93"
grep -Fq 'if (STAT_ISEQUAL(rc, STAT_NEED_DS) && hostname_isequal(name, keyname))' \
	"$dnsmasq_src/src/dnssec.c"
grep -Fq '/* Transient errors: just return and retry on next poll cycle. */' \
	"$dnsmasq_src/src/dnsmasq.c"
grep -Fq 'no permitted source given to --leasequery (logged only once)' \
	"$dnsmasq_src/src/rfc2131.c"
# Patch 0058 (upstream 10fbc39): zero-length blockdata allocations succeed.
test -f "$openwrt/package/network/services/dnsmasq/patches/027-Return-an-empty-block-from-blockdata_alloc-for-zero-length.patch"
awk '
	/^  if \(len == 0\)$/ { getline; if ($0 ~ /^    return new_block\(\);$/) ok = 1 }
	END { exit ok ? 0 : 1 }
' "$dnsmasq_src/src/blockdata.c"
# Patch 0047: dropbear 2026.94 (curve25519 S < L check, CVE-2026-3706) plus
# upstream 59870ad4 (channel max packet) and 17549ea6 (scp escaping).
dropbear_src="$btarget/dropbear-2026.94"
grep -Fq '#define MAX_AUTHKEYS_LINE 3000' "$dropbear_src/src/svr-authpubkey.c"
grep -Fq 'static int s_lt_l(const u8 *s) {' "$dropbear_src/src/curve25519.c"
grep -Fq 'channel->transmaxpacket = MAX(channel->transmaxpacket, 1);' \
	"$dropbear_src/src/common-channel.c"
grep -Fq 'static void cleantext(char* dirtytext, int allow_whitespace) {' \
	"$dropbear_src/src/scp.c"
grep -Fq 'cleantext(&buf[1], 0);' "$dropbear_src/src/scp.c"
busybox_src="$btarget/busybox-default/busybox-1.37.0"
test "$(grep -Fc 'packet is too short, ignoring' \
	"$busybox_src/networking/udhcp/dhcpc.c")" -eq 2
# Patch 0059: nslookup reply length checks.
grep -Fq 'if (rdlen <= n) {' "$busybox_src/networking/nslookup.c"
grep -Fq 'if (rdlen < (cp - start) + 20) {' "$busybox_src/networking/nslookup.c"
grep -Fq '/* if "..": malicious, return "" */' \
	"$busybox_src/archival/libarchive/unsafe_prefix.c"
# Patch 0046 (CVE-2026-98432): IPv4 options are freed after an RCU grace period.
kernel_src="$btarget/linux-ipq53xx_generic/linux-6.6.88"
grep -Fq 'kfree_rcu(rcu_dereference_protected(inet->inet_opt, 1), rcu);' \
	"$kernel_src/net/ipv4/af_inet.c"
grep -Fq 'kfree_rcu(rcu_dereference_protected(inet_rsk(req)->ireq_opt, 1), rcu);' \
	"$kernel_src/net/ipv4/tcp_ipv4.c"
# Patch 0052: 908 (CVE-2026-99288, unhashed sockets in established lookups),
# 903 (CVE-2026-98255, old ACKs) and 909 (CVE-2026-99805, VLAN-0 depth).
grep -Fq 'if (unlikely(hlist_nulls_unhashed_lockless(&sk->sk_nulls_node) ||' \
	"$kernel_src/net/ipv4/inet_hashtables.c"
grep -Fq 'if (unlikely(hlist_nulls_unhashed_lockless(&sk->sk_nulls_node) ||' \
	"$kernel_src/net/ipv6/inet6_hashtables.c"
grep -Fq 'between(TCP_SKB_CB(skb)->ack_seq, tp->snd_una, tp->snd_nxt)) {' \
	"$kernel_src/net/ipv4/tcp_input.c"
grep -Fq 'if (unlikely(priority_tag_depth >= VLAN_MAX_DEPTH))' \
	"$kernel_src/net/core/dev.c"
# Patch 0052, the request-socket fixes 908 builds on: 901 (Fast Open request
# cleared on disconnect), 902 (no second removal in tcp_conn_request) and
# 907 (timer cancelled before the migrated request is dropped).
awk '
	/^int tcp_disconnect\(/ { f = 1 }
	f && /reqsk_fastopen_remove\(sk, req, false\);/ { ok = 1 }
	f && /^}/ { f = 0 }
	END { exit ok ? 0 : 1 }
' "$kernel_src/net/ipv4/tcp.c"
awk '
	/^int tcp_conn_request\(/ { f = 1 }
	f && /reqsk_fastopen_remove\(/ { bad = 1 }
	f && /^}/ { f = 0 }
	END { exit bad ? 1 : 0 }
' "$kernel_src/net/ipv4/tcp_input.c"
grep -Fq '__inet_csk_reqsk_queue_drop(sk_listener, nreq, false);' \
	"$kernel_src/net/ipv4/inet_connection_sock.c"
# Patch 0062: 910 and 911 (the full socket replaces the request socket in
# one step) and 912 (a dropped request is accounted to its own listener).
grep -Fq 'static inline void hlist_nulls_replace_init_rcu(struct hlist_nulls_node *old,' \
	"$kernel_src/include/linux/rculist_nulls.h"
grep -Fq 'ret = sk_nulls_replace_node_init_rcu(osk, sk);' \
	"$kernel_src/net/ipv4/inet_hashtables.c"
test "$(grep -Fc 'sk_nulls_del_node_init_rcu(osk)' "$kernel_src/net/ipv4/inet_hashtables.c")" -eq 0
grep -Fq '__inet_csk_reqsk_queue_drop(oreq->rsk_listener, oreq, true);' \
	"$kernel_src/net/ipv4/inet_connection_sock.c"
# Patch 0053 (CVE-2026-107891): overflow checks in regcomp.
grep -Fq 'static int check_add(unsigned a, unsigned b)' "$musl/src/regex/regcomp.c"

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

# The source checks above mean nothing for a stale kernel: the persistent
# kernel must decompress to the Image built in this tree, and no network
# or timer source file may be newer than that Image.
"$dumpimage" -T flat_dt -p 0 -o "$tmp/persistent.kernel.gz" \
	"$tmp/sysupgrade-zyxel_nwa50be/kernel" >/dev/null
gzip -dc "$tmp/persistent.kernel.gz" | cmp -s - "$btarget/linux-ipq53xx_generic/Image"
test -z "$(find "$kernel_src/net" "$kernel_src/include/net" \
	"$kernel_src/include/linux/rculist_nulls.h" \
	"$kernel_src/kernel/time/posix-cpu-timers.c" \
	-name '*.[ch]' -newer "$btarget/linux-ipq53xx_generic/Image" | head -n 1)"

"$unsquashfs" -no-exit-code -d "$tmp/rootfs" \
	"$tmp/sysupgrade-zyxel_nwa50be/root" >/dev/null 2>&1

grep -Fxq "DISTRIB_TIP_VERSION='v5.1.1'" "$tmp/rootfs/etc/openwrt_release"
grep -Fq 'TIP-v5.1.1-f18e1f56' "$tmp/rootfs/etc/openwrt_release"
grep -Fxq "DISTRIB_UCENTRAL_SCHEMA_REVISION='e293493'" \
	"$tmp/rootfs/etc/openwrt_release"
python3 -c 'import json, sys; assert json.load(open(sys.argv[1])) == {"major": 5, "minor": 1, "patch": 1}' \
	"$tmp/rootfs/etc/ucentral/version.json"
grep -Fxq 'ucentral-schema - 2026.10.15~e2934931-r1' \
	"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"
# Patch 0049: validated hwaddr= and a hostname script that keeps the user's name.
cmp -s "$tmp/rootfs/etc/board.d/02_network" \
	"$tree/feeds/qca-wifi-7/ipq53xx/base-files/etc/board.d/02_network"
grep -Fq 'wan_mac=$(zyxel_cmdline_mac)' "$tmp/rootfs/etc/board.d/02_network"
test "$(grep -Fc 'wan_mac=$(cat /proc/cmdline)' "$tmp/rootfs/etc/board.d/02_network")" -eq 0
cmp -s "$tmp/rootfs/etc/uci-defaults/99-ucentral-hostname" \
	"$tree/feeds/ucentral/ucentral-schema/files/etc/uci-defaults/99-ucentral-hostname"
grep -Fq 'if [ "$hostname" = OpenWrt ] || ! valid_hostname "$hostname"; then' \
	"$tmp/rootfs/etc/uci-defaults/99-ucentral-hostname"
grep -Fq 'config_add_string uci_section' "$tmp/rootfs/lib/netifd/hostapd.sh"
# Patch 0057: the LuCI session token comes from /dev/urandom.
grep -Fq "let data = readfile('/dev/urandom', num_bytes);" \
	"$tmp/rootfs/usr/share/ucode/luci/dispatcher.uc"
# Patch 0055: the resolved /proc path pattern for the rpcd symlink ACL check.
grep -Fq '"/proc/*/mounts": [ "read" ]' \
	"$tmp/rootfs/usr/share/rpcd/acl.d/luci-mod-system.json"
# Patch 0063: the resolved bridge port paths and the busybox link target.
python3 -I - "$tmp/rootfs/usr/share/rpcd/acl.d/luci-mod-network.json" <<'PY'
import json, sys
acl = json.load(open(sys.argv[1]))
config = acl["luci-mod-network-config"]["read"]["file"]
diagnostics = acl["luci-mod-network-diagnostics"]["read"]["file"]
assert config["/sys/devices/*/net/*/brport/*"] == ["read"]
assert diagnostics["/bin/busybox"] == ["list"]
PY
# The one admitted management address may use every uhttpd script slot.
grep -Fxq "uci -q set uhttpd.main.max_requests_per_source='3'" \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'append_arg "$cfg" max_requests_per_source "-W"' \
	"$tmp/rootfs/etc/init.d/uhttpd"
# Patch 0061, in the packaged binary itself: ask it through the hostapd
# link LuCI uses, when a user-mode emulator is installed. The source checks
# above cover hosts without one.
test "$(readlink "$tmp/rootfs/usr/sbin/hostapd")" = wpad
if command -v qemu-aarch64-static >/dev/null 2>&1; then
	hostapd_has() {
		qemu-aarch64-static "$tmp/rootfs/lib/ld-musl-aarch64.so.1" \
			--library-path "$tmp/rootfs/usr/lib:$tmp/rootfs/lib" \
			--argv0 hostapd "$tmp/rootfs/usr/sbin/hostapd" "-v$1" >/dev/null 2>&1
	}
	hostapd_has 11be
	hostapd_has 11ax
	status=0
	hostapd_has no-such-feature || status=$?
	if [ "$status" -ne 1 ]; then
		echo "Refusing: hostapd answered $status to an unknown feature, expected 1." >&2
		exit 1
	fi
else
	echo 'Note: qemu-aarch64-static not found; hostapd feature query checked in source only.' >&2
fi
cmp -s "$tmp/rootfs/lib/netifd/hostapd.sh" \
	"$tree/feeds/qca-wifi-7/wifi-scripts/files/lib/netifd/hostapd.sh"

for path in \
	etc/NWA50BE_PERSISTENT_BUILD \
	etc/sysupgrade.conf \
	etc/apk/repositories.d/distfeeds.list \
	etc/init.d/qca-ssdk \
	etc/config/network etc/config/firewall etc/config/dropbear \
	etc/uci-defaults/zzzz-nwa50be-community \
	etc/modules.d/ath12k etc/init.d/ath12k_dyn_dbg_enable.sh \
	root/nwa50be-setup usr/libexec/nwa50be-management-state \
	usr/sbin/nwa50be-sysupgrade \
	usr/share/nwa50be/99-wireless-isolation \
	usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft \
	lib/firmware/ath12k/IPQ5332/hw1.0/caldata.bin \
	lib/firmware/ath12k/QCN6432/hw1.0/cal-ahb-soc@0:wifi2@c0000000.bin \
	sbin/sysupgrade usr/sbin/ubiformat usr/sbin/ubiupdatevol \
	www/cgi-bin/luci www/luci-static/bootstrap/cascade.css \
	www/luci-static/resources/view/network/dhcp.js \
	www/luci-static/resources/view/network/wireless.js \
	www/luci-static/resources/view/status/include/40_dhcp.js; do
	test -e "$tmp/rootfs/$path"
done

for path in \
	etc/sysupgrade.conf \
	etc/uci-defaults/99-ucentral-network \
	etc/uci-defaults/zzz-ucentral \
	etc/uci-defaults/zzzz-nwa50be-community \
	usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft \
	root/nwa50be-setup \
	usr/libexec/nwa50be-management-state \
	usr/sbin/nwa50be-sysupgrade; do
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
test -x "$tmp/rootfs/usr/sbin/nwa50be-sysupgrade"
grep -Fq '"$sysupgrade_bin" -T -f "$backup" "$image"' \
	"$tmp/rootfs/usr/sbin/nwa50be-sysupgrade"
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
grep -Fq "uhttpd.main.ucode_prefix='/cgi-bin/luci=/usr/share/ucode/luci/uhttpd.uc'" \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"
test -f "$tmp/rootfs/usr/share/ucode/luci/uhttpd.uc"
# Workers must not share the uhttpd parent's ubus socket (login page hang).
grep -Fxq "$(printf '\tubus = connect();')" \
	"$tmp/rootfs/usr/share/ucode/luci/dispatcher.uc"

# Patch 0040 changes the toolchain's musl, but OpenWrt does not repackage libc
# by itself after that. The image must carry the rebuilt libc, not the
# unpatched 25.12.3 one (sha256 below, shipped by the first two fork images).
libc_sha=$(sha256sum "$tmp/rootfs/lib/libc.so")
test "${libc_sha%% *}" != \
	'2df39ef76b658fa2d8c7b6f3cff5cb0963508ce2d15250590ba5aa29efb80e4f'
toolchain_dir="$openwrt/staging_dir/toolchain-aarch64_cortex-a53+neon-vfpv4_gcc-14.3.0_musl"
test -n "$(find "$btarget/toolchain/.built" -newer "$toolchain_dir/stamp/.musl_installed")"
# The shipped libc is the freshly built toolchain libc after the image's own
# sstrip step (checked to be byte-identical on 2026-10-31).
cp "$toolchain_dir/lib/libc.so" "$tmp/libc-staging.so"
"$openwrt/staging_dir/host/bin/sstrip" "$tmp/libc-staging.so"
cmp -s "$tmp/libc-staging.so" "$tmp/rootfs/lib/libc.so"
if grep -Fq 'uhttpd.main.listen_http=' \
	"$tmp/rootfs/etc/uci-defaults/zzzz-nwa50be-community"; then
	echo 'Refusing: first-boot policy still configures cleartext HTTP.' >&2
	exit 1
fi
grep -Fq 'hook ingress device eth0 priority -500' \
	"$tmp/rootfs/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fq 'meta mark set meta mark | 0x40000000' \
	"$tmp/rootfs/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fq 'hook input priority -10' \
	"$tmp/rootfs/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fq 'meta mark & 0x40000000 == 0 drop' \
	"$tmp/rootfs/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fxq 'destroy table bridge nwa50be_management' \
	"$tmp/rootfs/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"

grep -Eq '^uhttpd - 2026\.11\.05~93b05e0b-r1$' \
	"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"
grep -Eq '^libopenssl3 - 3\.5\.9-r1$' \
	"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"
grep -Eq '^cgi-io - 2026\.07\.21~31cb3c89-r1$' \
	"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"
grep -Eq '^umdns - 2026\.10\.04~defe7ccf-r1$' \
	"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"
for line in \
	'dropbear - 2026.94-r4' \
	'busybox - 1.37.0-r9' \
	'dnsmasq-full - 2.93-r5' \
	'zlib - 1.3.1-r2' \
	'rpcd - 2026.10.04~d99f703e-r1' \
	'ca-bundle - 20260816-r2' \
	'libubox20260213 - 2026.11.02~ff13b89e-r1' \
	'libmbedtls21 - 3.6.8-r1' \
	'libpcap1 - 1.10.7-r1' \
	'curl - 8.23.0-r1' \
	'libcurl4 - 8.23.0-r1' \
	'libnghttp2-14 - 1.70.0-r1' \
	'libevent2-7 - 2.1.13-r1' \
	'libssh - 0.12.2-r2'; do
	grep -Fxq "$line" "$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"
done
grep -Eq '^procd - 2026\.03\.13~58eb263d-r1$' \
	"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"
grep -Eq '^jsonfilter - 2026\.03\.16~b9034210-r1$' \
	"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"

"$project/scripts/check-luci-mount-acl.py" \
	"$tmp/rootfs/usr/share/rpcd/acl.d/luci-mod-system.json"
test "$(grep -Fo "'%h'.format(host||'-')" \
	"$tmp/rootfs/www/luci-static/resources/view/network/dhcp.js" | wc -l)" -eq 2
test "$(grep -Fo "'%h'.format(host||'-')" \
	"$tmp/rootfs/www/luci-static/resources/view/status/include/40_dhcp.js" | wc -l)" -eq 2
grep -Fq 'document.createTextNode(`${res?.ssid}`)' \
	"$tmp/rootfs/www/luci-static/resources/view/network/wireless.js"
if grep -Eq '^luci-app-package-manager ' \
	"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"; then
	echo 'Refusing: unsupported LuCI package manager is installed.' >&2
	exit 1
fi
for package in \
	odhcpd odhcpd-ipv6only ead luci-lib-px5g luci-app-https-dns-proxy \
	luci-app-adblock-fast luci-app-bmx7 luci-app-banip luci-app-upnp \
	luci-app-travelmate luci-app-advanced-reboot luci-proto-openvpn \
	luci-app-dockerman luci-app-samba4 luci-app-tailscale-community \
	luci-app-lxc; do
	if grep -Eq "^${package} " \
		"$stage/openwrt-ipq53xx-zyxel_nwa50be.manifest"; then
		echo "Refusing: security-disposition package is unexpectedly installed: $package" >&2
		exit 1
	fi
done
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
