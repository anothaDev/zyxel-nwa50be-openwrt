#!/bin/sh

# Generate the per-flash sysupgrade guard for one exact image and one exact
# configuration backup. The guard fails closed on any other bytes.
set -eu

usage() {
	echo "usage: $0 <sysupgrade.tar> <backup.tar.gz> <new-output-directory>" >&2
	exit 2
}
[ "$#" -eq 3 ] || usage

project=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.."
	pwd
)
image=$1
backup=$2
out=$3

[ -s "$image" ] && [ -s "$backup" ]
[ ! -e "$out" ]
gzip -t "$backup"
tar -tf "$image" | grep -Fxq 'sysupgrade-zyxel_nwa50be/kernel'
tar -tf "$image" | grep -Fxq 'sysupgrade-zyxel_nwa50be/root'

hex_only() {
	digest=$(cut -d' ' -f1)
	case "$digest" in
		*[!0-9a-f]*|'') echo 'Refusing: invalid digest.' >&2; exit 1 ;;
	esac
	[ "${#digest}" -eq 64 ] || { echo 'Refusing: invalid digest length.' >&2; exit 1; }
	printf '%s\n' "$digest"
}
sha() { sha256sum <"$1" | hex_only; }
member_sha() { tar -xOf "$image" "sysupgrade-zyxel_nwa50be/$1" | sha256sum | hex_only; }
member_len() { tar -xOf "$image" "sysupgrade-zyxel_nwa50be/$1" | wc -c; }

suffix=$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')
stage=/tmp/nwa50be-flash.$suffix

mkdir -p "$out/guard"
chmod 0700 "$out" "$out/guard"
for file in nand.sh do_stage2; do
	sed \
		-e "s|@BACKUP_SHA@|$(sha "$backup")|g" \
		-e "s|@IMAGE_SHA@|$(sha "$image")|g" \
		-e "s|@KERNEL_SHA@|$(member_sha kernel)|g" \
		-e "s|@ROOT_SHA@|$(member_sha root)|g" \
		-e "s|@KERNEL_LEN@|$(member_len kernel)|g" \
		-e "s|@ROOT_LEN@|$(member_len root)|g" \
		-e "s|@STAGE@|$stage|g" \
		"$project/scripts/flash-guard/$file" >"$out/guard/$file"
done
chmod 0700 "$out/guard/do_stage2"
if grep -q '@[A-Z_]*@' "$out/guard/nand.sh" "$out/guard/do_stage2"; then
	echo 'Refusing: unfilled placeholder in generated guard.' >&2
	exit 1
fi
printf '%s\n' "$stage" >"$out/stage-dir"
printf 'image=%s\nbackup=%s\nstage=%s\n' "$(sha "$image")" "$(sha "$backup")" "$stage" >"$out/pins"
echo "Guard written to $out (stage $stage)"
