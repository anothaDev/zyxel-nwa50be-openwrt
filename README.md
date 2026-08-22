# Zyxel NWA50BE OpenWrt research build

Experimental, pinned build support for running a persistent TIP/OpenWiFi-based
OpenWrt image on the Zyxel NWA50BE, including the QCN6432 wide-band radio in
6 GHz mode.

This is a private-review prototype. It is not upstream OpenWrt, not an official
Zyxel image, and not ready for unattended installation.

## What was verified

One NWA50BE was unlocked through Zyxel's official waiver flow, RAM-booted,
backed up, installed to NAND, cold-booted, and exercised in a routed deployment.

- OpenWrt 25.12.3 with TIP/OpenWiFi `v5.1.0-rc1`
- Persistent squashfs plus UBIFS overlay on the 60 MiB NAND `rootfs` partition
- SPI NOR, bootloader, environment, and ART inaccessible from Linux
- 2.5 GbE full duplex with no interface errors, drops, or collisions
- QCN6432 in 6 GHz LPI mode, channel 5, EHT160
- More than 2 Gbit/s negotiated client PHY rates and more than 1 Gbit/s
  measured throughput in close-range testing
- Standard LuCI with HTTPS
- Optional cross-BSS bridge-port isolation while preserving same-BSS printer
  access
- Repeated cold boots with stable Ethernet and BSS MAC addresses

See [docs/VALIDATION.md](docs/VALIDATION.md) for the acceptance evidence and
its limits.

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

The working image requires per-device ART calibration. The validated private
build also contained a device-specific admin key and build-host metadata. Those
must never be published.

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
- The installer image exposes only the NAND rootfs area required by sysupgrade.
- SPI NOR remains disabled from Linux.
- Radios boot disabled.
- HTTPS LuCI and SSH stay disabled until serial setup establishes credentials.
- Country code and regulatory limits are never bypassed.

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

The source and documentation are being reviewed in a private repository first.
Public visibility and binary releases are separate decisions. The repository
must pass `./scripts/audit-public-tree.sh` before either decision.
