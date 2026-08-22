# Build

## Inputs

The build is pinned to:

- TIP/OpenWiFi tag `v5.1.0-rc1`
- TIP commit `122d893d88a6762bffeac54c5f87b37407cefe7a`
- OpenWrt base commit `a5652f421c6f6e548fb801a93b2cd2ae13eca631`
- TIP-patched OpenWrt tree `a0fa511453f26becffbde594f46103ab9bad57a7`

The TIP tag is lightweight and unsigned. The OpenWrt `v25.12.3` tag was signed,
but this project consumes TIP's 124-patch OpenWrt result and records its Git
tree object separately. The generated commit ID is intentionally not pinned
because committer metadata changes it without changing source content.

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

`qca-ssdk-shell` has a broken generated-dependency bootstrap. The build runs it
at `-j1` for at most six passes before the parallel build. Each permitted failed
pass must generate dependencies and end on the exact missing-`.d` rule; any
compiler or linker error aborts immediately. A clean tree succeeded on pass 5.
This avoids redistributing a patch from a source repository that does not state
redistribution terms.

TIP's Kconfig currently prints recursive-dependency diagnostics for the
unselected `kmod-qca-nss-ecm-premium`, `kmod-qca-nss-ecm-wifi-plugin`,
`cig-device-boot`, and `kmod-usb-serial-xr` packages during `defconfig`. The
verifier requires all four to remain unselected; treat a selected symbol or a
nonzero `defconfig` exit as a failure.

## Host requirements

Use a recent Linux distribution with the normal OpenWrt build dependencies,
Git, Python 3 with PyYAML, rsync, GNU make, and enough disk space for a complete
ipq53xx build. The scripts use every available CPU by default; override with
`JOBS`.

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

The destination normally must not exist. After TIP's exact 124-patch setup has
completed, preparation may resume that exact pinned upstream state if project
patching has not started. The script refuses every other existing tree and
never resets or cleans a checkout.

```sh
./scripts/prepare-tree.sh ./work/wlan-ap /secure/path/nwa50be-art.bin
JOBS="$(nproc)" ./scripts/build.sh ./work/wlan-ap
```

Outputs are copied to a new UTC-stamped directory under `artifacts/` and
checksummed. The directory is ignored by Git and the script refuses to
overwrite it. The build rejects swallowed nested make errors and then validates
FIT metadata, the DTB flash boundary, UBI geometry, calibration, LuCI, and
rootfs policy.

## Build identity

The config disables kernel debug information and sets neutral build metadata.
Before sharing any artifact privately, inspect it for usernames, hostnames,
paths, keys, calibration provenance, and credentials. A successful build is not
permission to publish it.
