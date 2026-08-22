# Contributing

Open an issue before changing flash geometry, boot flow, calibration handling,
or regulatory behavior. Those changes require hardware evidence and a recovery
plan, not only a successful compile.

## Before submitting

1. Base the change on the pinned source revisions or explain the pin update.
2. Run `./scripts/audit-public-tree.sh`.
3. Prepare a fresh tree and run `./scripts/verify-prepared-tree.sh`.
4. For build changes, verify all four local images with
   `./scripts/verify-artifacts.sh`.
5. Describe what was directly observed, what was inferred, and what remains
   untested.

## Never submit

- ART, SPI NOR, NAND, or stock-configuration dumps
- extracted calibration or a firmware image containing it
- unlock tokens, passwords, keys, device serials, or MAC addresses
- unredacted serial captures or private network details
- commands that write bootloader, environment, ART, training, or license areas

Generated binaries are device-specific and are not accepted as issue or pull
request attachments.
