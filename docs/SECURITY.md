# Security findings and mitigations

This document records findings from a review of the pinned TIP/OpenWiFi source,
the generated firmware, and one installed NWA50BE. It describes this project's
specific mitigations, not the security posture of every TIP, OpenWrt, Qualcomm,
or Zyxel build.

No credential, device serial, MAC address, calibration hash, unlock token,
private network address, or administrator identity is included here.

The upstream advisory review in this document is current through 2026-08-28,
except where the October 2026 review below extends it through 2026-10-08.

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

An October 2026 check found that the `0011` pin also precedes the 2026-08-24
upstream commit `3aa7e1c7678` ("file: enforce Basic Auth realms for URL-prefix
handlers", GHSA-5cgm-8h9x-v28c). A configured Basic-Auth realm was never
evaluated for lua, ucode, and ubus URL-prefix handlers, so a realm-protected
prefix served through those handlers bypassed the realm entirely. No shipped
configuration defines a uhttpd realm, so this image is not affected as
configured, and the LuCI prefix remains session-authenticated. The pin should
still move past `3aa7e1c7678` before any realm is ever introduced, and the
August currency claim above was incorrect for this item: the fix commit was
public since 2026-08-24 even though the advisory itself was not.

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
October 2026 fingerprinting of the live unit (see the October review) shows
the 2026-09-17 image is installed there, so the fixed revision is in service.

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

Upstream merged further memory-safety fixes on 2026-09-29 (`15a507e0` cached
TXT record termination, `7ff43470` record allocation check, `126426e6`
full-address IPv6 source comparison) which are newer than that pin and, as of
2026-10-08, not carried by any OpenWrt release, so a further source-side
roll-forward remains open. uMDNS stays disabled at first boot, keeping this
version debt rather than an active exposure.

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
- bridge-family nftables drops for every ingress except the supported wired
  uplink, `eth0`, including renamed wireless and MLO interfaces.

Management services remain usable from the provisioned wired host while
wireless-originated management traffic is rejected before the IP allowlist.

The final claim in the preceding paragraph did not hold on the hardware: the
bridge-family drop does not take effect on this platform, which left the
address allowlist as the only on-device control for wireless clients. See
the October 2026 review below.

The September 17 review replaced interface-name patterns with the wired-port
allowlist above. Other bridge-port names, including VLAN subinterfaces such as
`eth0.10`, are denied by default and require deliberate review before use. This
is an ingress-interface check, not an independent VLAN-tag filter. Serial setup
now uses firewall reload so policy replacement occurs in one nftables transaction, avoiding the
unfiltered interval of stop/start. Changing the administrator address does not
by itself revoke every preexisting connection; this is not a revocation tool.

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

## October 2026 review

A review completed 2026-10-08 re-examined the pinned source, the 2026-09-17
candidate artifacts, the built kernel and package binaries, and the installed
validation unit against upstream state published through 2026-10-08. Earlier
reviews tracked OpenWrt, LuCI, uHTTPd, TIP wlan-ap, and schema advisories;
this round additionally covered the upstream w1.fi advisories for the vendored
`qca-wifi-7` hostapd feed, the OpenSSL 2026-09-29 advisory, and the current
upstream release tags. Items below are new relative to the sections above;
the dated updates further down record which have since been corrected.

### Installed-unit state (October 2026)

Live fingerprinting of the validation unit on 2026-10-08 established that it
runs the 2026-09-17 image: the served root page and bootstrap stylesheet are
byte-identical to that build's squashfs, with matching ETag and modification
timestamps, and a staged upgrade record in the work tree pins the flashed
sysupgrade image by SHA-256 to the 2026-09-17 postmerge packaging of the same
build. The statements in this document and in VALIDATION.md describing the
installed unit as still running the June uHTTPd revision, OpenSSL 3.5.7, the
2025.12.11 cgi-io, or the 2026.02 uMDNS describe the state before that
verified upgrade and should be read as history. The Vantage LuCI theme is
installed on the unit outside the build chain, as described below.

Live boundary checks from the provisioned wired administrator host on the
same occasion confirmed: a full TCP port scan of the unit finds only 22 and
443 open; cleartext HTTP is refused rather than dropped; the `/ubus` uHTTPd
RPC prefix is absent; HTTP keep-alive is disabled; conflicting
Content-Length and Transfer-Encoding headers are rejected; an oversized
header is rejected with 413; the TLS floor is TLS 1.2, with TLS 1.0 and 1.1
rejected by the server; and an 800-connection full-port sweep left uHTTPd
healthy, so the previously fixed listener-wedge conditions did not recur.
Follow-on checks from an associated wireless client found that the
bridge-family drop include described under Management-plane exposure does
not take effect on this platform: the bridge input hook never evaluates
frames delivered to the AP itself, so no rule placed in it can filter them.
On images built from earlier revisions of this repository the source-address
allowlist is therefore the only on-device control between a wireless client
and the SSH and HTTPS listeners, and an address allowlist is not a boundary
on a shared bridge. Such images do not confine management to the wired
port; move to a build with the gate described below. The verification chain
missed this because it compared the include file byte for byte and never
asserted that the loaded ruleset contains a live hook for the traffic it
governs. No IPv6 management path exists; the AP does not respond to
all-nodes multicast.

Update 2026-11-26: corrected in the source since the October 28 batch and
installed on the unit since October 31. The include now marks SSH and HTTPS
arriving on `eth0` in a netdev ingress chain (`nwa50be_mark`) and drops any
SSH or HTTPS reaching the AP's input hook without that mark (`nwa50be_gate`),
so a client on one of the AP's own wireless bridge ports cannot reach the
management services whatever source address it uses. Prepared-tree and
artifact verification check the shipped include, and
`scripts/check-live-management-gate.sh` checks the loaded tables on a unit.

Live check 2026-11-27 on the installed unit, with the gate loaded according
to that script: an on-device capture of packet headers while a phone
requested the HTTPS management address. From the SSID bridged onto the
management segment, the phone resolved the AP's address and its SYNs arrived
on the radio port and on `br-lan`; over two connection attempts and 17 SYNs
the AP sent nothing back. The gate rule does not match on the source
address, so the address a client uses makes no difference to it. From an
SSID on another VLAN the same request was forwarded by the upstream router,
arrived on `eth0`, passed the gate as wired ingress, and was refused with a
TCP reset by the fw4 address allowlist.

Scope of the gate: it separates wired from wireless ingress on the AP
itself. Traffic that an upstream router forwards from another network,
wireless or not, arrives on `eth0` and meets only the address allowlist.
Source-address validation and inter-VLAN policy for that path belong to the
router.

### hostapd multi-link parsing (high, over the air)

w1.fi advisory 2026-1 (CVE-2026-58374, published 2026-06-05) describes missing
validation of received multi-link (MLO, EHT, 802.11be) information in hostapd
and wpa_supplicant snapshots after v2.11 and before v2.12 when built with
`CONFIG_IEEE80211BE`. In AP mode a crafted management frame — an association
request carrying a malformed Basic Multi-Link Element — can terminate the
process or cause small memory corruption, without authentication or user
action.

The `qca-wifi-7` hostapd package pins snapshot `95ad7115` (2025-03-10) with
`CONFIG_IEEE80211BE=y` in both `hostapd-full.config` and
`wpa_supplicant-full.config`. None of its 51 patches backports the eight w1.fi
commits, and the affected link-ID handling is present in the built source
under `src/ap/ieee802_11.c`. OpenWrt's own feeds backported the fixes in
24.10.8 and 25.12.5; the TIP feed has not, and TIP `main` as of 2026-10-07
does not carry them.

This is an over-the-air exposure: the wired `/32` allowlist and the
bridge-family nftables rules do not reach it. The installed validation unit
runs the same `wpad-openssl 2025.03.10~95ad7115` build with the 6 GHz EHT
BSS active, so both the current source and the installed unit are exposed.
The single-link, non-MLO BSS configuration does not prevent a client from
sending the malformed element; the vulnerability is in parsing of received
frames, not in operating an MLD. Upstream assesses practical exploitation
beyond process termination as unlikely; the hardening gaps recorded below
reduce the margin that assessment depends on.

Remediation: backport the eight w1.fi commits into the `qca-wifi-7` hostapd
package as a new patch, extend prepared-source and artifact
verification, and include it in the next validated flash.

### Package currency backlogs (contained as shipped)

The 2026-09-17 source remains version-affected by the following advisories
disclosed or extended after the 2026-08-28 review. Each is contained today by
service disablement, missing exposure, or use pattern; all are roll-forward
candidates for the next source update.

- OpenSSL 3.5.8: CVE-2026-84782 (high; DTLS retransmission reads from a stale
  buffer offset, disclosing heap memory or crashing) plus low items
  CVE-2026-35189, CVE-2026-54872, CVE-2026-54875, CVE-2026-72897,
  CVE-2026-75805, CVE-2026-75806, and CVE-2026-77696 from the 2026-09-29
  advisory; all fixed in 3.5.9. No shipped service runs DTLS; radsecproxy is
  disabled at first boot, and the QUIC items in the same advisory do not apply
  because the QUIC stack is compiled out.
- dropbear 2025.89: the upstream 2026.90 and 2026.91 security fixes that
  OpenWrt backported in 25.12.4 (`2218cb19`, `6dead28`) are not in the TIP
  package. Contained by key-only authentication and by SSH staying disabled
  unless an authorized key is provisioned.
- curl and libcurl4 8.19.0: the 2026-06-24 batch fixed in 8.21.0 (15 CVEs,
  including CVE-2026-8925 SASL double-free and CVE-2026-10536 HTTP/2
  use-after-free) and the 2026-09-02 8.22.0 batch (CVE-2026-19931 Negotiate
  connection reuse and the remainder). No shipped service exposes libcurl to
  untrusted input; the cloud agent stays disabled and remote package feeds
  stay off.
- libevent 2.1.12: CVE-2026-63387 (evdns off-by-one stack write from a
  crafted DNS response) and the evhttp request-smuggling set including
  CVE-2026-63382. The consumers on this image, ucentral and rtty, are
  disabled and tmate is manual-only; no libevent HTTP server is shipped.
- libpcap 1.10.6: the 2026-09-05 batch (CVE-2026-0799, CVE-2026-31911,
  CVE-2026-31912, CVE-2026-6244, CVE-2026-6554 in the BPF interpreter; the
  rpcap items apply to a daemon that is not shipped). tcpdump is an
  interactive administrator tool.
- mbedtls 3.6.6: CVE-2026-25832 (TLS 1.3 client HelloRetryRequest group) and
  CVE-2026-73064 (random-generator fault affecting TLS 1.3 server ticket
  integrity), fixed in 3.6.7 with the July 2026 batch. Consumers are
  apk-mbedtls, whose feeds are disabled, and owner-initiated uclient-fetch.
- busybox 1.37.0: CVE-2026-88839, an out-of-bounds pointer write in the
  `/etc/passwd` and `/etc/group` parser (fix commit `c2dec52d3` on master,
  no release yet) — the vulnerable pattern is present in the built
  `libpwdgrp/pwd_grp.c`; plus CVE-2026-26157 (tar path traversal) and
  CVE-2026-38752 through 38755 (awk and ash denial of service) in applets
  that are built. The parser issue requires a malformed entry in root-owned
  input, so it is a robustness issue more than an exposure.
- wpad supplicant-side advisories (CVE-2026-78807 PMKSA bypass and the w1.fi
  2026-2/3/4 series) do not apply while the supplicant is not used in STA
  mode on this AP. w1.fi 2026-5, a RADIUS Message-Authenticator out-of-bounds
  access in hostapd, materializes only if 802.1X/RADIUS is configured later;
  it is recorded here before that happens.
- dnsmasq-full 2.91: the May 2026 CERT batch (CVE-2026-2291, CVE-2026-4890
  through 4893, CVE-2026-5172; fixed upstream in 2.92rel2 and 2.93) and
  CVE-2026-13002 (DNSSEC NSEC/NSEC3 bitmap loop, disclosed 2026-08-14). All
  require DNSSEC validation or resolver exposure; the service is disabled at
  first boot.
- libssh 0.11.3: the 2026-07-21 0.11.5 security release (CVE-2026-15370 SFTP
  longname stack overflow with potential code execution, CVE-2026-59843/44
  denial of service, CVE-2026-59850 use-after-free). The only consumer is the
  manual tmate binary.
- nghttp2 1.66.0: CVE-2026-27135 reachable assertion, fixed in 1.68.1; the
  library ships for libcurl.
- tmate 2.4.0 itself is not affected by its only advisory (CVE-2026-4751
  affects earlier versions), has no init script or UCI configuration, and
  starts only manually. Removing it would also remove the only libssh and a
  direct libevent consumer from the image.

### Kernel CVE backlog (class-level)

The kernel pin remains 6.6.88 while the 6.6 stable series advanced roughly 69
further releases through the end of September 2026, with the series' usual
continuous CVE stream. An itemized 6.6.88-to-current diff filtered to
compiled-in, network-reachable subsystems is still to be produced. The three
kernel CVEs added to the CISA KEV catalog on 2026-09-18 affect 6.6.88 by
version but are not compiled into this kernel (verified in the built
`.config`): `CONFIG_TLS` is unset (CVE-2025-39682 kTLS),
`CONFIG_BRIDGE_NF_EBTABLES` is unset (CVE-2026-53266 ebtables SNAT), and the
`CONFIG_CRYPTO_USER_API` family is unset (CVE-2025-39964 AF_ALG). Examples
that are compiled in: IPv6 (CVE-2026-53362 out-of-bounds write, fixed in
6.6.144) and rtmutex (CVE-2026-43499 use-after-free, fixed in 6.6.140). The
QCA vendor stack is pinned to this kernel version, so targeted backports are
preferred over a wholesale bump.

### Kernel and userspace hardening gaps

The built 6.6.88 kernel ships without KASLR (`CONFIG_RANDOMIZE_BASE` unset),
without `CONFIG_VMAP_STACK`, without `CONFIG_SLAB_FREELIST_RANDOM` or
`_HARDENED`, without `CONFIG_INIT_ON_ALLOC_DEFAULT_ON` or
`_FREE_DEFAULT_ON`, and without module signing. `CONFIG_BPF_UNPRIV_DEFAULT_OFF`
is unset. `CONFIG_DEBUG_INFO=y` reaches the shipped kernel despite the seed
disabling debug info, because the TIP kernel configuration supplies its own
complete symbol set. No shipped daemon binary compiles with stack canaries
(checked uhttpd, dropbear, dnsmasq, busybox, wpad, hostapd, ubusd, rpcd,
ssdk_sh, ucentral, and login), and busybox, tmate, ucentral, and login are
non-PIE; full RELRO and NX are present throughout. A memory-corruption
primitive in this image therefore meets a weaker hardening stack than the
project's other defenses suggest; the hostapd multi-link finding above is
the concrete case in point, since its AP-mode reachability is over the air.

### Setup-time password gate

[`overlay/root/nwa50be-setup`](../overlay/root/nwa50be-setup) runs `passwd`
once and then unconditionally enables and restarts `rpcd` and `uhttpd`.
The built busybox `passwd`, running as root, skips the weak-password check
entirely and accepts an empty entry, so an operator who completes the prompt
with an unusable value leaves the management services enabled with that
state. [`nwa50be-management-state`](../overlay/usr/libexec/nwa50be-management-state)
refuses an empty, locked, or missing root hash but is only invoked at
upgrade or uci-defaults time, not by the setup helper. The containment is
the wired `/32` allowlist; the fix is to re-run the management-state gate
after `passwd` and abort setup when it fails.

### ROM-state service containment

The inherited ROM ships the full TIP service set enabled, and its uHTTPd
configuration contains cleartext listeners. Containment depends on the
first-boot `uci-defaults` policy, which runs during early boot before the
firewall loads and before the first network service starts, rebuilding the
uHTTPd configuration as HTTPS-only, disabling the cloud services, and
restoring the REJECT-default firewall. Verified boot ordering closes the
practical window; the limitation is that the contained state is produced by
one-shot, configuration-state-dependent scripts rather than by the image
itself. Stripping the ROM configurations would make the contained state
independent of one-shot execution, upgrade restores, and future service
additions. The inherited ROM ucentral configuration also retains a
placeholder serial, a private development endpoint, and debug logging; the
rtty section created at first boot matches a disabled service. These are
inert while disabled but should not ship at all.

### Vantage theme integration

The Vantage LuCI theme and dashboard app are installed outside this build's
pinned seed, patch stack, and artifact verification chain, so shipped-image
verification cannot vouch for them. The audited server-side surfaces are
disciplined: the login template is data-free for unauthenticated visitors and
entity-encodes every echoed value, the rpcd plugin validates alias input
strictly (strict UTF-8 decoding with overlong and surrogate rejection,
bidi and control-character filtering, an icon allowlist, and a 512-section
bound), and its reduced wireless status omits key and credential fields.
The plugin's ubus `uci get` grant matches the stock LuCI baseline that all
authenticated sessions already hold, so it grants no additional
configuration access; the reverse-DNS ACL group is a deliberate, documented
DNS-probe primitive. The theme should be folded into the pinned seed and
artifact verification, and its client-side JavaScript audit completed.

### Upstream release currency

TIP `v5.1.0` remains the newest release; `main` is 10 commits past it as of
2026-10-07 and is visibly preparing `v5.1.1` (ucentral version.json bumped to
5.1.1), including a hostapd netlink message-leak fix (`26a47519`) and a
rebase onto the OpenWrt 25.12.5 baseline — but not the hostapd multi-link
backports. The vendored OpenWrt snapshot (`6639b15f62`) is effectively
25.12.3 minus one commit; 25.12.4 and 25.12.5 exist, carrying the dropbear
2026.90/91 backports among roughly 139 commits. The uhttpd realm fix
(`3aa7e1c7678`) and the umdns 2026-09-29 fixes exist only on upstream master;
no release carries them yet, so patch-level roll-forwards remain the
mechanism for those regardless of base rebase timing.

Update 2026-10-28: upstream tagged `v5.1.1-rc1` on 2026-10-23 at the head of
`release/v5.1.0`, 18 commits past `v5.1.0`, and the source now targets it (see
the verification boundary below and [BUILD.md](BUILD.md)). `main` has since
moved to the OpenWrt 25.12.5 baseline and begun 5.2.0; the release branch has
not, so the dropbear backports still need that base move or a patch-level
roll-forward. Of the items in this review, only the hostapd netlink leak fix
is carried by the new tag.

Update 2026-10-31: the fork stays on `v5.1.1-rc1` and OpenWrt `v25.12.3` and
rolls the fixes forward as patches instead of moving to the 25.12.5 baseline
(TIP had to revert and patch regressions that baseline introduced, for
example the `config_generate` move and the ubus `GRND_INSECURE` flag). Patches
0040 to 0045 add:

- musl 1.2.5: CVE-2026-40200 (qsort stack corruption on large inputs) and
  CVE-2026-6042 (iconv gb18030 decoder DoS), from openwrt-25.12 `084cdacf9d`.
  Every dynamically linked program uses this libc.
- dnsmasq-full 2.93: OpenWrt main's October batch (CVE-2026-93006 to 93009,
  93011 and two fixes without a CVE id) plus four newer upstream commits: the
  query id disclosure that makes cache poisoning cheap (2.91 to 2.93), a
  double free in `blockdata_expand()` and a TFTP root escape. CVE-2026-93010
  has no upstream commit in any tree that was checked and is not covered.
- dropbear 2025.89: the security fixes of 2026.92 and 2026.93 (authorized_keys
  line splitting that could bypass `command=`, `permitopen` port range,
  deferred KEX queue bound, `-t` with `-B`, scp filename escaping). Fixes for
  X11, ECDSA, askpass and utmp are not built in this configuration and were
  left out. Open: upstream commits `17549ea6` (more scp escaping) and
  `59870ad4` (channel packet size 0), and CVE-2026-3706 (not exploitable over
  SSH per the maintainer).
- busybox 1.37.0: the upstream tar fixes for CVE-2026-108119 (a symlink plus
  hardlink pair could place a file outside the extraction directory) and our
  own fix for CVE-2026-88833 (udhcpc crash on a short IP total length from
  an adjacent host). The udhcpc change is not an upstream commit; replace it
  when busybox ships one.
- zlib 1.3.1: CVE-2026-27171 (`crc32_combine` never terminates for negative
  lengths). No binary in the image calls it.
- Linux 6.6.88 (patch 0046): CVE-2026-98432, a use-after-free of a request
  socket's IPv4 options when a retransmitted SYN races the end of the
  handshake on another CPU (fixed upstream in 6.6.159). It needs a SYN that
  carries IPv4 options sent to a listening TCP port; the wireless gate stops
  such SYNs to 22 and 443 from the AP's own wireless bridge ports before TCP
  sees them (not traffic a router forwards to `eth0`), but not to other
  listening ports.

Later on 2026-10-31, patches 0047 to 0049 close the items left open above:

- dropbear moves to 2026.94 (patch 0047) instead of carrying cherry-picks.
  That adds what the cherry-picks never had: the curve25519 S < L and
  y < p checks (CVE-2026-3706), a cap of 15 public key queries per
  session, no signals under a forced command or without dropped
  privileges, RSA exponent blinding, O_NOFOLLOW for scp and dropbearkey
  output, a 300-line authorized_keys cap, an FD_SET overflow check and an
  ECDSA curve identifier out-of-bounds read. Upstream 59870ad4 and
  17549ea6 come on top. 17549ea6 itself drops the 0x01 marker of scp's
  recoverable errors, so one missing file aborted a batch transfer; our
  patch 003 keeps the marker (reproduced and fixed with OpenSSH `scp -O`).
- dnsmasq (patch 0048) gets twelve more upstream fixes, among them a DS
  reply loop, an `accept()` busy loop, inherited listening sockets in TCP
  children, a log-file chown through a symlink, a TFTP descriptor leak and
  unvalidated `DNSMASQ_SUPPLIED_HOSTNAME`. CVE-2026-93010 (leasequery
  answered any host when no permitted source is configured) has no
  upstream fix; our patch 026 makes it fail closed and log once. dnsmasq
  is disabled on the NWA50BE and OpenWrt's init script cannot enable
  leasequery, so neither was reachable on this unit.
- Not a security fix, but found at the same time (patch 0049): TIP's
  board.d took the whole kernel command line as the MAC when U-Boot passes
  no `hwaddr=`, so the label MAC, `system.mac`, the ucentral serial and,
  through `99-ucentral-hostname`, the hostname became
  `console=ttymsm0,115200n8`. That script also overwrote any hostname the
  user set after every upgrade.

Update 2026-11-26: the pin moves to the TIP `v5.1.1` release (three commits
past `v5.1.1-rc1`, multi-PSK only; mpskd stays disabled). OpenWrt published
no release after `v25.12.6`, and TIP's `v5.2.0-rc1` comes from `main` on the
25.12.5 baseline, so the base stays and patches 0050 to 0060 carry:

- uhttpd 2026-11-05 (patch 0054): a chunked request split across packets
  could abort uhttpd before authentication, and three connections that
  announce a body and stop sending held all script slots, blocking LuCI.
  Both were reachable on 443 from the wired management address. A
  per-source script slot cap (default 2 of the 3 slots) queues, rather
  than refuses, a source's extra requests.
- Linux 6.6.88 (patch 0052): CVE-2026-99288, where a SYN flood to a
  listening port can make the established-socket lookup dereference a
  NULL listener; with `PANIC_ON_OOPS=y` any wired LAN host could reboot
  the AP. The wireless gate drops SYNs to 22 and 443 from the AP's own
  wireless bridge ports before TCP sees them. Also CVE-2026-98255 (old ACKs on the fast path), CVE-2026-98532,
  CVE-2026-99076/99077 (UDP exceptions created before socket matching) and
  CVE-2026-99805 (VLAN-0 tag depth), plus TIP's own nf_tables and
  posix-cpu-timers backports. The ath12k WBM error-path hardening that
  `v5.2.0-rc1` lists (6641626b) is already in `v5.1.1` as ab296b5b.
- rpcd 2026-10-04 (0050) with the LuCI ACL companion (0055): the file
  plugin now re-checks ACLs against the resolved path, plus use-after-free
  and overflow fixes. This unit has only the root login, so the ACL bypass
  itself grants nothing here; the memory-safety fixes apply to any
  session.
- LuCI session tokens come from `/dev/urandom` (0057) instead of a
  `math.rand()` generator seeded with the request time.
- musl `regcomp()` overflows (0053), libubox hardening (0056), Mbed TLS
  3.6.8 for apk's HTTPS client (0060), ca-certificates 20260816 (0051),
  busybox nslookup reply checks (0059), and a dnsmasq caching regression
  that 0041 introduced (0058).

Not taken: OpenSSL 3.5.10 (not yet released; the open issues are in QUIC,
DTLS, CMS, DANE and GCM-SIV, none used here), zlib 1.4, ucode 2026-07-09
(it needs coordinated rpcd, LuCI and TIP nl80211 changes), odhcp6c (not running: no DHCPv6 interface), hostapd's
FT-PSK VLAN fix (per-PSK VLANs with 802.11r are not used), and ppp,
radsecproxy and logd fixes (not running, or local only).

Update 2026-11-27: this stack, together with patches 0061 to 0063, is
installed on the validation unit; see
[VALIDATION.md](VALIDATION.md#installed-image-2026-11-27).

### Remediation order

1. Wireless management containment (see the installed-unit state section):
   corrected by the wired-ingress mark and input gate, and checked live on
   2026-11-27. Routed traffic from other networks stays the upstream
   router's to police.
2. Backport the w1.fi 2026-1 hostapd commits as the next patch; extend
   verification.
3. Record the 2026-09-19 verified upgrade of the installed unit to the
   2026-09-17 image in VALIDATION.md; the next flash after the fixes above
   should again go through `nwa50be-sysupgrade`.
3. Move the `0011` uHTTPd pin past `3aa7e1c7678`.
4. Roll OpenSSL forward to 3.5.9 as the successor to `0012`.
5. Re-run the management-state gate after `passwd` in the setup helper.
6. Roll the low-reachability package set forward (dropbear, umdns, curl,
   libevent, libpcap, mbedtls, busybox cherry-pick, nghttp2, libssh), or
   remove tmate and its library consumers.
7. Produce the itemized 6.6.88 kernel CVE diff and apply targeted backports.
8. Evaluate kernel hardening options (KASLR, `VMAP_STACK`, freelist
   hardening) and compiler hardening for shipped binaries; strip ROM service
   state; and anchor artifact verification outside the build tree before any
   binary release.

## Verification boundary

### TIP 5.1.1-rc1 update: reviewed upstream delta

The October 28 update moves the pin from
`5b797b292359436ccf17d5d367a46bda75fc260a` to
`20561633308643cb0d14b6aa72a9df9ed925add2` (`v5.1.1-rc1`, a prerelease tagged
2026-10-23). The 18-commit delta was read in full. The OpenWrt base, its
125-patch result, the feeds, the kernel baseline, flash geometry, calibration,
and the NWA50BE device tree are unchanged, and all 22 project patches apply
without modification. Reviewed items:

- **ath12k WBM error path.** `ath12k_wifi7_dp_rx_process_wbm_err()` no longer
  trusts the descriptor address written back by hardware cookie conversion. It
  derives the owning device from the software cookie, consistent with the
  per-device page-table base of `device_id * ATH12K_NUM_RX_SPT_PAGES`,
  resolves the descriptor in that device's pool, and skips entries whose
  magic, socket buffer, or owner do not match instead of freeing memory it
  cannot vouch for. This hardens a receive path that any wireless peer can
  feed; the previous code could act on a corrupt descriptor. Skipped entries
  are left to the owning device's cleanup rather than freed here, the safer
  side of that trade. Lock handling in the changed block is unchanged, and the
  new counters stay within `WBM_ERR_DROP_MAX`.
- **hostapd station hooks.** The Wi-Fi 7 hostapd gains the `sta_auth` and
  `sta_connected` ucode hooks and the MPSK roaming VLAN logic from the Wi-Fi 6
  tree. `sta_auth` runs for every authentication that allocates a station and
  replaces the station's PSK list only when a ubus subscriber answers with one.
  The packaged `hostapd.uc` forwards both hooks as notifications on the
  `hostapd-auth` object with a one-second timeout; with `mpskd` disabled at
  first boot there is no subscriber, the hooks return empty objects, and
  authentication proceeds as before. The code is compiled in regardless; the
  new per-station `sae_pt` allocation is released in `ap_free_sta()`.
- **hostapd netlink leak.** `wpa_driver_nl80211_set_ttlm_link_mapping()`
  allocated a message and then overwrote it with a second allocation; the
  first is removed. MLO stays disabled here, so the path is not exercised.
- **Kernel pstore.** `CONFIG_PSTORE`, `CONFIG_PSTORE_CONSOLE`,
  `CONFIG_PSTORE_PMSG`, and `CONFIG_PSTORE_RAM` are enabled in the shared
  ipq53xx kernel configuration for EAP105 crash logs. The NWA50BE device tree
  already declares `ramoops@49c00000` (1 MiB; 128 KiB record, console, and
  pmsg sizes) directly above the TrustZone application region at
  `0x49600000`-`0x49c00000`, with no overlap, so the driver now binds on this
  board and OpenWrt's boot script mounts `/sys/fs/pstore` with
  `nosuid,nodev,noexec`. The previous boot's kernel console and pmsg records
  are expected to become readable by root after a warm reboot, provided the
  boot firmware leaves that RAM intact; retention has not been tested on the
  hardware. They do not survive a power cycle and are never written to
  flash. This widens what an administrator session can read, not what an
  unauthenticated peer can reach.
- **uCentral.** `version.json` reports 5.1.1 and the schema moves to
  `e2934931` (scan restricted to the requested frequency, one regulatory
  domain for radio country codes, bridge rendering, schema version 5.1.1).
  The client stays disabled; the artifact assertions were updated.

The updated `mpskd` is installed but stays disabled at first boot; the
Wi-Fi 6, ipq807x, and EAP105 changes do not reach this image. The update
does not include the hostapd multi-link validation fix
(CVE-2026-58374), the uHTTPd realm fix, OpenSSL 3.5.9, the uMDNS September
fixes, or the dropbear backports that upstream `main` obtains from its OpenWrt
25.12.5 baseline; the October remediation order above stands.

Three independent reads of this delta were made: one agent and two Codex
runs. The ath12k read found no issue for
this configuration and noted two low items that need no change here: the
telemetry vendor enum was not extended for the three new WBM drop reasons,
so a telemetry event can carry attributes beyond
`QCA_VENDOR_ATTR_WBM_SW_DROP_MAX` (telemetry consumers are disabled), and
the cookie arithmetic depends on a descriptor-count module parameter that
stays writable after initialization (root-only and never changed here).
Findings that need MPSK or RADIUS (a stale per-station SAE `pt` after a
password change, a wrong MPSK index with mixed raw-key lists, ignored VLAN
binding failures, and a synchronous one-second notification that can stall
hostapd while `mpskd` runs) do not apply while `mpskd` stays disabled and
are recorded for the day it is enabled.

### TIP 5.1.0 update: corrected stale-peer locking regression

The September 17 update reviews TIP commit
`122d893d88a6762bffeac54c5f87b37407cefe7a` through
`5b797b292359436ccf17d5d367a46bda75fc260a`, including the three-commit
ucentral-schema dependency update. The main review and two independent
upstream-delta passes identified one new release blocker before remediation.
Prior local-hardening findings were already known, limiting historical review
independence. No second new finding was established in the reviewed delta;
this is not a full audit of the existing kernel, vendor stack, or firmware blobs.

**TIP-001: unmatched ath12k lock release** (medium severity, availability;
high confidence; release blocking until corrected).
The new upstream stale-peer patch releases `dp_lock`, calls
`ath12k_peer_delete()` with the lock unheld, then releases it a second time
before reacquiring it. The deletion helpers balance their own lock sections
and return unlocked. On successful deletion of a stale same-radio,
different-VAP, non-MLO peer, this violates lock ownership and bottom-half
accounting and can destabilize the kernel or Wi-Fi service.

Affected code is `ath12k_peer_create()` in the
[pinned upstream stale-peer patch](https://github.com/Telecominfraproject/wlan-ap/blob/5b797b292359436ccf17d5d367a46bda75fc260a/feeds/qca-wifi-7/mac80211/patches/ath12k/0002-QSDK-wifi-ath12k-peer-create-delete-stale-same-pdev-peer.patch#L85),
specifically the releases at patch lines 70 and 85 around the deletion at 77.
Normal client activity or a client deliberately requesting a new association
can enter peer creation, but the stale-peer precondition below is material.

An ordinary active duplicate can be rejected earlier by the station-address
hash. A failed earlier teardown can leave a datapath peer after removing that
hash entry, which makes the new recovery branch relevant. A reliable
unauthenticated over-the-air crash or code-execution path was not established.
Patch `0021` removes only the redundant release and retains the bounded
recheck under the reacquired lock.

`scripts/test-ath12k-peer-lock.py` compiles the actual collision block with
instrumented host C lock/deletion stubs. The unmodified upstream code fails
the successful-delete and still-present-peer cases; the corrected block passes
all six cases, also covering no peer, same VAP, existing MLO, and deletion
failure. Artifact verification runs this check against the prepared driver
source. This does not emulate firmware completion, concurrent CPUs, or full
station teardown; hardware reassociation and stability testing remain required.

The updated hostapd configuration string flows from trusted root-owned UCI
configuration to structured ubus output. Updated cloud/event consumers remain
disabled; cloud LuCI and `bridger` remain excluded. Flash geometry, calibration,
regulatory configuration, and the kernel baseline are unchanged by this update.

The Sonatype connection was unavailable, so no dependency-database clearance
is claimed. A September 17 refresh of published GitHub advisories for
OpenWrt core, LuCI, uHTTPd, TIP wlan-ap, and wlan-ucentral-schema found no new
entries since the prior review. This scoped check does not replace a complete
dependency or vendor-firmware audit.

The inspected delta covers source pinning/preparation and release provenance;
ath12k peer lookup/deletion and adjacent station cleanup; hostapd shell/ucode
configuration, string ownership, and ubus serialization; ucentral-event bridge
lookup and RPC; schema rendering; the excluded Maverick profile updater; and
upstream CI/version metadata. The unchanged standalone upgrade and management
policy is an integration boundary, not a newly complete audit of every helper.
The build host, its toolchain/PATH, and local root administrator are trusted;
wireless and other wired peers are not. Firmware timing, kernel concurrency,
NAND failure recovery, proprietary blobs, and host compromise were not proven
by this review. Maintainer-owned hardware acceptance remains unchecked in
[VALIDATION.md](VALIDATION.md#final-image-hardware-acceptance-gate).

### Restored configuration erased by cloud provisioning defaults

A September 17 review of the complete startup sequence found a second,
independent configuration-loss path in the August 28 candidate. After backup
restoration, `99-ucentral-network` removes network interfaces/devices and
firewall sections. `zzz-ucentral` commits those deletions and regenerates the
network when no cloud configuration shadow is restored. The final local policy
sees the preserved setup marker and intentionally leaves the network untouched,
so the wired LAN can be lost despite a valid backup and successful image test.

This standalone image now overrides both cloud defaults with no-ops at their
original paths. The local first-boot policy remains responsible for fresh
setup, management containment, and retaining provisioned networking. Regression
tests execute these overrides before the local policy; artifact verification
byte-compares both packaged files against the reviewed overlay. This corrects
the startup interaction; hardware upgrade acceptance is still required.

### Earlier validation

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
