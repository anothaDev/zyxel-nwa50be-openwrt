# Security findings and mitigations

This document records findings from a review of the pinned TIP/OpenWiFi source,
the generated firmware, and one installed NWA50BE. It describes this project's
specific mitigations, not the security posture of every TIP, OpenWrt, Qualcomm,
or Zyxel build.

No credential, device serial, MAC address, calibration hash, unlock token,
private network address, or administrator identity is included here.

The upstream advisory review in this document is current through 2026-08-28.

## Inherited web-service vulnerabilities

The pinned source originally selected an older uHTTPd revision preceding fixes
for CVE-2026-55612, CVE-2026-55613, and CVE-2026-55614. A later publication
review also identified GHSA-vhx4-3p5q-m59q, GHSA-2mpg-6wp5-435p,
GHSA-c2wg-hcff-hqrm, GHSA-83vv-qrc6-h3hx, and GHSA-wvgh-cm54-q6f6. These
advisories cover request smuggling, memory corruption or growth, and a
permanent listener wedge.

The build applies
[`0011-openwrt-update-uhttpd-security.patch`](../patches/0011-openwrt-update-uhttpd-security.patch),
which selects OpenWrt's reviewed 2026-08-03 revision containing all of those
fixes. Defense in depth also removes cleartext HTTP, disables HTTP keep-alive,
limits HTTPS to one provisioned wired `/32`, and blocks all wireless bridge
interfaces from the AP management plane.

The installed validation unit remains on the earlier June revision. Its LuCI
listener is contained to the provisioned wired host, but the August uHTTPd
update is source-only until a later firmware installation is deliberately
performed and validated.

## OpenSSL and unused QUIC code

The pinned tree selected OpenSSL 3.5.6. The source now updates to OpenSSL 3.5.8
with
[`0012-openwrt-update-openssl-3.5.8.patch`](../patches/0012-openwrt-update-openssl-3.5.8.patch).
That release addresses CVE-2026-14456, CVE-2026-14457, CVE-2026-18798,
CVE-2026-54874, CVE-2026-63072, CVE-2026-63073, CVE-2026-63074,
CVE-2026-63075, CVE-2026-63076, and CVE-2026-75803. The installed validation
unit remains on `libopenssl3-3.5.7-r1`. The latest locally built candidate
contains `libopenssl3-3.5.8-r1` and passed the project artifact checks, but it
has not been installed on the validation unit.

No shipped service needs OpenSSL QUIC. The build therefore applies
[`0016-openssl-disable-unused-quic.patch`](../patches/0016-openssl-disable-unused-quic.patch)
to remove that code, including the QUIC surfaces associated with
CVE-2026-14456, CVE-2026-18798, and CVE-2026-63075. Artifact verification
rejects any image whose `libssl.so.3` still exports
`OSSL_QUIC_server_method`.

## cgi-io file-read boundary

The selected `cgi-io` revision was affected by CVE-2026-62947, an ACL bypass
and arbitrary root-file read through `cgi-download`. The source applies
[`0017-packages-update-cgi-io-security.patch`](../patches/0017-packages-update-cgi-io-security.patch),
using the fixed revision selected by OpenWrt's current 25.12 packages feed.
The update is checked in both the prepared source and final package manifest.

## LuCI delegated mount ACL

The selected `luci-mod-system` ACL gave a delegated mount-management user stale
write access to root's crontab. That permission can turn a limited authenticated
LuCI account into root command execution, as tracked by
GHSA-v5f9-62c7-cw29.

[`0018-luci-remove-mount-crontab-grant.patch`](../patches/0018-luci-remove-mount-crontab-grant.patch)
backports the one-line upstream fix. The installed validation unit has only its
root administrator and no delegated LuCI users, so that exploitation
precondition is absent there. The verifier nevertheless rejects future images
that retain the stale crontab grant.

## LuCI untrusted table fields

The pinned May 2026 LuCI feed already contains the Wi-Fi scan SSID escaping fix
for CVE-2026-32721. It predates the DHCP lease field fix tracked by
GHSA-686p-p8p9-x6fh. The build applies
[`0020-luci-escape-dhcp-lease-fields.patch`](../patches/0020-luci-escape-dhcp-lease-fields.patch),
backporting upstream commit `55379d04fcc3` so lease hostnames and MAC vendor
strings are escaped before LuCI table rendering. Prepared-source and artifact
verification require both the earlier SSID text-node fix and this later DHCP
escaping fix.

## uMDNS cache exhaustion

The selected uMDNS revision already contained the parser fixes for
CVE-2026-30871 and CVE-2026-30872, but it preceded CVE-2026-55492's bounded
cache and TTL handling. A peer on an adjacent network could otherwise grow the
mDNS cache until the daemon exhausted memory.

The first-boot policy disables uMDNS because this AP does not use it. The source
also applies
[`0019-openwrt-update-umdns-security.patch`](../patches/0019-openwrt-update-umdns-security.patch),
using OpenWrt 25.12.5's fixed revision so package safety does not depend only on
service disablement.

## Already-fixed base components

The pinned OpenWrt base already selects procd
`2026.03.13~58eb263d-r1`, containing the `PATH=` filtering fix for
CVE-2026-30874, and jsonfilter `2026.03.16~b9034210-r1`, containing the
temporary lexer-string cleanup for CVE-2026-30873. Prepared-source and artifact
verification require those exact revisions.

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

## Reviewed non-installed advisories

The same 2026-08-28 review considered the other current OpenWrt and LuCI
repository advisories. The affected components are not selected in this image:

- EAD for CVE-2026-55490;
- `luci-lib-px5g` for GHSA-jgc3-4q3p-g6xh; and
- the affected HTTPS DNS proxy, adblock-fast, BMX7, banIP, UPnP, Travelmate,
  Advanced Reboot, OpenVPN protocol, Dockerman, Samba4, Tailscale Community,
  and LXC LuCI packages.

Artifact verification rejects those packages if they appear unexpectedly.

## Removed DHCP server

The inherited package selection included `odhcpd-ipv6only`, which is affected
by CVE-2026-62948's unauthenticated DHCPv6 hostname injection and stored LuCI
XSS chain. This AP is a bridge and does not provide DHCPv4 or DHCPv6 service.
The build therefore excludes both `odhcpd` server variants while retaining the
separate `odhcp6c` client. First boot still disables and stops `odhcpd` if a
future downstream dependency unexpectedly restores it, and artifact
verification rejects either server package.

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

The installed AP has the June uHTTPd revision and OpenSSL 3.5.7, HTTPS-only and
wired-only management, key-only SSH, restricted write surfaces, and more than
five days of continuous post-recovery operation. Network containment materially
reduces reachability but is not represented as a substitute for package fixes.

A clean local build completed on 2026-08-28. Artifact verification accepted the
corrected upgrade wrapper, fresh-boot DHCP DUID cleanup, idempotent
wireless-management nftables loading, uHTTPd
`2026.08.03~60f64bec-r1`, OpenSSL `3.5.8-r1`, cgi-io
`2026.07.21~31cb3c89-r1`, and uMDNS `2026.06.16~1b5e7bf1-r1`. It also confirmed
that LuCI's mount ACL and untrusted table fields were corrected and that
reviewed non-installed advisory packages, including both odhcpd server
variants, were absent.

That artifact remains private and has not been flashed. The wall-mounted AP
therefore still runs the earlier June uHTTPd revision and OpenSSL 3.5.7 under
the wired-only management containment described above. None of the newer
package corrections has been validated by another live installation.

Security fixes do not eliminate the hardware-recovery boundary. A failed NAND
or kernel boot still requires UART and TFTP.
