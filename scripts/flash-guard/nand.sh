# Copyright (C) 2014 OpenWrt.org
#
# OpenWrt's lib/upgrade/nand.sh, sourced by sysupgrade, with the NWA50BE
# guard; kept close to upstream, so upstream's shell style is not linted.
# shellcheck shell=sh disable=SC1091,SC2004,SC2034,SC2046,SC2086,SC2155,SC2166,SC2231,SC3040,SC3043,SC3057

. /lib/functions.sh

# 'kernel' partition or UBI volume on NAND contains the kernel
CI_KERNPART="${CI_KERNPART:-kernel}"

# 'ubi' partition on NAND contains UBI
CI_UBIPART="${CI_UBIPART:-ubi}"

# 'rootfs' UBI volume on NAND contains the rootfs
CI_ROOTPART="${CI_ROOTPART:-rootfs}"

# ipq807x qsdk kernel misbehaves
CI_IPQ807X=0

# update BOOTCONFIG partitions (rotate rootfs/rootfs_1)
CI_BOOTCFG=0

# update uboot-env if upgrade suceeded
CI_FWSETENV=

ubi_mknod() {
	local dir="$1"
	local dev="/dev/$(basename $dir)"

	[ -e "$dev" ] && return 0

	local devid="$(cat $dir/dev)"
	local major="${devid%%:*}"
	local minor="${devid##*:}"
	mknod "$dev" c $major $minor
}

ubi_sysfs_root() {
	if [ -d /sys/class/ubi ]; then
		echo /sys/class/ubi
	else
		echo /sys/devices/virtual/ubi
	fi
}

nand_find_volume() {
	local ubidevdir ubivoldir ubiroot
	ubiroot="$(ubi_sysfs_root)"
	if [ "$ubiroot" = "/sys/class/ubi" ]; then
		ubidevdir="$ubiroot"
	else
		ubidevdir="$ubiroot/$1"
	fi
	[ ! -d "$ubidevdir" ] && return 1
	for ubivoldir in $ubidevdir/${1}_*; do
		[ ! -d "$ubivoldir" ] && continue
		[ ! -f "$ubivoldir/name" ] && continue
		if [ "$( cat $ubivoldir/name )" = "$2" ]; then
			basename $ubivoldir
			ubi_mknod "$ubivoldir"
			return 0
		fi
	done
}

nand_find_ubi() {
	local ubidevdir ubidev mtdnum ubiroot
	mtdnum="$( find_mtd_index $1 )"
	[ ! "$mtdnum" ] && return 1
	ubiroot="$(ubi_sysfs_root)"
	for ubidevdir in $ubiroot/ubi*; do
		[ ! -d "$ubidevdir" ] && continue
		[ ! -f "$ubidevdir/mtd_num" ] && continue
		cmtdnum="$( cat $ubidevdir/mtd_num )"
		[ ! "$mtdnum" ] && continue
		if [ "$mtdnum" = "$cmtdnum" ]; then
			ubidev=$( basename $ubidevdir )
			ubi_mknod "$ubidevdir"
			echo $ubidev
			return 0
		fi
	done
}

nand_get_magic_long() {
	dd if="$1" skip=$2 bs=4 count=1 2>/dev/null | hexdump -v -n 4 -e '1/1 "%02x"'
}

get_magic_long_tar() {
	( tar xf $1 $2 -O | dd bs=4 count=1 | hexdump -v -n 4 -e '1/1 "%02x"') 2> /dev/null
}

identify_magic() {
	local magic=$1
	case "$magic" in
		"55424923")
			echo "ubi"
			;;
		"31181006")
			echo "ubifs"
			;;
		"68737173")
			echo "squashfs"
			;;
		"d00dfeed")
			echo "fit"
			;;
		"4349"*)
			echo "combined"
			;;
		*)
			echo "unknown $magic"
			;;
	esac
}


identify() {
	identify_magic $(nand_get_magic_long "$1" "${2:-0}")
}

identify_tar() {
	identify_magic $(get_magic_long_tar "$1" "$2")
}

nand_restore_config() {
	local expected=@BACKUP_SHA@
	[ "$(/bin/busybox sha256sum "$1" | awk '{print $1}')" = "$expected" ] || return 1
	/bin/busybox gzip -t "$1" || return 1
	sync || return 1
	local ubidev=$( nand_find_ubi $CI_UBIPART )
	local ubivol="$( nand_find_volume $ubidev rootfs_data )"
	[ -n "$ubivol" ] || return 1
	[ "$BACKUP_FILE" = sysupgrade.tgz ] || return 1
	mkdir /tmp/new_root || return 1
	if ! mount -t ubifs /dev/$ubivol /tmp/new_root; then
		echo "mounting ubifs $ubivol failed"
		rmdir /tmp/new_root
		return 1
	fi
	# Retain the RAM copy, and verify the persistent copy across a remount.
	cp "$1" "/tmp/new_root/$BACKUP_FILE" || return 1
	sync || return 1
	umount /tmp/new_root || return 1
	mount -t ubifs -o ro /dev/$ubivol /tmp/new_root || return 1
	[ "$(/bin/busybox sha256sum "/tmp/new_root/$BACKUP_FILE" | awk '{print $1}')" = "$expected" ] || return 1
	/bin/busybox gzip -t "/tmp/new_root/$BACKUP_FILE" || return 1
	umount /tmp/new_root || return 1
	rmdir /tmp/new_root
}

nand_upgrade_prepare_ubi() {
	local rootfs_length="$1"
	local rootfs_type="$2"
	local rootfs_data_max="$(fw_printenv -n rootfs_data_max 2>/dev/null)"
	[ -n "$rootfs_data_max" ] && rootfs_data_max=$(printf %d "$rootfs_data_max")

	local kernel_length="$3"
	local has_env="${4:-0}"

	[ -n "$rootfs_length" -o -n "$kernel_length" ] || return 1

	local mtdnum="$( find_mtd_index "$CI_UBIPART" )"
	if [ ! "$mtdnum" ]; then
		echo "cannot find ubi mtd partition $CI_UBIPART"
		return 1
	fi

	if [ "$CI_IPQ807X" = 1 ]; then
		ubidetach -f -m "$mtdnum" || return 1
	fi

	local ubidev="$( nand_find_ubi "$CI_UBIPART" )"
	if [ ! "$ubidev" ]; then
		ubiattach -m "$mtdnum" || return 1
		sync
		ubidev="$( nand_find_ubi "$CI_UBIPART" )"
	fi

	if [ ! "$ubidev" ]; then
		echo 'Refusing destructive UBI reformat fallback' >&2
		return 1
	fi

	local kern_ubivol="$( nand_find_volume $ubidev $CI_KERNPART )"
	local root_ubivol="$( nand_find_volume $ubidev $CI_ROOTPART )"
	local data_ubivol="$( nand_find_volume $ubidev rootfs_data )"

	local ubiblk ubiblkvol
	for ubiblk in /dev/ubiblock*_? ; do
		[ -e "$ubiblk" ] || continue
		echo "removing ubiblock${ubiblk:13}"
		ubiblkvol=ubi${ubiblk:13}
		if ! ubiblock -r /dev/$ubiblkvol; then
			echo "cannot remove $ubiblk"
			return 1
		fi
	done

	# kill volumes
	[ -n "$kern_ubivol" ] && [ -n "$root_ubivol" ] && [ -n "$data_ubivol" ] || return 1
	[ "$root_ubivol" != "$kern_ubivol" ] || return 1
	ubirmvol /dev/$ubidev -N "$CI_KERNPART" || return 1
	ubirmvol /dev/$ubidev -N "$CI_ROOTPART" || return 1
	ubirmvol /dev/$ubidev -N rootfs_data || return 1

	# update kernel
	if [ -n "$kernel_length" ]; then
		if ! ubimkvol /dev/$ubidev -N $CI_KERNPART -s $kernel_length; then
			echo "cannot create kernel volume"
			return 1;
		fi
	fi

	# update rootfs
	if [ -n "$rootfs_length" ]; then
		local rootfs_size_param
		if [ "$rootfs_type" = "ubifs" ]; then
			rootfs_size_param="-m"
		else
			rootfs_size_param="-s $rootfs_length"
		fi
		if ! ubimkvol /dev/$ubidev -N $CI_ROOTPART $rootfs_size_param; then
			echo "cannot create rootfs volume"
			return 1;
		fi
	fi

	# create rootfs_data for non-ubifs rootfs
	if [ "$rootfs_type" != "ubifs" ]; then
		local ubidevdir="$(ubi_sysfs_root)/$ubidev"
		local availeb ebsize
		availeb=$(cat "$ubidevdir/avail_eraseblocks") || return 1
		ebsize=$(cat "$ubidevdir/eraseblock_size") || return 1
		case "$availeb" in ''|0*|*[!0-9]*) return 1 ;; esac
		[ "$availeb" -le 480 ] && [ "$ebsize" = 126976 ] || return 1
		local avail_size=$(( $availeb * $ebsize ))
		local rootfs_data_size_param="-m"
		if [ -n "$rootfs_data_max" ] &&
		   [ "$rootfs_data_max" != "0" ] &&
		   [ "$rootfs_data_max" -le "$avail_size" ]; then
			rootfs_data_size_param="-s $rootfs_data_max"
		fi
		if ! ubimkvol /dev/$ubidev -N rootfs_data $rootfs_data_size_param; then
			echo "cannot initialize rootfs_data volume"
			return 1
		fi
	fi
	sync || return 1
	return 0
}

nand_qca_update_bootconfig() {
	local primary="0"
	local mtdnum
	local part

	[ -f /proc/boot_info/bootconfig0/rootfs/primaryboot ] || [ -f /proc/boot_info/bootconfig1/rootfs/primaryboot ] || return
	[ -f /proc/boot_info/bootconfig0/getbinary_bootconfig ] || [ -f /proc/boot_info/bootconfig1/rootfs/primaryboot ] || return

	[ "$(cat /proc/boot_info/bootconfig0/rootfs/primaryboot)" = "0" ] && [ "$(cat /proc/boot_info/bootconfig1/rootfs/primaryboot)" = "0" ] && primary="1"
	echo "$primary" > /proc/boot_info/bootconfig0/rootfs/primaryboot 2>/dev/null
	echo "$primary" > /proc/boot_info/bootconfig1/rootfs/primaryboot 2>/dev/null

	for part in "0:BOOTCONFIG" "0:BOOTCONFIG1"; do
		mtdnum="$(find_mtd_index "$part")"
		[ -c "/dev/mtd${mtdnum}" ] && {
			mtd -qq write /proc/boot_info/bootconfig0/getbinary_bootconfig \
				"/dev/mtd${mtdnum}" 2>/dev/null &&\
			mtd -qq write /proc/boot_info/bootconfig1/getbinary_bootconfig \
				"/dev/mtd${mtdnum}" 2>/dev/null &&\
			echo "partition '$part' updated"
		}
	done
}

nand_do_upgrade_success() {
	local conf_tar="/tmp/sysupgrade.tgz"
	[ "$CI_BOOTCFG" = 0 ] && [ -z "$CI_FWSETENV" ] || return 1
	[ -f "$conf_tar" ] || return 1
	nand_restore_config "$conf_tar" || return 1
	sync || return 1
	echo 'NWA50BE_GUARD_VERIFIED: firmware readback and preserved configuration'
	return 0
}

# Flash the UBI image to MTD partition
nand_upgrade_ubinized() {
	local ubi_file="$1"
	local mtdnum="$(find_mtd_index "$CI_UBIPART")"

	[ ! "$mtdnum" ] && {
		CI_UBIPART="rootfs"
		mtdnum="$(find_mtd_index "$CI_UBIPART")"
	}

	if [ ! "$mtdnum" ]; then
		echo "cannot find mtd device $CI_UBIPART"
		umount -a
		reboot -f
	fi

	local mtddev="/dev/mtd${mtdnum}"
	ubidetach -p "${mtddev}" || true
	sync
	ubiformat "${mtddev}" -y -f "${ubi_file}"
	ubiattach -p "${mtddev}"
	nand_do_upgrade_success
}

# Write the UBIFS image to UBI volume
nand_upgrade_ubifs() {
	local rootfs_length=$( (cat $1 | wc -c) 2> /dev/null)

	nand_upgrade_prepare_ubi "$rootfs_length" "ubifs" "" ""

	local ubidev="$( nand_find_ubi "$CI_UBIPART" )"
	local root_ubivol="$(nand_find_volume $ubidev $CI_ROOTPART)"
	ubiupdatevol /dev/$root_ubivol -s $rootfs_length $1

	nand_do_upgrade_success
}

nand_upgrade_fit() {
	local fit_file="$1"
	local fit_length="$(wc -c < "$fit_file")"

	nand_upgrade_prepare_ubi "" "" "$fit_length" "1"

	local fit_ubidev="$(nand_find_ubi "$CI_UBIPART")"
	local fit_ubivol="$(nand_find_volume $fit_ubidev "$CI_KERNPART")"
	ubiupdatevol /dev/$fit_ubivol -s $fit_length $fit_file

	nand_do_upgrade_success
}

nand_upgrade_tar() {
	local tar_file="$1"
	local stage=@STAGE@
	local payload="$stage/sysupgrade-zyxel_nwa50be"
	local kernel_length=@KERNEL_LEN@
	local rootfs_length=@ROOT_LEN@
	local kernel_hash=@KERNEL_SHA@
	local rootfs_hash=@ROOT_SHA@

	[ "$(board_name)" = 'zyxel,nwa50be' ] || return 1
	[ "$CI_UBIPART" = rootfs ] && [ "$CI_ROOTPART" = ubi_rootfs ] && [ "$CI_KERNPART" = kernel ] || return 1
	[ "$CI_IPQ807X" = 1 ] && [ "$CI_BOOTCFG" = 0 ] && [ -z "$CI_FWSETENV" ] || return 1
	[ "$(find_mtd_index rootfs)" = 2 ] || return 1
	[ ! -e /tmp/new_root ] && [ ! -L /tmp/new_root ] || return 1
	[ "$tar_file" = "$stage/image.tar" ] || return 1
	[ "$(/bin/busybox sha256sum "$tar_file" | awk '{print $1}')" = @IMAGE_SHA@ ] || return 1
	[ "$(/bin/busybox sha256sum /tmp/sysupgrade.tgz | awk '{print $1}')" = @BACKUP_SHA@ ] || return 1
	# Extract and validate both complete payloads before deleting any volume.
	tar xf "$tar_file" -C "$stage" sysupgrade-zyxel_nwa50be/kernel sysupgrade-zyxel_nwa50be/root || return 1
	[ "$(/bin/busybox sha256sum "$payload/kernel" | awk '{print $1}')" = "$kernel_hash" ] || return 1
	[ "$(/bin/busybox sha256sum "$payload/root" | awk '{print $1}')" = "$rootfs_hash" ] || return 1
	nand_upgrade_prepare_ubi "$rootfs_length" squashfs "$kernel_length" 0 || return 1

	local ubidev="$(nand_find_ubi "$CI_UBIPART")"
	local kern_ubivol="$(nand_find_volume "$ubidev" "$CI_KERNPART")"
	local root_ubivol="$(nand_find_volume "$ubidev" "$CI_ROOTPART")"
	[ -n "$ubidev" ] && [ -n "$kern_ubivol" ] && [ -n "$root_ubivol" ] || return 1
	ubiupdatevol "/dev/$kern_ubivol" -s "$kernel_length" "$payload/kernel" || return 1
	ubiupdatevol "/dev/$root_ubivol" -s "$rootfs_length" "$payload/root" || return 1
	sync || return 1
	local digest
	digest=$(set -o pipefail; /bin/busybox head -c "$kernel_length" "/dev/$kern_ubivol" | /bin/busybox sha256sum) || return 1
	[ "${digest%% *}" = "$kernel_hash" ] || return 1
	digest=$(set -o pipefail; /bin/busybox head -c "$rootfs_length" "/dev/$root_ubivol" | /bin/busybox sha256sum) || return 1
	[ "${digest%% *}" = "$rootfs_hash" ] || return 1
	nand_do_upgrade_success
}

# Recognize type of passed file and start the upgrade process
nand_do_upgrade() {
	local file_type=$(identify $1)

	[ ! "$( find_mtd_index "$CI_UBIPART" )" ] && CI_UBIPART="rootfs"

	case "$file_type" in
		"fit")		nand_upgrade_fit $1;;
		"ubi")		nand_upgrade_ubinized $1;;
		"ubifs")	nand_upgrade_ubifs $1;;
		*)		nand_upgrade_tar $1;;
	esac
}

# Check if passed file is a valid one for NAND sysupgrade. Currently it accepts
# 3 types of files:
# 1) UBI - should contain an ubinized image, header is checked for the proper
#    MAGIC
# 2) UBIFS - should contain UBIFS partition that will replace "rootfs" volume,
#    header is checked for the proper MAGIC
# 3) TAR - archive has to include "sysupgrade-BOARD" directory with a non-empty
#    "CONTROL" file (at this point its content isn't verified)
#
# You usually want to call this function in platform_check_image.
#
# $(1): board name, used in case of passing TAR file
# $(2): file to be checked
nand_do_platform_check() {
	local board_name="$1"
	local tar_file="$2"
	local control_length=$( (tar xf $tar_file sysupgrade-$board_name/CONTROL -O | wc -c) 2> /dev/null)
	local file_type="$(identify $2)"

	[ "$control_length" = 0 -a "$file_type" != "ubi" -a "$file_type" != "ubifs" -a "$file_type" != "fit" ] && {
		echo "Invalid sysupgrade file."
		return 1
	}

	return 0
}
