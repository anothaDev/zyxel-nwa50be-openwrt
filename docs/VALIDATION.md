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

## Latest unflashed artifact checks

On 2026-09-17, `scripts/build.sh` completed a local incremental build and
`scripts/verify-artifacts.sh` accepted all four NWA50BE images. This artifact
set remains private and has not been installed on the validation AP. The
verifier:

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
