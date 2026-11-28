#!/bin/sh

# Run on the AP after flashing: the gate must be loaded and wired management
# traffic must be counted through it without drops.
set -eu

nft list table netdev nwa50be_mark | grep -Eq 'hook ingress device "?eth0"?'
nft list table inet nwa50be_gate | grep -Fq 'meta mark & 0x40000000 == 0x00000000'
if nft list tables | grep -Fq 'bridge nwa50be_management'; then
	echo 'Refusing: the dead bridge-family guard is still loaded.' >&2
	exit 1
fi
echo 'Management gate is loaded.'
