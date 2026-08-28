# Security findings and mitigations

This document records findings from a review of the pinned TIP/OpenWiFi source,
the generated firmware, and one installed NWA50BE. It describes this project's
specific mitigations, not the security posture of every TIP, OpenWrt, Qualcomm,
or Zyxel build.

No credential, device serial, MAC address, calibration hash, unlock token,
private network address, or administrator identity is included here.

## Inherited web-service vulnerabilities

The pinned source originally selected an older uHTTPd revision preceding fixes
for CVE-2026-55612, CVE-2026-55613, and CVE-2026-55614. These issues concern
HTTP request parsing and request smuggling.

The build applies
[`0011-openwrt-update-uhttpd-security.patch`](../patches/0011-openwrt-update-uhttpd-security.patch),
which backports the uHTTPd revision used by OpenWrt 25.12.5. The installed AP
reports uHTTPd `2026.06.16~7b1bec45-r1`. Defense in depth also removes cleartext
HTTP, disables HTTP keep-alive, limits HTTPS to one provisioned wired `/32`, and
blocks all wireless bridge interfaces from the AP management plane.

## OpenSSL and unused QUIC code

The pinned tree selected OpenSSL 3.5.6. The build backports OpenSSL 3.5.7 with
[`0012-openwrt-update-openssl-3.5.7.patch`](../patches/0012-openwrt-update-openssl-3.5.7.patch).
The installed AP reports `libopenssl3-3.5.7-r1`.

No shipped service needs OpenSSL QUIC. The build therefore applies
[`0016-openssl-disable-unused-quic.patch`](../patches/0016-openssl-disable-unused-quic.patch)
to remove that code, including the QUIC listener surface associated with
CVE-2026-14456. Artifact verification rejects any image whose `libssl.so.3`
still exports `OSSL_QUIC_server_method`.

## Public development credential and embedded keys

The inherited development image contained a publicly known root-password hash.
[`0013-openwrt-remove-default-root-password.patch`](../patches/0013-openwrt-remove-default-root-password.patch)
removes it. Fresh images have no usable remote management until serial setup
records a unique root password and a single administrator `/32`. SSH remains
disabled unless the owner separately installs an authorized key.

Artifact verification rejects embedded `authorized_keys` files. The repository
and its reachable history are also scanned for private keys, public SSH keys,
unlock-token structure, private addresses, MAC addresses, personal paths, and
forbidden firmware or calibration files.

## Build-time config-seed command injection

The original config-seed helper interpolated an unchecked Kconfig symbol into a
`sed` expression. A malicious seed controlled by someone able to modify build
inputs could reach `sed` command execution on the build host.

[`scripts/apply-config-seed.sh`](../scripts/apply-config-seed.sh) now rejects
symbols containing shell or `sed` metacharacters before interpolation.
[`scripts/test-security-regressions.sh`](../scripts/test-security-regressions.sh)
contains a malicious-seed regression test and verifies accepted symbols still
produce the intended configuration.

## Management-plane exposure

The initial live configuration accepted all input on the shared LAN bridge.
That made SSH and LuCI reachable from bridged wireless clients. A source-address
allowlist alone was insufficient because a wireless client on the same bridge
could spoof the trusted address.

The corrected policy combines:

- default `REJECT` input policy;
- TCP 22 and 443 plus ICMP allowed only from one recorded wired `/32`;
- key-only SSH with port forwarding disabled;
- HTTPS-only LuCI with HTTP keep-alive disabled; and
- bridge-family nftables drops for every 2.4, 5, and 6 GHz AP interface.

Management services remain usable from the provisioned wired host while
wireless-originated management traffic is rejected before the IP allowlist.

## Package and writable-storage boundaries

The downstream target has no compatible public binary package repository.
Remote APK feeds and LuCI package management are disabled to avoid installing
ABI-incompatible or unreviewed packages.

Linux can write only the reviewed NAND `rootfs` partition. SPI NOR is absent
from Linux MTD enumeration, bootloader and ART are not exposed, recovery and
license partitions are read-only, and the image does not contain the generic
`mtd` write utility.

## Upgrade-state failure

This snapshot treats plain `sysupgrade <image>` as a no-preservation upgrade.
That behavior caused a provisioned AP to boot without its saved management and
wireless configuration. Recovery used UART and a verified configuration archive.

The source now ships [`nwa50be-sysupgrade`](../overlay/usr/sbin/nwa50be-sysupgrade),
which creates a backup, verifies the required management and wireless state,
tests the image with that backup, and explicitly passes it using `sysupgrade
-f`. The wrapper has automated regression coverage but has not yet been used
for another live flash.

## Verification boundary

The installed AP has the updated uHTTPd and OpenSSL packages, HTTPS-only and
wired-only management, key-only SSH, restricted write surfaces, and more than
five days of continuous post-recovery operation.

The latest rebuilt artifact additionally contains the corrected upgrade
wrapper, fresh-boot DHCP DUID cleanup, and idempotent wireless-management
nftables loading. Those three source corrections passed automated artifact and
regression checks but have not been validated by another live installation.

Security fixes do not eliminate the hardware-recovery boundary. A failed NAND
or kernel boot still requires UART and TFTP.
