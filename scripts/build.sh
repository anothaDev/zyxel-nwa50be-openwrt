#!/bin/sh

set -eu

usage() {
	echo "usage: $0 <prepared-wlan-ap-directory>" >&2
	exit 2
}

[ "$#" -eq 1 ] || usage

project=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.."
	pwd
)
tree="$1"
openwrt="$tree/openwrt"
jobs=${JOBS:-$(nproc)}
stamp=$(date -u '+%Y%m%dT%H%M%SZ')
stage=${ARTIFACT_DIR:-"$project/artifacts/$stamp"}
log="$stage/build.log"

command -v flock >/dev/null 2>&1 || {
	echo 'Missing required command: flock' >&2
	exit 1
}
mkdir -p "$project/work"
exec 9>"$project/work/.nwa50be-build.lock"
if ! flock -n 9; then
	echo 'Refusing: another NWA50BE build is already using this repository.' >&2
	exit 1
fi

"$project/scripts/verify-prepared-tree.sh" "$tree"

[ ! -e "$stage" ] || {
	echo "Refusing to overwrite existing artifact directory: $stage" >&2
	exit 1
}
mkdir -p "$stage"

export KBUILD_BUILD_USER='nwa50be'
export KBUILD_BUILD_HOST='local'

make -C "$openwrt" -j"$jobs" tools/install V=s
make -C "$openwrt" -j"$jobs" toolchain/install V=s
make -C "$openwrt" -j"$jobs" target/compile V=s
"$project/scripts/bootstrap-qca-ssdk-shell.sh" "$openwrt" "$stage"
if ! make -C "$openwrt" -j"$jobs" V=s >"$log" 2>&1; then
	cat "$log"
	echo 'Refusing: OpenWrt build failed.' >&2
	exit 1
fi
cat "$log"

if grep -Eq 'Cannot open|make\[[0-9]+\]: \*\*\* .* Error [0-9]+' "$log"; then
	echo 'Refusing: build log contains a swallowed inner build failure.' >&2
	exit 1
fi

found=0
for image in "$openwrt"/bin/targets/ipq53xx/generic/*nwa50be*; do
	[ -f "$image" ] || continue
	case "$image" in
		*initramfs-kernel.bin|*sysupgrade.tar|*nand-factory.bin|*nand-factory.ubi)
			cp -p "$image" "$stage/"
			found=$((found + 1))
			;;
	esac
done

[ "$found" -eq 4 ] || {
	echo "Refusing: expected four NWA50BE images, found $found." >&2
	exit 1
}

for metadata in config.buildinfo feeds.buildinfo profiles.json version.buildinfo \
	openwrt-ipq53xx-zyxel_nwa50be.manifest; do
	file="$openwrt/bin/targets/ipq53xx/generic/$metadata"
	[ -f "$file" ] && cp -p "$file" "$stage/"
done

(
	cd "$stage"
	sha256sum ./* >SHA256SUMS
	sha256sum -c SHA256SUMS
)

"$project/scripts/verify-artifacts.sh" "$tree" "$stage"

echo "Device-specific artifacts staged in $stage"
echo 'Do not publish them without completing docs/RELEASE-CHECKLIST.md.'
