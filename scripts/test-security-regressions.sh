#!/bin/sh

# Test fixtures below intentionally preserve shell expressions for later execution.
# shellcheck disable=SC2016

set -eu

project=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.."
	pwd
)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

mkdir -p "$tmp/bin" "$tmp/openwrt"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$tmp/bin/make"
chmod 0755 "$tmp/bin/make"

cat >"$tmp/safe-acl.json" <<'EOF'
{
	"luci-mod-system-mounts": {
		"write": {
			"file": {
				"/bin/umount": [ "exec" ]
			}
		}
	}
}
EOF
"$project/scripts/check-luci-mount-acl.py" "$tmp/safe-acl.json"

cat >"$tmp/vulnerable-acl.json" <<'EOF'
{
	"luci-mod-system-mounts": {
		"write": {
			"file": {
				"/etc/crontabs/root": [ "write" ]
			}
		}
	}
}
EOF
if "$project/scripts/check-luci-mount-acl.py" \
	"$tmp/vulnerable-acl.json" >"$tmp/vulnerable-acl.log" 2>&1; then
	echo 'Refusing: vulnerable LuCI mount ACL passed verification.' >&2
	exit 1
fi
grep -Fq 'LuCI mount ACL can still write the root crontab' \
	"$tmp/vulnerable-acl.log"

printf '%s\n' 'CONFIG_ATTACK=y' >"$tmp/openwrt/.config"
printf '%s\n' 'CONFIG_ATTACK=y' 'CONFIG_ATTACK/e id;#=y' \
	>"$tmp/malicious.seed"

if PATH="$tmp/bin:$PATH" \
	"$project/scripts/apply-config-seed.sh" \
	"$tmp/openwrt" "$tmp/malicious.seed" >"$tmp/malicious.log" 2>&1; then
	echo 'Refusing: malicious config symbol was accepted.' >&2
	exit 1
fi
grep -Fq 'Invalid config symbol:' "$tmp/malicious.log"
if grep -Fq 'uid=' "$tmp/malicious.log"; then
	echo 'Refusing: config symbol reached sed command execution.' >&2
	exit 1
fi

printf '%s\n' 'CONFIG_FOO=n' 'CONFIG_BAR=y' 'CONFIG_TARGET_ipq53xx=n' \
	'CONFIG_PACKAGE_ip-bridge=n' \
	>"$tmp/openwrt/.config"
printf '%s\n' 'CONFIG_FOO=y' '# CONFIG_BAR is not set' \
	'CONFIG_TARGET_ipq53xx=y' 'CONFIG_PACKAGE_ip-bridge=y' >"$tmp/valid.seed"
PATH="$tmp/bin:$PATH" \
	"$project/scripts/apply-config-seed.sh" \
	"$tmp/openwrt" "$tmp/valid.seed"
grep -Fxq 'CONFIG_FOO=y' "$tmp/openwrt/.config"
grep -Fxq '# CONFIG_BAR is not set' "$tmp/openwrt/.config"
grep -Fxq 'CONFIG_TARGET_ipq53xx=y' "$tmp/openwrt/.config"
grep -Fxq 'CONFIG_PACKAGE_ip-bridge=y' "$tmp/openwrt/.config"
test "$(wc -l <"$tmp/openwrt/.config")" -eq 4

management_root="$tmp/management-root"
mkdir -p "$management_root/etc/dropbear"
touch "$management_root/etc/nwa50be-setup-complete"
printf '%s\n' '192.0.2.21/32' \
	>"$management_root/etc/nwa50be-management-cidr"
printf '%s\n' 'ssh-ed25519 test-key nwa50be-test' \
	>"$management_root/etc/dropbear/authorized_keys"
mkdir -p "$management_root/etc/config"
for config in dropbear firewall network uhttpd wireless; do
	printf 'config %s\n' "$config" >"$management_root/etc/config/$config"
done
printf '%s\n' 'root:$6$test-hash:20000:0:99999:7:::' \
	>"$management_root/etc/shadow"

test "$("$project/overlay/usr/libexec/nwa50be-management-state" \
	"$management_root")" = '192.0.2.21/32'

printf '%s\n' '192.0.2.0/24' \
	>"$management_root/etc/nwa50be-management-cidr"
if "$project/overlay/usr/libexec/nwa50be-management-state" \
	"$management_root" >/dev/null 2>&1; then
	echo 'Refusing: remote management accepted a non-host CIDR.' >&2
	exit 1
fi
printf '%s\n' '192.0.2.21/32' \
	>"$management_root/etc/nwa50be-management-cidr"

printf '%s\n' 'root::20000:0:99999:7:::' >"$management_root/etc/shadow"
if "$project/overlay/usr/libexec/nwa50be-management-state" \
	"$management_root" >/dev/null 2>&1; then
	echo 'Refusing: remote management accepted an empty root password.' >&2
	exit 1
fi
printf '%s\n' 'root:$6$test-hash:20000:0:99999:7:::' \
	'root:$6$duplicate:20000:0:99999:7:::' >"$management_root/etc/shadow"
if "$project/overlay/usr/libexec/nwa50be-management-state" \
	"$management_root" >/dev/null 2>&1; then
	echo 'Refusing: remote management accepted duplicate root entries.' >&2
	exit 1
fi
printf '%s\n' 'root:$6$test-hash:20000:0:99999:7:::' \
	>"$management_root/etc/shadow"

firstboot_log="$tmp/firstboot.log"
mkdir -p "$management_root/etc/init.d" \
	"$management_root/usr/libexec"
cp "$project/overlay/usr/libexec/nwa50be-management-state" \
	"$management_root/usr/libexec/"
printf '%s\n' '#!/bin/sh' \
	'printf "service %s %s\\n" "$(basename "$0")" "$*" >>"$NWA50BE_TEST_LOG"' \
	>"$tmp/bin/fake-service"
chmod 0755 "$tmp/bin/fake-service"
for service in dnsmasq dropbear firewall odhcpd rpcd sysntpd uhttpd; do
	cp "$tmp/bin/fake-service" "$management_root/etc/init.d/$service"
done
printf '%s\n' '#!/bin/sh' \
	'printf "uci" >>"$NWA50BE_TEST_LOG"' \
	'for argument in "$@"; do printf " %s" "$argument" >>"$NWA50BE_TEST_LOG"; done' \
	'printf "\\n" >>"$NWA50BE_TEST_LOG"' \
	'[ "$*" = "-q get firewall.@zone[0]" ] && exit 1' \
	'[ "$*" = "-q get network.globals.dhcp_default_duid" ] && { printf "%s\\n" auto; exit 0; }' \
	'[ "$*" = "-q show firewall" ] && { printf "%s\\n" "firewall.guest=zone"; exit 0; }' \
	'exit 0' >"$tmp/bin/uci"
printf '%s\n' '#!/bin/sh' \
	'printf "wifi %s\\n" "$*" >>"$NWA50BE_TEST_LOG"' \
	>"$tmp/bin/wifi"
printf '%s\n' '#!/bin/sh' \
	'printf "logger %s\\n" "$*" >>"$NWA50BE_TEST_LOG"' \
	>"$tmp/bin/logger"
chmod 0755 "$tmp/bin/uci" "$tmp/bin/wifi" "$tmp/bin/logger"

NWA50BE_ROOT="$management_root" \
NWA50BE_TEST_LOG="$firstboot_log" \
PATH="$tmp/bin:$PATH" \
	/bin/sh "$project/overlay/etc/uci-defaults/zzzz-nwa50be-community"

grep -Fq 'service dropbear enable' "$firstboot_log"
grep -Fq 'service odhcpd disable' "$firstboot_log"
grep -Fq 'service odhcpd stop' "$firstboot_log"
grep -Fq 'service rpcd enable' "$firstboot_log"
grep -Fq 'service uhttpd enable' "$firstboot_log"
grep -Fq 'uci -q set firewall.lan.input=REJECT' "$firstboot_log"
grep -Fq 'uci -q set firewall.guest.input=REJECT' "$firstboot_log"
grep -Fq \
	'uci -q set firewall.nwa50be_management.src_ip=192.0.2.21/32' \
	"$firstboot_log"
if grep -Fq 'service dropbear disable' "$firstboot_log" || \
	grep -Fq 'service uhttpd disable' "$firstboot_log" || \
	grep -Fq 'uci -q delete network.lan' "$firstboot_log"; then
	echo 'Refusing: provisioned upgrade disabled management or rewrote LAN.' >&2
	exit 1
fi

: >"$management_root/etc/dropbear/authorized_keys"
test "$("$project/overlay/usr/libexec/nwa50be-management-state" \
	"$management_root")" = '192.0.2.21/32'
: >"$firstboot_log"
NWA50BE_ROOT="$management_root" \
NWA50BE_TEST_LOG="$firstboot_log" \
PATH="$tmp/bin:$PATH" \
	/bin/sh "$project/overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'service dropbear disable' "$firstboot_log"
grep -Fq 'service rpcd enable' "$firstboot_log"
grep -Fq 'service uhttpd enable' "$firstboot_log"
grep -Fq \
	'uci -q set firewall.nwa50be_management.src_ip=192.0.2.21/32' \
	"$firstboot_log"
if grep -Fq 'service uhttpd disable' "$firstboot_log" || \
	grep -Fq 'uci -q delete network.lan' "$firstboot_log"; then
	echo 'Refusing: keyless HTTPS upgrade disabled management or rewrote LAN.' >&2
	exit 1
fi
printf '%s\n' 'ssh-ed25519 test-key nwa50be-test' \
	>"$management_root/etc/dropbear/authorized_keys"

upgrade_log="$tmp/upgrade.log"
upgrade_backup="$tmp/upgrade-backup.tar.gz"
upgrade_image="$tmp/sysupgrade.tar"
printf '%s\n' 'test-image' >"$upgrade_image"
printf '%s\n' '#!/bin/sh' \
	'printf "%s\\n" "$*" >>"$NWA50BE_TEST_LOG"' \
	'case "$1" in' \
	'  -b)' \
	'    if [ "${NWA50BE_TEST_INCOMPLETE:-0}" = 1 ]; then' \
	'      tar -C "$NWA50BE_TEST_ROOT" -czf "$2" \
	        etc/config/dropbear etc/config/firewall etc/config/network \
	        etc/config/uhttpd etc/config/wireless \
	        etc/nwa50be-management-cidr etc/shadow \
	        etc/dropbear/authorized_keys' \
	'    else' \
	'      tar -C "$NWA50BE_TEST_ROOT" -czf "$2" \
	        etc/config/dropbear etc/config/firewall etc/config/network \
	        etc/config/uhttpd etc/config/wireless \
	        etc/nwa50be-setup-complete etc/nwa50be-management-cidr \
	        etc/shadow etc/dropbear/authorized_keys' \
	'    fi' \
	'    ;;' \
	'  -T|-f) exit 0 ;;' \
	'  *) exit 1 ;;' \
	'esac' >"$tmp/bin/mock-sysupgrade"
chmod 0755 "$tmp/bin/mock-sysupgrade"

NWA50BE_ROOT="$management_root" \
NWA50BE_TEST_ROOT="$management_root" \
NWA50BE_TEST_LOG="$upgrade_log" \
NWA50BE_SYSUPGRADE_BIN="$tmp/bin/mock-sysupgrade" \
NWA50BE_BACKUP_PATH="$upgrade_backup" \
	"$project/overlay/usr/sbin/nwa50be-sysupgrade" "$upgrade_image"
grep -Fxq -- "-b $upgrade_backup" "$upgrade_log"
grep -Fxq -- "-T -f $upgrade_backup $upgrade_image" "$upgrade_log"
grep -Fxq -- "-f $upgrade_backup $upgrade_image" "$upgrade_log"

: >"$upgrade_log"
if NWA50BE_ROOT="$management_root" \
	NWA50BE_TEST_ROOT="$management_root" \
	NWA50BE_TEST_LOG="$upgrade_log" \
	NWA50BE_TEST_INCOMPLETE=1 \
	NWA50BE_SYSUPGRADE_BIN="$tmp/bin/mock-sysupgrade" \
	NWA50BE_BACKUP_PATH="$upgrade_backup" \
	"$project/overlay/usr/sbin/nwa50be-sysupgrade" \
	"$upgrade_image" >"$tmp/incomplete-upgrade.log" 2>&1; then
	echo 'Refusing: upgrade wrapper accepted an incomplete backup.' >&2
	exit 1
fi
grep -Fq 'configuration backup is missing etc/nwa50be-setup-complete' \
	"$tmp/incomplete-upgrade.log"
if grep -Eq '^-T |^-f ' "$upgrade_log"; then
	echo 'Refusing: incomplete backup reached an upgrade invocation.' >&2
	exit 1
fi

rm -f "$management_root/etc/nwa50be-setup-complete"
: >"$firstboot_log"
NWA50BE_ROOT="$management_root" \
NWA50BE_TEST_LOG="$firstboot_log" \
PATH="$tmp/bin:$PATH" \
	/bin/sh "$project/overlay/etc/uci-defaults/zzzz-nwa50be-community"
grep -Fq 'service dropbear disable' "$firstboot_log"
grep -Fq 'service rpcd disable' "$firstboot_log"
grep -Fq 'service uhttpd disable' "$firstboot_log"
grep -Fq 'uci -q delete network.lan' "$firstboot_log"
grep -Fq 'uci -q delete network.globals.dhcp_default_duid' "$firstboot_log"
if grep -Fq 'firewall.nwa50be_management.src_ip=' "$firstboot_log"; then
	echo 'Refusing: unprovisioned boot exposed remote management.' >&2
	exit 1
fi

grep -Fxq 'destroy table bridge nwa50be_management' \
	"$project/overlay/usr/share/nftables.d/ruleset-pre/10-nwa50be-wireless-management.nft"
grep -Fq 'adapter RX to AP pin 2 (TX)' "$project/docs/INSTALL.md"
grep -Fq 'pin 3 (RX)' "$project/docs/INSTALL.md"
grep -Fq 'AP header:  [1] [2] [3] [4]' "$project/README.md"
grep -Fq 'NC  TX  RX  GND' "$project/README.md"
grep -Fq '3.3 V means TTL logic level, not a power connection' \
	"$project/README.md"
grep -Fq 'Never connect adapter `VCC`, `3V3`, or `5V`' \
	"$project/docs/INSTALL.md"

echo 'Security regression tests passed.'
