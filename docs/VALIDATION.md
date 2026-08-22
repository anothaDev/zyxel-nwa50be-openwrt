# Validation evidence

The following results were collected on one NWA50BE. They demonstrate that the
build worked on that unit; they are not a reliability guarantee for every board
revision or RF environment.

The live results below predate the publication-hardening changes. The current
candidate was rebuilt from its pinned prepared state and passed the automated
checks described next, but it has not yet been flashed for a new live acceptance
run.

## Candidate artifact checks

`scripts/build.sh` completed a full local build and
`scripts/verify-artifacts.sh` accepted all four NWA50BE images. The verifier:

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
- requires the packaged SSDK init script to match the NWA50BE profile; and
- verifies the pinned uHTTPd and OpenSSL package versions in the image manifest.

The prepared-source fingerprint also passed after the build, proving the build
did not alter its tracked, untracked, configuration, or overlay inputs. These
checks establish artifact structure and policy, not hardware behavior.

## Boot and storage

- Normal U-Boot loaded the kernel and DTB from NAND UBI and verified FIT hashes.
- Squashfs root and UBIFS overlay mounted read-write.
- The exact NAND layout was 512 KiB training, 256 KiB license, 60 MiB rootfs,
  and 60 MiB read-only rootfs_1.
- SPI NOR was absent from Linux MTD enumeration.
- Multiple normal cold boots preserved configuration and stable MAC addresses.

## Networking

- AP uplink negotiated 2500Base-T full duplex.
- Interface counters showed zero errors, drops, collisions, and output errors.
- A 60-packet routed management sample completed with 0% loss and sub-millisecond
  latency.
- AP-originated public-IP and DNS tests completed successfully.
- HTTPS LuCI returned the authenticated login boundary after reboot.

## Wireless

- 2.4 GHz normal and compatibility BSSes operated on channel 6 at 20 MHz.
- QCN6432 operated at 5975 MHz, channel 5, EHT160, WPA3-SAE, and LPI power mode.
- Close-range client PHY rates exceeded 2 Gbit/s.
- Measured internet download exceeded 1 Gbit/s in close-range testing.
- Multiple clients and a legacy printer re-associated after cold boot.
- Cross-BSS isolation blocked normal-to-compatibility traffic while the printer
  remained reachable from a client on the same compatibility BSS.

## Known limits

- MLO was deliberately disabled because early tests exposed peer-allocation
  failures in the downstream stack.
- 6 GHz range is materially shorter than 5 GHz at the same placement.
- The QPIC bootloader sometimes falls back from serial-NAND training to a 50 MHz
  feedback-clock mode; the training partition is preserved read-only.
- The image is based on a downstream Qualcomm/TIP stack, not upstream OpenWrt.
