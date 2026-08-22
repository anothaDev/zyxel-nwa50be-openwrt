#!/bin/sh

set -eu

[ "$#" -eq 1 ] || {
	echo "usage: $0 <initramfs-fit>" >&2
	exit 2
}

image="$1"
[ -f "$image" ]

size=$(wc -c <"$image")
size_hex=$(printf '%x' "$size")
sha256=$(sha256sum "$image" | awk '{print $1}')
crc32=$(python3 -c 'import pathlib, sys, zlib; print(f"{zlib.crc32(pathlib.Path(sys.argv[1]).read_bytes()) & 0xffffffff:08x}")' "$image")

printf 'bytes=%s\n' "$size"
printf 'hex_size=0x%s\n' "$size_hex"
printf 'sha256=%s\n' "$sha256"
printf 'crc32=%s\n' "$crc32"
printf 'uboot_crc_command=crc32 0x60000000 0x%s\n' "$size_hex"
