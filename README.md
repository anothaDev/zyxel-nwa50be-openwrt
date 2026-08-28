# Zyxel NWA50BE OpenWrt research build

Experimental, pinned build support for running a persistent TIP/OpenWiFi-based
OpenWrt image on the Zyxel NWA50BE, including the QCN6432 wide-band radio in
6 GHz mode.

This is an experimental source-only project. It is not upstream OpenWrt, not an
official Zyxel image, and not ready for unattended installation.

> [!CAUTION]
> **This is not an easy or risk-free firmware flash.** The official unlock can
> erase the stock installation and may prevent normal restoration. This build
> requires calibration from the exact target device, has no writable A/B
> rollback slot, and can require 3.3 V UART plus TFTP recovery after a mistake or
> failed boot. Do not proceed without verified backups, serial access, recovery
> experience, and acceptance that the AP can become unusable. No warranty or
> recovery guarantee is provided.

## What was verified

One NWA50BE was unlocked through Zyxel's official waiver flow, RAM-booted,
backed up, installed to NAND, cold-booted, and exercised in a routed deployment.
The publication-hardening candidate was subsequently installed and recovered
from a verified configuration backup after the OpenWrt snapshot's explicit
`sysupgrade -f` requirement was identified. A normal reboot then preserved the
recovered state and passed the routed acceptance checks.

- OpenWrt 25.12.3 with TIP/OpenWiFi `v5.1.0-rc1`
- Persistent squashfs plus UBIFS overlay on the 60 MiB NAND `rootfs` partition
- SPI NOR, bootloader, environment, and ART inaccessible from Linux
- 2.5 GbE full duplex with zero driver-reported hardware error, drop, CRC, and
  FIFO-overflow counters at the five-day checkpoint
- QCN6432 in 6 GHz LPI mode, channel 5, EHT160
- More than 2 Gbit/s negotiated client PHY rates and more than 1 Gbit/s
  measured throughput in close-range testing
- Standard LuCI with HTTPS
- Optional cross-BSS bridge-port isolation while preserving same-BSS printer
  access
- Repeated cold boots with stable Ethernet and BSS MAC addresses
- More than five days of continuous post-recovery operation without an observed
  radio crash, watchdog, DFS event, or Ethernet link-down event

See [docs/VALIDATION.md](docs/VALIDATION.md) for the acceptance evidence and
its limits. The security review and remediation boundary are documented in
[docs/SECURITY.md](docs/SECURITY.md).

## The software limitation

The tested stock firmware exposed 2.4 GHz and 5 GHz service and reported the
wide-band slot as AX-class operation. In the public TIP/OpenWiFi NWA50BE device
tree used as the build base, the QCN6432 is configured with:

```dts
qcom,wide_band = <1>;
```

Changing that policy to `<2>` causes the same QCN6432 to initialize in 6 GHz
mode, where the Qualcomm driver identifies Wi-Fi 7 hardware and supports
EHT160. That establishes a software-enforced product limitation on the tested
hardware. It does not establish why Zyxel chose it; certification, regulatory,
SKU, support, and product-positioning constraints are all possible.

The project documents the evidence and avoids claims about intent. See
[docs/HARDWARE-FINDINGS.md](docs/HARDWARE-FINDINGS.md).

## Why there is no downloadable firmware image

The working image requires per-device ART calibration. Earlier exploratory
builds also contained device-specific administrator material and build-host
metadata. Those must never be published.

This repository therefore builds a local image only after the owner supplies a
private 1 MiB ART backup. The ART file and extracted calibration remain ignored
by Git. Qualcomm runtime firmware is consumed from the pinned public TIP tree;
its package lacks explicit package-level license metadata. The selected
`qca-ssdk-shell` package has the same problem. Release binaries therefore
remain blocked pending a complete license inventory and clearer redistribution
evidence.

## Safety model

- Zyxel's official unlock can void warranty and erase the stock NAND image.
- A normal return to stock firmware is not guaranteed.
- UART and a verified TFTP RAM boot are mandatory.
- Only NAND `rootfs` is writable; training, license, and `rootfs_1` remain
  read-only.
- SPI NOR remains disabled from Linux.
- Radios boot disabled.
- HTTPS LuCI and SSH stay disabled until serial setup establishes credentials
  and one wired administrator `/32`. Provisioned upgrades use the
  `nwa50be-sysupgrade` wrapper to create, verify, and explicitly pass the backup;
  HTTPS/SSH remain restricted to the recorded host.
- Cleartext HTTP stays disabled, HTTP keep-alive is off, and wireless bridge
  ports cannot reach the AP management plane.
- Country code and regulatory limits are never bypassed.
- Remote package feeds and LuCI package management are disabled because no
  compatible binary package repository exists for this downstream target.

Read [docs/INSTALL.md](docs/INSTALL.md) completely before touching hardware.

## Build overview

```sh
./scripts/prepare-tree.sh ./work/wlan-ap /secure/path/nwa50be-art.bin
JOBS="$(nproc)" ./scripts/build.sh ./work/wlan-ap
```

The build is pinned and refuses dirty or unexpected source state. Generated
images stay under the ignored `artifacts/` directory. Full details are in
[docs/BUILD.md](docs/BUILD.md).

## Upstream bases

- [TIP OpenWiFi AP NOS](https://github.com/Telecominfraproject/wlan-ap)
- [OpenWrt](https://openwrt.org/)
- [Zyxel official OpenWrt support announcement](https://community.zyxel.com/en/discussion/32423/zyxel-networks-access-points-now-support-openwrt-based-customized-software)

## Project status

Public source visibility and binary releases are separate decisions. No binary
release is currently permitted. The repository must pass
`./scripts/audit-public-tree.sh` before any publication decision.
