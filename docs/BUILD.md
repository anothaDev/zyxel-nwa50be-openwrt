# Build

## Inputs

The build is pinned to:

- TIP/OpenWiFi tag `v5.1.1` (release; same commit as `v5.1.1-rc2`)
- TIP commit `f18e1f560b50998b759a3d837a320d911d7d8584`
- OpenWrt base commit `a5652f421c6f6e548fb801a93b2cd2ae13eca631`
- TIP-patched OpenWrt tree `6dce2f66f457d2f4de0046da03bfd0d85577aba0`

The TIP tag is lightweight and unsigned. The OpenWrt `v25.12.3` tag was signed,
but this project consumes TIP's 125-patch OpenWrt result and records its Git
tree object separately. The generated commit ID is intentionally not pinned
because committer metadata changes it without changing source content.

### Upstream refresh checkpoint: 2026-11-26

TIP tagged `v5.1.1` (and `v5.1.1-rc2`) on November 2 at commit
`f18e1f560b50998b759a3d837a320d911d7d8584`, three commits past `v5.1.1-rc1`
([comparison](https://github.com/Telecominfraproject/wlan-ap/compare/v5.1.1-rc1...v5.1.1)):
mpskd re-applies a cached VLAN on 6 GHz PMKSA reconnects, and the Wi-Fi
scripts pass `multi_psk` to mpskd. This image keeps mpskd disabled. The
OpenWrt base, the 125-patch tree object, the feeds and the kernel are
unchanged. `v5.2.0-rc1` (November 15) comes from `main` on the OpenWrt
25.12.5 baseline and is not adopted; its rpcd update, ca-certificates update
and two 6.6.88 kernel backports are taken as patches 0050, 0051 and 0052.
OpenWrt has published no release after `v25.12.6`.

Patches 0062 and 0063 and one first-boot setting, also added on 2026-11-27,
come from a review of this change set: 0052's established-lookup fix
leaned on two later stable commits and left a third open, the rpcd update
made two LuCI views read through paths that were no longer granted, and
the new per-source limit in uhttpd left the single management address two
of the three script slots. `max_requests_per_source` is now set to 3.

Patch 0061, added on 2026-11-27, is not from that refresh: the Wi-Fi 7
overlay's hostapd answered "no" to `hostapd -v11be`, which made LuCI show an
empty Mode field for a radio set to BE.

### Upstream refresh checkpoint: 2026-10-28

[TIP/OpenWiFi v5.1.1-rc1](https://github.com/Telecominfraproject/wlan-ap/releases/tag/v5.1.1-rc1)
was tagged on October 23 at commit
`20561633308643cb0d14b6aa72a9df9ed925add2`, the head of the `release/v5.1.0`
branch, and is marked as a prerelease. It is 18 commits ahead of `v5.1.0`
([comparison](https://github.com/Telecominfraproject/wlan-ap/compare/v5.1.0...v5.1.1-rc1))
and keeps the NWA50BE profile, the OpenWrt base pin, the 125-patch OpenWrt
result (the same tree object), the feeds, and the kernel baseline. The release
branch does not carry upstream `main`'s move to the OpenWrt 25.12.5 baseline
or its 5.2.0 preparation. The GitHub release has no uploaded firmware assets.

Changes in the delta that reach this image:

- ath12k: the WBM error path resolves the receive descriptor from the software
  cookie, including the owning device, and cross-checks the hardware-written
  address instead of trusting it; three error counters are added.
- hostapd (`qca-wifi-7`): a netlink message leak in TID-to-link mapping is
  fixed, and the `sta_auth`/`sta_connected` ucode station hooks plus the MPSK
  roaming VLAN patches are ported from the Wi-Fi 6 tree. The hooks act only
  when a ubus subscriber such as `mpskd` answers, and the RADIUS VLAN caching
  only with dynamic VLANs; the updated `mpskd` is installed but disabled at
  first boot.
- ipq53xx kernel configuration: `CONFIG_PSTORE`, `CONFIG_PSTORE_CONSOLE`,
  `CONFIG_PSTORE_PMSG`, and `CONFIG_PSTORE_RAM` are enabled for EAP105 crash
  logs. The NWA50BE device tree already declares a 1 MiB `ramoops` region at
  `0x49c00000`, so this kernel mounts `/sys/fs/pstore` and is expected to
  keep the previous boot's console and pmsg records across a warm reboot if
  the boot firmware leaves that RAM intact; retention is untested here.
- uCentral: `version.json` reports 5.1.1 and the schema moves to `e2934931`.
  The client remains disabled.

The qca-wifi-6, ipq807x, and EAP105 device-tree changes do not apply here.

This repository now targets that prerelease. All 22 existing project patches
apply unchanged; the pinned TIP commit, the schema revision, and the version
labels in `prepare-tree.sh`, `verify-prepared-tree.sh`, and
`verify-artifacts.sh` changed. The update does not include the hostapd
multi-link validation fix (CVE-2026-58374) or the other open items in
[SECURITY.md](SECURITY.md#october-2026-review); those remain separate
backports. The candidate is not hardware-validated.

### Upstream refresh checkpoint: 2026-09-17

[TIP/OpenWiFi v5.1.0 final](https://github.com/Telecominfraproject/wlan-ap/releases/tag/v5.1.0)
was released on September 1 at commit
`5b797b292359436ccf17d5d367a46bda75fc260a`. It retains the NWA50BE profile
and is 12 commits ahead of this project's previous release candidate. The
[comparison](https://github.com/Telecominfraproject/wlan-ap/compare/122d893d88a6762bffeac54c5f87b37407cefe7a...v5.1.0)
includes a same-radio cross-VAP ath12k stale-peer fix and hostapd/uCentral
configuration and strict-forwarding fixes; it does not change the OpenWrt base
pin or the kernel baseline. The GitHub release has no uploaded firmware assets.

This repository then tracked that release while retaining the local hardening,
configuration-preservation, flash-boundary, and explicit-MLO policies. Review
found an unmatched lock release in the new stale-peer path; patch `0021`
corrects it. The source-derived lock regression rejects the unmodified final
release and checks six control-flow cases after correction. See
[SECURITY.md](SECURITY.md) for reachability and test limits.

Artifact validation also rejected a joined `v5.1.0-rc2 v5.1.0` label: both
tags identify the same commit. Patch `0022` selects one exact tag, preferring
final over prerelease. Five real-Git test cases cover duplicate tags,
annotated prereleases, and untagged development commits.

The final-release candidate still needs hardware upgrade and wireless
acceptance. An upstream cloud image is not a substitute for this standalone
image or its device-specific calibration and management policy.

## Project patch stack

| Patch | Purpose |
| --- | --- |
| `0001` | Select QCN6432 wide-band mode 2, align remoteproc memory, and keep both flash controllers disabled for RAM testing. |
| `0002` | Force the embedded initramfs payload to rebuild instead of reusing a stale kernel object. |
| `0003` | Point the external ipq53xx feed at OpenWrt's real initramfs device list. |
| `0004` | Require explicit MLO enablement; the default remains off. |
| `0005` | Expose only the reviewed serial-NAND layout for persistence while keeping SPI NOR disabled. |
| `0006` | Preserve local ath12k module policy when the vendor debug helper runs. |
| `0007` | Apply an upstream ucode const-correctness fix required by current host compilers. |
| `0008` | Force only the nested qca-ssdk-shell source build to remain serial. |
| `0009` | Ignore qca-nss-phy's empty package-assembly init-script probe. |
| `0010` | Keep absolute external-feed paths out of APK package-origin metadata. |
| `0011` | Update uHTTPd through the 2026-08-03 upstream security fixes. |
| `0012` | Update to the OpenSSL 3.5.8 security release. |
| `0013` | Remove TIP's public development root password before first boot. |
| `0014` | Remove LuCI's package-manager dependency for this downstream target. |
| `0015` | Select the SSDK profile init script without modifying tracked source. |
| `0016` | Disable unused OpenSSL QUIC code, removing the CVE-2026-14456 attack surface. |
| `0017` | Update cgi-io past CVE-2026-62947. |
| `0018` | Remove LuCI mount management's stale root-crontab write grant. |
| `0019` | Update uMDNS past CVE-2026-55492. |
| `0020` | Escape untrusted DHCP lease fields before LuCI table rendering. |
| `0021` | Remove an unmatched ath12k lock release in TIP 5.1.0 stale-peer recovery. |
| `0022` | Select one exact TIP release label, preferring final over prerelease tags on the same commit. |
| `0024` | Backport the w1.fi 2026-1 multi-link validation fixes (6 of 8 commits) into hostapd. |
| `0025` | Backport the w1.fi 2026-5 RADIUS Message-Authenticator fix into hostapd. |
| `0026` | Update OpenSSL to 3.5.9. |
| `0027` | Update uhttpd to the 2026-10-19 revision (Basic Auth realm check, ubus `list` parameter validation). |
| `0028` | Update umdns to the 2026-10-04 revision. |
| `0029` | Update dropbear to 2025.89-r3 with the upstream fixes. |
| `0030` | Backport the BusyBox 1.37.0-r7 security fixes. |
| `0031` | Update dnsmasq to 2.93. |
| `0032` | Update mbedTLS to 3.6.7. |
| `0033` | Update libpcap to 1.10.7. |
| `0034` | Update curl to 8.23.0. |
| `0035` | Update nghttp2 to 1.70.0. |
| `0036` | Update libevent2 to 2.1.13. |
| `0037` | Update libssh to 0.12.2-r2. |
| `0038` | Keep pstore disabled, matching the hardware-validated kernel configuration. |
| `0039` | Give each forked uhttpd worker its own ubus connection in LuCI's dispatcher. Workers inherited the parent's socket, which the parent also reads, so on four CPUs the reply was lost and every LuCI request that made a ubus call, including the login page, hung its worker and then blocked uhttpd. |
| `0040` | Backport the musl fixes for CVE-2026-40200 (qsort stack corruption) and CVE-2026-6042 (iconv gb18030 decoder DoS) from openwrt-25.12 (084cdacf9d). |
| `0041` | Backport OpenWrt main's October 2026 dnsmasq batch (6db25ee835) onto 2.93: CVE-2026-93006 to 93009 and 93011, plus two fixes without a CVE id. |
| `0042` | Backport the security fixes of dropbear 2026.92 and 2026.93 as patch files: authorized_keys line splitting, `-t` with `-B`, KEX reply queue bound, `permitopen` port range, packet length overflow, scp filename escaping. |
| `0043` | busybox: two upstream tar fixes (`..` as unsafe name, symlink plus hardlink escape, CVE-2026-108119) and our own udhcpc fix for CVE-2026-88833, which has no upstream fix yet. Drop the udhcpc part when busybox ships one. |
| `0044` | zlib: reject negative lengths in `crc32_combine` (upstream ba829a458576, CVE-2026-27171). |
| `0045` | dnsmasq: four upstream fixes newer than 2.93 that main's batch lacks: query id disclosure in error replies (two commits), a double free in `blockdata_expand()`, and a TFTP directory escape. |
| `0046` | Kernel: free IPv4 socket and request options after an RCU grace period (upstream e3f33b0a1d89, stable 742f73df544e, CVE-2026-98432; fixed in 6.6.159, the ipq53xx kernel is 6.6.88). |
| `0047` | dropbear 2026.94 from OpenWrt main's package (Makefile, Config.in, patches 100 to 901), replacing the 2025.89 cherry-picks of 0029 and 0042, plus upstream 59870ad4 (channel max packet) and 17549ea6 (scp terminal escaping) and our fix 003 for the scp error marker 17549ea6 drops. The 25.12 init and failsafe scripts stay. |
| `0048` | dnsmasq: OpenWrt main's SIGHUP slowdown fix (001, 002), twelve more upstream fixes newer than 2.93 (014 to 025), and our fix 026 for CVE-2026-93010: `--leasequery` without a permitted source now ignores lease queries instead of answering any host. |
| `0049` | Zyxel NWA50BE/NWA130BE/NWA210BE: accept `hwaddr=` only as a valid unicast MAC (the NWA50BE falls back to the SoC-serial address eth0 already uses), and make `99-ucentral-hostname` keep a valid hostname after upgrades instead of overwriting it from the label MAC. |
| `0050` | rpcd to Git HEAD 2026-10-04 from openwrt-25.12 (file ACL re-checked against the resolved path, use-after-free and overflow fixes), with TIP's refreshed `100-guard-he-eht-fields.patch`. |
| `0051` | ca-certificates 20260816 from openwrt-25.12, including the emSign ECC Root CA - G3 and Comodo AAA blacklist. |
| `0052` | Kernel 6.6.88 network backports: TIP's nf_tables `addchain` and posix-cpu-timers fixes, and linux-6.6.y fixes for CVE-2026-99288 (remote crash through the established-socket lookup) with its prerequisites, CVE-2026-98255, CVE-2026-98532, CVE-2026-99076, CVE-2026-99077 and CVE-2026-99805. |
| `0053` | musl: integer overflows in `regcomp()` (CVE-2026-107891), from openwrt-25.12. |
| `0054` | uhttpd to Git HEAD 2026-11-05 from openwrt-25.12: pre-authentication parser abort, script slots held by abandoned request bodies, a per-source script slot cap (`max_requests_per_source`), and the ubus list encoding bound. |
| `0055` | LuCI: rpcd ACL patterns for symlinked `/proc` paths (needed with 0050) and escaped URL and user name in dispatcher logs. |
| `0056` | libubox to openwrt-25.12 Git HEAD 2026-11-03 (blob, blobmsg, JSON and usock overflow fixes; ABI unchanged). |
| `0057` | LuCI: session token from `/dev/urandom` instead of a time-seeded `math.rand()` (luci master df71c66019). |
| `0058` | dnsmasq: cache SOA and non-address records again (upstream 10fbc39, a regression from 0041's 009). |
| `0059` | busybox: nslookup reply length checks (upstream c64ffa2e2). |
| `0060` | Mbed TLS 3.6.8 (security release; used by apk for HTTPS). |
| `0061` | hostapd: answer the 802.11be build feature query, so LuCI offers BE in the Mode list (the `build_features.h` hunk of OpenWrt b1d6068330). |
| `0062` | Kernel 6.6.88: three more linux-6.6.y commits completing 0052. The full socket replaces the request socket in the established hash in one step (ad12d25edbbe, 23b2b6af8dc6), and a request dropped after a failed listener migration is accounted to its own listener (07d77d774f71). |
| `0063` | LuCI: permissions for the resolved paths rpcd checks since 0050, for bridge port options and the IPv6 diagnostics test. Not upstream as of 2026-11-25. |

`qca-ssdk-shell` has a broken generated-dependency bootstrap. After target
kernel compilation, the build runs it at `-j1` for at most six passes before
the parallel world build. Each permitted failed pass must generate dependencies
and end on the exact missing-`.d` rule; any compiler or linker error aborts
immediately. Running it after target compilation matters because that phase
recreates the target build directory. A clean tree succeeded on pass 5. This
avoids redistributing a patch from a source repository that does not state
redistribution terms.

If an incremental rebuild fails in libradcli's install hook because
`libfreeradius-client.so` already exists, clean only that package's generated
output with `make -C <prepared-tree>/openwrt package/feeds/packages/libradcli/clean`
and rerun the build. This does not change its source or version; do not ignore
the failed install or treat its incomplete output as an accepted image.

TIP's Kconfig currently prints recursive-dependency diagnostics for the
unselected `kmod-qca-nss-ecm-premium`, `kmod-qca-nss-ecm-wifi-plugin`,
`cig-device-boot`, and `kmod-usb-serial-xr` packages during `defconfig`. The
verifier requires all four to remain unselected; treat a selected symbol or a
nonzero `defconfig` exit as a failure.

## Host requirements

Use a recent Linux distribution with the normal OpenWrt build dependencies,
Git, Python 3 with PyYAML, a host C compiler (`cc`), rsync, GNU make, `flock`,
`fdtget` (normally provided by a device-tree-compiler package), and enough disk
space for a complete ipq53xx
build. The scripts use every available CPU by default; override with `JOBS`.
One repository-level lock prevents concurrent builds from corrupting shared
OpenWrt staging state.

## Private ART input

The build requires an exact 1 MiB ART dump from the target AP. Store it outside
the repository. `prepare-tree.sh` verifies its size and extracts:

| Radio | ART offset | Size | Image destination |
| --- | ---: | ---: | --- |
| IPQ5332 | `0x1000` | 131072 | `IPQ5332/hw1.0/caldata.bin` |
| QCN6432 | `0x58800` | 184320 | `QCN6432/hw1.0/cal-ahb-soc@0:wifi2@c0000000.bin` |

These offsets matched the complete calibration files exactly on the validated
NWA50BE. Stop if extraction checks fail; do not substitute another device's
calibration.

## Prepare and build

The destination normally must not exist. After TIP's exact 125-patch setup has
completed, preparation may resume that exact pinned upstream state if project
patching has not started. The script refuses every other existing tree and
never resets or cleans a checkout.

Preparation records a private state fingerprint covering all nested Git
worktrees, untracked source additions, the generated `.config`, and the full
overlay including calibration. The build refuses any later input change. This
fingerprint is an accidental-change guard, not a signed source attestation.

```sh
./scripts/prepare-tree.sh ./work/wlan-ap /secure/path/nwa50be-art.bin
JOBS="$(nproc)" ./scripts/build.sh ./work/wlan-ap
```

Outputs are copied to a new UTC-stamped directory under `artifacts/` and
checksummed. The directory is ignored by Git and the script refuses to
overwrite it. The build rejects swallowed nested make errors and then validates
FIT metadata, both the RAM-boot and persistent DTBs, the exact flash boundary,
UBI geometry, calibration, LuCI, and rootfs policy.

## Package management

This downstream target has no compatible binary package repository. The build
therefore removes LuCI package management and ships no active remote APK feeds.
Do not point the device at generic OpenWrt repositories: kernel modules and
other ABI-sensitive packages will not match the Qualcomm/TIP build.

The unused `odhcpd` and `odhcpd-ipv6only` server packages are excluded. The
separate `odhcp6c` client remains available for obtaining upstream IPv6
configuration.

## Build identity

The config disables kernel debug information and sets neutral build metadata.
Before sharing any artifact privately, inspect it for usernames, hostnames,
paths, keys, calibration provenance, and credentials. A successful build is not
permission to publish it.
