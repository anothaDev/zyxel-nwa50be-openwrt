# Backup and recovery

## Private backups

Before unlock or install, keep offline copies of:

- stock configuration export
- complete 16 MiB SPI NOR
- 1 MiB ART region
- build-time source pins and artifact checksums

These files can contain credentials, device identity, calibration, and boot
state. Never upload them.

## Read-only U-Boot backup

The validated unlocked U-Boot provided `sf read` and `tftpput`. With a TFTP
server configured in temporary environment variables, the read-only sequence
was:

```text
sf probe
sf read 0x60000000 0x300000 0x100000
crc32 0x60000000 0x100000
tftpput 0x60000000 0x100000 <PRIVATE_ART_FILENAME>
sf read 0x60000000 0x0 0x1000000
crc32 0x60000000 0x1000000
tftpput 0x60000000 0x1000000 <PRIVATE_SPI_FILENAME>
```

Confirm file sizes, U-Boot CRC32 values, and host SHA-256 values immediately.
This reads flash into RAM and uploads it; it does not write flash. Do not infer
or publish a restore command from this backup procedure.

## Recovery boundary

Zyxel documents that normal restoration to stock firmware may be unavailable
after custom firmware conversion because of its signing and security
architecture. Keep UART accessible until multiple normal boots have passed.

The custom DTS leaves bootloader, environment, and ART inaccessible from Linux.
Only NAND `rootfs` is writable; `rootfs_1`, training, and license partitions are
read-only. A damaged NAND rootfs should be recovered by TFTP RAM boot and a
reviewed sysupgrade, not by guessing SPI write commands.
