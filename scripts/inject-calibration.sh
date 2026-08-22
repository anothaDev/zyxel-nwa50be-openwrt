#!/bin/sh

set -eu

usage() {
	echo "usage: $0 <private-art.bin> <overlay-directory>" >&2
	exit 2
}

[ "$#" -eq 2 ] || usage

art="$1"
overlay="$2"

[ -f "$art" ] || {
	echo "ART input does not exist: $art" >&2
	exit 1
}

art_size=$(wc -c <"$art")
[ "$art_size" -eq 1048576 ] || {
	echo "Refusing: expected a 1048576-byte ART dump, got $art_size bytes." >&2
	exit 1
}

ipq="$overlay/lib/firmware/ath12k/IPQ5332/hw1.0/caldata.bin"
qcn="$overlay/lib/firmware/ath12k/QCN6432/hw1.0/cal-ahb-soc@0:wifi2@c0000000.bin"

mkdir -p "$(dirname "$ipq")" "$(dirname "$qcn")"

dd if="$art" of="$ipq" bs=1 skip=4096 count=131072 status=none
dd if="$art" of="$qcn" bs=1 skip=362496 count=184320 status=none

has_calibration_data() {
	od -An -v -tu1 "$1" | awk '
		{
			for (i = 1; i <= NF; i++)
				if ($i != 0 && $i != 255)
					found = 1
		}
		END { exit found ? 0 : 1 }
	'
}

[ "$(wc -c <"$ipq")" -eq 131072 ]
[ "$(wc -c <"$qcn")" -eq 184320 ]
has_calibration_data "$ipq"
has_calibration_data "$qcn"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
dd if="$art" of="$tmp/ipq" bs=1 skip=4096 count=131072 status=none
dd if="$art" of="$tmp/qcn" bs=1 skip=362496 count=184320 status=none
cmp -s "$tmp/ipq" "$ipq"
cmp -s "$tmp/qcn" "$qcn"

chmod 0644 "$ipq" "$qcn"

echo 'Injected private per-device calibration into the local build overlay.'
echo 'Do not commit the ART file, extracted calibration, or resulting images.'
