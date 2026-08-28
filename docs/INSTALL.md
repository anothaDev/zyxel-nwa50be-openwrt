# Installation

This procedure can erase the stock firmware and leave the AP dependent on
serial recovery. Read the official Zyxel waiver documentation first.

## Preconditions

1. Confirm the exact model is NWA50BE.
2. Upgrade stock firmware to a Zyxel-supported unlock release.
3. Generate a per-device unlock token through Zyxel's official waiver service.
4. Export the stock configuration.
5. Capture a complete stock boot over 3.3 V TTL UART at 115200 8N1.
6. Back up full SPI NOR and ART using the read-only procedure in RECOVERY.md.
7. Build images using that same device's ART.

Zyxel states that NWA50BE OpenWrt conversion is supported from V7.30 and that
custom firmware is outside normal warranty and support coverage:

- https://community.zyxel.com/en/discussion/32423/zyxel-networks-access-points-now-support-openwrt-based-customized-software
- https://warranty-waiver.zyxel.com/
- https://warranty-waiver.zyxel.com/docs/Zyxel_OpenWRT_SOP_v1.1-202600303.pdf

## UART

Use a 3.3 V TTL adapter. Connect adapter RX to AP pin 2 (TX), adapter TX to AP
pin 3 (RX), and ground to AP pin 4. Power the AP through PoE. The adapter's
3.3 V setting describes its UART logic level; it does not authorize a power
connection. Never connect adapter `VCC`, `3V3`, or `5V` to pin 1 or any other
AP header pin, and never use RS-232 voltage levels.

The standard four-pin orientation, viewed using the board's pin-1 triangle, is:

```text
triangle
   v
 [1] [2] [3] [4]
  NC  TX  RX  GND
```

Verify the board revision and pinout independently before applying power.

## Official unlock

Submit the Zyxel-generated token only through the authenticated stock serial
CLI and only after accepting the waiver. Never record the token in a repository
or issue. The tested process rebooted into an unrestricted SDK U-Boot and left
the NAND rootfs area empty.

Do not run `saveenv`.

## Read-only RAM boot

Use an isolated Ethernet segment and a TFTP server. Choose temporary addresses
that do not conflict with another DHCP server. In unlocked U-Boot:

```text
setenv ipaddr <AP_TEMPORARY_IP>
setenv serverip <TFTP_SERVER_IP>
setenv netmask <NETMASK>
ping <TFTP_SERVER_IP>
tftpboot 0x60000000 <INITRAMFS_FILENAME>
```

Run `scripts/uboot-values.sh` on the exact initramfs file. Stop unless U-Boot's
transferred byte count matches. Then run U-Boot `crc32` over the exact reported
hex size and compare it with the script output. Only after both checks match:

```text
bootm 0x60000000
```

This command boots the FIT from RAM. It does not persist U-Boot environment.

## Persistent install

The initramfs system uses DHCP on Ethernet, keeps radios disabled, and exposes
SPI NOR to neither Linux nor user-space tools. SSH and LuCI are intentionally
off. On the isolated build host, serve only the matching timestamped artifact
directory:

```sh
cd artifacts/<BUILD_TIMESTAMP>
python3 -m http.server 8000 --bind <BUILD_HOST_IP>
```

Find the AP's DHCP address from its serial console, then pull the archive from
that same console:

```sh
ubus call network.interface.lan status
wget -O /tmp/openwrt-ipq53xx-zyxel_nwa50be-squashfs-sysupgrade.tar \
  http://<BUILD_HOST_IP>:8000/openwrt-ipq53xx-zyxel_nwa50be-squashfs-sysupgrade.tar
```

Stop the temporary HTTP server after the transfer. Still on the serial console:

```sh
sha256sum /tmp/openwrt-ipq53xx-zyxel_nwa50be-squashfs-sysupgrade.tar
sysupgrade -T /tmp/openwrt-ipq53xx-zyxel_nwa50be-squashfs-sysupgrade.tar
sysupgrade -n /tmp/openwrt-ipq53xx-zyxel_nwa50be-squashfs-sysupgrade.tar
```

Stop if the SHA-256 differs from the `SHA256SUMS` file in the matching local
timestamped artifact directory, or if `sysupgrade -T` fails. Keep serial
capture running through the first normal U-Boot boot.

## First boot

Network management services and radios remain disabled. Log in on serial and
run:

```sh
/root/nwa50be-setup
```

The helper replaces the intentionally empty serial-setup password, sets an ISO
country code, then enables HTTPS LuCI.
It requires the wired administrator's IPv4 address as a `/32`. Wireless bridge
ports are blocked from the AP management plane independently of this source
allowlist. The setup state, management `/32`, password, and SSH key when present
are preserved across later sysupgrades. HTTPS remains reachable only from that
host; SSH does too when an authorized key exists. Cleartext HTTP remains
disabled. Use a static or DHCP-reserved administrator address; changing it
requires another serial setup run.
The helper does not create SSIDs or enable radios. Configure those deliberately
in LuCI and retain the driver's regulatory enforcement. Use 6 GHz LPI mode only
where permitted and only in the indoor deployment conditions required locally.

## Later remote upgrades

An already provisioned AP may retain remote management across a later
sysupgrade when all of the following are preserved: the setup-complete marker,
one wired administrator `/32`, and a nonempty root password. The first-boot
policy validates that state before enabling rpcd and uhttpd. Dropbear is enabled
only when at least one SSH authorized key is also preserved. The policy rebuilds
the input firewall with only ports 22 and 443 allowed from the recorded `/32`;
cleartext HTTP remains absent.

The first upgrade from an older community image requires staging
`/etc/nwa50be-setup-complete` and `/etc/nwa50be-management-cidr`, then confirming
that `sysupgrade -l` lists those files and, when used,
`/etc/dropbear/authorized_keys`. The key is optional when only HTTPS management
is required.
This OpenWrt snapshot treats a plain `sysupgrade <image>` command as a
no-preservation upgrade. Use the device wrapper, which creates and validates a
backup before passing it explicitly with `sysupgrade -f`:

```sh
nwa50be-sysupgrade /tmp/openwrt-ipq53xx-zyxel_nwa50be-squashfs-sysupgrade.tar
```

Do not invoke plain `sysupgrade <image>` for a provisioned AP. `sysupgrade -n`
also deliberately removes the saved state and returns the AP to serial-only
setup.

Remote upgrade prevents an intentional management lockout, but it cannot
recover a failed boot. Without UART, a NAND or kernel failure remains
unrecoverable over the network.
