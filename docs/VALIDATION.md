# Validation evidence

The following results were collected on one NWA50BE. They demonstrate that the
build worked on that unit; they are not a reliability guarantee for every board
revision or RF environment.

The publication-hardening candidate was installed on the tested AP. A plain
`sysupgrade <image>` booted the new image but did not preserve configuration,
because this OpenWrt snapshot requires the backup to be supplied explicitly
with `-f`. The verified pre-upgrade backup was restored over UART, followed by
a normal reboot and a new live acceptance run. The source now provides a
fail-closed `nwa50be-sysupgrade` wrapper; that wrapper itself has automated
coverage but has not been used for another live flash.

## Installed image: 2026-11-27

The `v5.1.1` image built on 2026-11-27, with patches up to 0063, was
installed on the validation AP the same day through the flash guard: a fresh
`sysupgrade -b` backup, a guard generated for exactly that image and backup
(14 of 14 offline guard cases passed), an on-device comparison of the nine
required files with the backup, `sysupgrade -T`, then the guarded upgrade.
The AP answered on SSH again 72 seconds after the session closed.

After the flash:

- The kernel and root filesystem volumes hash to the image's kernel and root
  members. Kernel 6.6.88 runs with 146 modules loaded and no oops or warning
  in the kernel log.
- Host name, LAN address, the recorded management address, every interface
  MAC address, the SSH host keys and the eight checked configuration and
  state files are as in the backup. The same three first-boot scripts remain
  as on the previous image.
- `scripts/check-live-management-gate.sh` passes. dropbear listens on the
  LAN address only, with password login off, and uhttpd runs with
  `-n 3 -W 3`.
- All three BSSs are up in EHT modes, and the eight clients present before
  the flash were associated again within a minute of boot.
- LuCI answers its login page over HTTPS from the wired administrator host,
  alone and for eight parallel requests; port 80 is closed.
- `hostapd -v11be` exits 0, and LuCI's feature list reports 11be.

Vantage 1.2.1 was installed afterwards from its signed feed, outside the
build chain. The wireless-side capture of the management gate described
below ran on the previous image, which has the same gate include; it has not
been repeated on this one.

## Live management gate check: 2026-11-27

On the installed unit (the `v5.1.1-rc1` image, installed 2026-10-31),
`scripts/check-live-management-gate.sh` passed, and an on-device capture of
packet headers watched a phone request the HTTPS management address:

- From the SSID bridged onto the management segment: the address lookup was
  answered, 17 SYNs over two connection attempts arrived on the radio port
  and on `br-lan`, and the AP sent no TCP reply.
- From an SSID on another VLAN: the upstream router forwarded the request,
  it arrived on `eth0`, and the fw4 address allowlist refused it with a TCP
  reset.

The first result is the gate. The second is outside it; see the scope note
in [SECURITY.md](SECURITY.md#installed-unit-state-october-2026). No
forged-source traffic was sent: the gate rule does not match on the source
address.

## Artifact checks

On 2026-11-27, patches 0061 to 0063 and the uhttpd per-source setting were
added. The kernel build directory was removed and the kernel, every kernel
module and the images were rebuilt in the same tree. `scripts/build.sh` and
`scripts/verify-artifacts.sh` passed for all four NWA50BE images (230 PEBs,
30,146,560-byte UBI). The first build attempt stopped in `qca-nss-ppe-ds`,
which compiled before `qca-nss-ppe-vp` had staged a header it includes; the
second run completed. Checked on the result:

- The kernel packed in the sysupgrade image is the `Image` built in the
  tree, and its device tree is byte-identical to the installed image's.
- Against the build of the day before, the root filesystem differs in
  `/usr/sbin/wpad`, `luci-mod-network.json`, the first-boot script, the
  package database, and the build time stamped into `qca-ssdk.ko` and
  `ssdk_sh`. All other kernel modules are byte-identical, and every module
  resolves the symbols it needs against the new kernel or another module.
- Run under user-mode emulation, `hostapd -v11be` exits 0 where the earlier
  binary exited 1; the artifact verifier now asks the packaged binary.

Rehearsed on the validation AP in RAM, without installing: the image's files
were unpacked into the RAM disk, a fresh `sysupgrade -b` backup restored
over them, and the first-boot scripts run there as an unprivileged account.
The management state was recognised, the enabled services came out identical
to the running system's (44 links), and network, wireless, firewall and
dropbear configuration were unchanged; uhttpd gained only
`max_requests_per_source`. `fw4 print` with the new tools rendered the same
145 lines as the running system. On a private bus the new rpcd allowed the
bridge port and `/bin/ping6` reads that 0063 grants and refused unrelated
files, uhttpd answered 24 parallel LuCI requests, and the new dropbear
accepted the key login with the existing host keys. Afterwards the unit's
ruleset, the hash of its `/etc`, its mounts and its service PIDs were as
before.

Tested in QEMU's generic arm64 machine, not on NWA50BE hardware: the kernel
with 0062 completed 296,870 TCP connections against listeners that stayed up
with no failure. The same multi-segment test on the kernel without 0062
produced 32 resets during establishment in 107,800 connections, when
consecutive segments of one connection were delivered to two CPUs over a
bonded link. UDP, VLAN (including VLAN 0 tags), nftables with the gate file,
listener migration and CPU-timer load ran without a kernel warning, the
image's kernel modules loaded, and the image's own init reached "init
complete" and stayed up. The hardware offload path, the Wi-Fi and switch
drivers, and the bootloader hand-over are not covered by any of this.

This artifact was installed on the validation AP the same day; see
"Installed image: 2026-11-27" above.

On 2026-11-26, the `v5.1.1` update with patches 0050 to 0060 received a
fresh preparation of the pinned tree and a full tools, toolchain, kernel and
package build. `scripts/build.sh` and `scripts/verify-artifacts.sh` passed
for all four NWA50BE images (230 PEBs, 30,146,560-byte UBI). The new kernel
patches were also applied in `patch-kernel.sh` order to a 6.6.88 source with
TIP's 934 patches, at fuzz 0. The image labels read `v5.1.1`, commit
`f18e1f56`, and schema `e293493`. This artifact has not been installed on the
validation AP.

On 2026-10-28, the `v5.1.1-rc1` update received a fresh
source/toolchain/kernel/package build from a new preparation of the pinned
tree. The image set, built from the 22 existing patches, passed
`scripts/build.sh` and `scripts/verify-artifacts.sh` for all four NWA50BE images (230 PEBs, 30,146,560-byte UBI, the same
geometry as the September build), the prepared-source fingerprint passed
again after the build, the image labels read `v5.1.1-rc1`, commit
`20561633`, schema `e293493`, and uCentral 5.1.1. The built
kernel enables pstore RAM logging (see [BUILD.md](BUILD.md)). The artifact
remains private and has not been installed on the validation AP.

On 2026-09-17, the `v5.1.0` update received a fresh source/toolchain/kernel/package
build, followed by a metadata-correction rebuild. The first image set was
rejected because upstream's version generator joined the rc2 and final tags.
Patch `0022` corrects that ambiguity; the accepted replacement passed
`scripts/build.sh` and `scripts/verify-artifacts.sh` for all four NWA50BE images
(230 PEBs, 30,146,560-byte UBI). A second fresh preparation with all 22 patches
matched the build tree's input fingerprint exactly. The final artifact remains
private and has not been installed on the validation AP. The verifier:

- checks every staged file against `SHA256SUMS`;
- extracts and structurally validates the DTB from both initramfs and the
  sysupgrade kernel, then requires those DTBs to be byte-identical;
- requires SPI disabled, NAND enabled, wide-band mode 2, the exact four NAND
  partitions, and read-only flags on every partition except `rootfs`;
- extracts the persistent squashfs and checks calibration against the private
  build overlay without recording calibration hashes in this repository;
- requires an empty pre-setup root password, disabled SSH, HTTPS-only setup,
  wired-source management policy, wireless management blocking, no active
  package feeds, and no LuCI package manager;
- requires the NWA50BE upgrade wrapper to create, inspect, test, and explicitly
  pass a configuration backup with `sysupgrade -f`;
- byte-compares both cloud-provisioning overrides and the wired-ingress guard
  against the reviewed overlay;
- requires the exact TIP label (`v5.1.1` for the current pin), commit
  prefix, schema revision, and uCentral version metadata, plus byte-exact
  packaged hostapd shell support;
- executes the six-case lock/BH regression against the actual generated ath12k
  collision block; prepared-tree verification also runs five real-Git
  version-label cases;
- requires the packaged SSDK init script to match the NWA50BE profile; and
- requires uHTTPd `2026.08.03~60f64bec-r1`, OpenSSL `3.5.8-r1`, cgi-io
  `2026.07.21~31cb3c89-r1`, and uMDNS `2026.06.16~1b5e7bf1-r1` in the image
  manifest;
- requires the already-fixed procd `2026.03.13~58eb263d-r1` and jsonfilter
  `2026.03.16~b9034210-r1` revisions;
- rejects the stale LuCI mount ACL write grant to root's crontab;
- requires the LuCI Wi-Fi scan and DHCP lease field escaping fixes; and
- rejects reviewed advisory-affected packages that are not part of the image's
  intended package set, including both odhcpd server variants.

The prepared-source fingerprint also passed after the build, proving the build
did not alter its tracked, untracked, configuration, or overlay inputs. These
checks establish artifact structure and policy, not hardware behavior. Live
validation below applies to the previously installed candidate, not this newer
unflashed build.

### Accepted 5.1.0 image startup and packet tests

Three isolated replays used the accepted image's exact defaults and ARM
configuration tools without source-overlay substitutions. Provisioned key-only
SSH and HTTPS retained the saved static LAN, wired `/32`, password, key, and
wireless settings. A keyless saved configuration retained HTTPS but disabled
SSH. An unprovisioned fixture produced DHCP LAN with no management allowlist,
no credentials or setup marker, disabled management/cloud services and radios,
and no BSS entries. All three dispatchers returned zero; the image checksum
was unchanged before and after testing.

The replay substituted host BusyBox and service-control logging stubs, used
synthetic board/configuration fixtures, and skipped hardware-only U-Boot
environment discovery. It does not prove NAND restoration, real service
startup, credential usability, or hardware boot.

The exact packaged bridge guard passed the same 17 isolated TCP packet cases
described below, using host nftables 1.1.7 and Linux 7.2.3. The target nftables
binary could not initialize its netlink connection under user-mode emulation;
target-userland/kernel packet enforcement remains a hardware acceptance item.

## September 17 startup and management regressions

The August 28 image had a second configuration-loss path: inherited cloud
defaults erased the restored LAN before the community policy ran. An isolated
replay used that exact image's full rootfs, actual `uci_apply_defaults`
dispatcher, and ARM UCI, jshn, and jsonfilter binaries under QEMU. The original
defaults lost the static LAN and bridge despite returning success. Replacing
only `99-ucentral-network` and `zzz-ucentral` with the new overrides preserved
the LAN, wired `/32`, key-only SSH, HTTPS-only policy, and byte-identical
wireless, password, and authorized-key fixtures.

The replay used synthetic configuration, host static BusyBox, and stubbed
service actions in isolated filesystem/PID/network namespaces. It skipped the
hardware-only U-Boot environment-discovery default. It did not test NAND
restoration, actual service startup, or hardware boot.

A separate isolated network-namespace test exercised the exact new bridge
guard with a minimal counterpart of the fw4 IPv4 management policy. All 17 TCP
cases passed: authorized wired 22/443 allowed; unauthorized wired sources and
port 80 blocked; spoofed authorized sources arriving on `phy2g-ap0`,
`phy6g-ap0`, `wlan0`, `ap-mld0`, and `eth0.10` blocked; repeated guard reloads
retained authorized access. The old guard failed the same test on `wlan0`.
Static neighbor entries ensured this tested IP filtering rather than only ARP
blocking. The harness used host Linux 7.2.3 and nftables 1.1.7, synthetic TCP
listeners, and no live AP interfaces; target hardware and nftables 1.1.6 remain
distinct acceptance boundaries.

Repository security regressions, public-tree audit, prepared-tree verification,
and rebuilt-artifact verification passed. No firmware was flashed or AP
configuration changed during this checkpoint.

## Final-image hardware acceptance gate

These checks remain maintainer-owned and must be performed on the exact
post-merge candidate, not inferred from an older image or CI success:

- [ ] Record the source commit, image checksum, and successful artifact checks.
- [ ] Keep a fresh off-device configuration backup and verify UART/TFTP recovery.
- [ ] Confirm the backup contains networking, wireless, credentials, setup marker,
      administrator `/32`, and SSH authorized keys; use the explicit-backup wrapper.
- [ ] Confirm normal boot and writable UBIFS with the protected flash boundary intact.
- [ ] Verify SSH and HTTPS from the authorized wired host, refusal from other wired
      sources and Wi-Fi, and no cleartext HTTP listener.
- [ ] Verify all configured BSSes, client association, DHCP, DNS, and internet traffic.
- [ ] Exercise same-radio cross-BSS reassociation and inspect for driver errors.
- [ ] Reboot again and confirm networking, management access, and credentials persist.
- [ ] Complete a stability soak; no claim of long-term reliability follows from one boot.

## Boot and storage

- Normal U-Boot loaded the kernel and DTB from NAND UBI and verified FIT hashes.
- Squashfs root and UBIFS overlay mounted read-write.
- The exact NAND layout was 512 KiB training, 256 KiB license, 60 MiB rootfs,
  and 60 MiB read-only rootfs_1.
- SPI NOR was absent from Linux MTD enumeration.
- Multiple normal cold boots preserved configuration and stable MAC addresses.

## Networking

- AP uplink negotiated 2500Base-T full duplex.
- At initial acceptance, interface counters showed zero errors, drops,
  collisions, and output errors.
- A 60-packet routed management sample completed with 0% loss and sub-millisecond
  latency.
- AP-originated public-IP and DNS tests completed successfully.
- HTTPS LuCI returned the authenticated login boundary after reboot.
- A new 60-packet routed management sample completed with 0% loss and 0.266 ms
  average latency after the hardened-image recovery reboot.
- HTTPS returned HTTP 200, cleartext port 80 refused connections, SSH key login
  succeeded, and outbound HTTPS plus DNS succeeded.

## Wireless

- 2.4 GHz normal and compatibility BSSes operated on channel 6 at 20 MHz.
- QCN6432 operated at 5975 MHz, channel 5, EHT160, WPA3-SAE, and LPI power mode.
- Close-range client PHY rates exceeded 2 Gbit/s.
- Measured internet download exceeded 1 Gbit/s in close-range testing.
- Multiple clients and a legacy printer re-associated after cold boot.
- Seven clients re-associated after the hardened-image recovery reboot: one on
  normal 2.4 GHz, two on compatibility, and four on the 160 MHz high-band BSS.
- Cross-BSS isolation blocked normal-to-compatibility traffic while the printer
  remained reachable from a client on the same compatibility BSS.

## Five-day soak checkpoint

A read-only checkpoint on 2026-08-28 found:

- 5 days and 2 hours of continuous uptime after the recovery reboot;
- 20 of 20 routed management probes returned, with 0% loss and 0.361 ms average
  latency;
- all three BSSes remained active with multiple associated clients;
- the high-band BSS remained on channel 5 at 160 MHz, while both 2.4 GHz BSSes
  remained on channel 6 at 20 MHz;
- retained logs contained no firmware crash, fatal assertion, watchdog,
  DFS/radar, or Ethernet link-down event; and
- Ethernet hardware counters reported zero receive/transmit errors, CRC errors,
  FIFO overflow, and hardware drops.

Linux's aggregate `rx_dropped` counter was 15,231. It did not increase during a
10-second sample, while the driver-reported hardware drop counters remained
zero. The source and timing of the accumulated Linux counter were not
established, so it is recorded rather than treated as proof of an active link
fault or ignored as harmless.

This is a point-in-time soak result, not a long-term reliability guarantee.

## Known limits

- MLO was deliberately disabled because early tests exposed peer-allocation
  failures in the downstream stack.
- 6 GHz range is materially shorter than 5 GHz at the same placement.
- The QPIC bootloader sometimes falls back from serial-NAND training to a 50 MHz
  feedback-clock mode; the training partition is preserved read-only.
- The image is based on a downstream Qualcomm/TIP stack, not upstream OpenWrt.
