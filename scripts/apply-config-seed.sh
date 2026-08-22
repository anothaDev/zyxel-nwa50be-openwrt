#!/bin/sh

set -eu

usage() {
	echo "usage: $0 <openwrt-directory> <config-seed>" >&2
	exit 2
}

[ "$#" -eq 2 ] || usage

openwrt="$1"
seed="$2"
config="$openwrt/.config"

[ -d "$openwrt" ]
[ -f "$config" ]
[ -f "$seed" ]

while IFS= read -r line; do
	case "$line" in
		CONFIG_*=*) symbol=${line%%=*} ;;
		'# CONFIG_'*' is not set') symbol=$(printf '%s' "$line" | cut -d' ' -f2) ;;
		''|'#'*) continue ;;
		*)
			echo "Unsupported config seed line: $line" >&2
			exit 1
			;;
	esac

	sed -i -e "/^${symbol}=/d" -e "/^# ${symbol} is not set$/d" "$config"
	printf '%s\n' "$line" >>"$config"
done <"$seed"

make -C "$openwrt" defconfig
