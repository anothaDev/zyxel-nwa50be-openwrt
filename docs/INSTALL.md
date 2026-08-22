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

## UART

Use a 3.3 V TTL adapter. Cross adapter RX to AP TX and adapter TX to AP RX.
Connect ground. Never connect adapter VCC and never use RS-232 voltage levels.

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

The helper sets a root password and ISO country code, then enables HTTPS LuCI.
It does not create SSIDs or enable radios. Configure those deliberately in LuCI
and retain the driver's regulatory enforcement.
