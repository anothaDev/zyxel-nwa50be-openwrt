#!/usr/bin/env python3
"""Offline failure injection through the packaged target's real do_stage2.

Uses the exact target BusyBox under bwrap/binfmt and the packaged platform
dispatch. No host devices, network, AP access, or actual flash operations are
available. Only hardware commands are replaced; nand_* helpers remain real.
Fake UBI files and backup data live only in a private temporary directory.
"""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


HERE = Path(__file__).resolve().parent
STAGE = "/tmp/nwa50be-flash.unset"
FAILURE_CASES = (
    "prep_failure", "kernel_write_failure", "root_write_failure",
    "kernel_readback_corruption", "root_readback_corruption",
    "backup_copy_failure", "mount_failure", "unmount_failure",
    "missing_available", "malformed_available", "malformed_eraseblock_size",
    "backup_readback_corruption", "remount_failure",
)


MOCKS = r'''
record() { printf '%s\n' "$*" >> /tmp/events; }
inject() { record "INJECT $*"; return 1; }
logger() { :; }
sync() { record sync; }
fw_printenv() { return 1; }
fw_setenv() { record 'UNEXPECTED fw_setenv'; return 1; }
mtd() { record 'UNEXPECTED mtd'; return 1; }
ubidetach() {
    record "ubidetach $*"
    /bin/busybox mv /sys/class/ubi/ubi0/mtd_num /sys/class/ubi/ubi0/detached_mtd_num
}
ubiattach() {
    record "ubiattach $*"
    /bin/busybox mv /sys/class/ubi/ubi0/detached_mtd_num /sys/class/ubi/ubi0/mtd_num
}
ubiformat() { record 'UNEXPECTED ubiformat'; return 1; }
mknod() { record 'UNEXPECTED mknod'; return 1; }
ubiblock() { record "ubiblock $*"; return 0; }

vol_id() {
    case "$1" in
        kernel) echo 0;;
        ubi_rootfs) echo 1;;
        rootfs_data) echo 2;;
        *) record "UNEXPECTED volume $1"; return 1;;
    esac
}
vol_name_arg() {
    while [ "$#" -gt 0 ]; do
        if [ "$1" = -N ]; then echo "$2"; return; fi
        shift
    done
    return 1
}
ubirmvol() {
    local name="$(vol_name_arg "$@")" id
    id="$(vol_id "$name")" || return 1
    record "remove $name"
    /bin/busybox rm -f "/sys/class/ubi/ubi0_$id/name" "/dev/ubi0_$id"
}
ubimkvol() {
    local name="$(vol_name_arg "$@")" id
    id="$(vol_id "$name")" || return 1
    record "prepare $name"
    if [ "$SCENARIO" = prep_failure ] && [ "$name" = kernel ]; then
        inject prep_failure; return 1
    fi
    /bin/busybox mkdir -p "/sys/class/ubi/ubi0_$id"
    printf '%s\n' "$name" > "/sys/class/ubi/ubi0_$id/name"
    printf '250:%s\n' "$((id+1))" > "/sys/class/ubi/ubi0_$id/dev"
    : > "/dev/ubi0_$id"
    if [ "$name" = ubi_rootfs ]; then
        case "$SCENARIO" in
            missing_available)
                /bin/busybox rm -f /sys/class/ubi/ubi0/avail_eraseblocks
                record 'INJECT missing_available';;
            malformed_available)
                printf ':\n' > /sys/class/ubi/ubi0/avail_eraseblocks
                record 'INJECT malformed_available';;
            malformed_eraseblock_size)
                printf ':\n' > /sys/class/ubi/ubi0/eraseblock_size
                record 'INJECT malformed_eraseblock_size';;
        esac
    fi
    return 0
}
ubiupdatevol() {
    local device="$1" name length source
    shift
    [ "$1" = -s ] || { record 'UNEXPECTED ubiupdatevol args'; return 1; }
    length="$2"; source="$3"
    case "$device" in
        /dev/ubi0_0) name=kernel;;
        /dev/ubi0_1) name=root;;
        *) record "UNEXPECTED update device $device"; return 1;;
    esac
    record "write $name $length"
    if [ "$SCENARIO" = "${name}_write_failure" ]; then
        [ "$source" != - ] || /bin/busybox cat > /dev/null
        inject "${name}_write_failure"; return 1
    fi
    if [ "$source" = - ]; then
        /bin/busybox cat > "$device"
    else
        /bin/busybox cp "$source" "$device"
    fi
    if [ "$SCENARIO" = "${name}_readback_corruption" ]; then
        printf 'X' | /bin/busybox dd of="$device" bs=1 count=1 conv=notrunc 2>/dev/null
        record "INJECT ${name}_readback_corruption"
    fi
}
mount() {
    local dest="" arg
    for arg in "$@"; do dest="$arg"; done
    case "$dest" in /tmp/*) :;; *) record "UNEXPECTED mount $*"; return 1;; esac
    record "mount $*"
    if [ "$SCENARIO" = mount_failure ]; then inject mount_failure; return 1; fi
    if [ "$SCENARIO" = remount_failure ] && [ -e /tmp/first-mount ]; then
        inject remount_failure; return 1
    fi
    : > /tmp/first-mount
    /bin/busybox mkdir -p /tmp/persisted-overlay
    /bin/busybox rmdir "$dest" || return 1
    /bin/busybox ln -s /tmp/persisted-overlay "$dest"
}
umount() {
    record "umount $*"
    [ "$1" = -a ] && return 0
    if [ "$SCENARIO" = unmount_failure ]; then inject unmount_failure; return 1; fi
    case "$1" in /tmp/*) :;; *) record "UNEXPECTED umount $*"; return 1;; esac
    if [ "$SCENARIO" = backup_readback_corruption ] && [ ! -e /tmp/backup-corrupted ]; then
        printf 'X' | /bin/busybox dd of=/tmp/persisted-overlay/sysupgrade.tgz bs=1 count=1 conv=notrunc 2>/dev/null
        : > /tmp/backup-corrupted
        record 'INJECT backup_readback_corruption'
    fi
    /bin/busybox rm -f "$1" || return 1
    /bin/busybox mkdir -p "$1"
}
cp() {
    if [ "$SCENARIO" = backup_copy_failure ]; then
        case "$*" in *sysupgrade.tgz*) inject backup_copy_failure; return 1;; esac
    fi
    /bin/busybox cp "$@"
}
mv() {
    if [ "$SCENARIO" = backup_copy_failure ]; then
        case "$*" in *sysupgrade.tgz*) inject backup_copy_failure; return 1;; esac
    fi
    /bin/busybox mv "$@"
}
sleep() {
    record "sleep $*"
    if [ "$1" -ge 30 ]; then
        record FAILSTOP_WAIT
        /bin/busybox sleep "$1"
    fi
}
reboot() { record REBOOT; exit 80; }
'''


def write(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value)


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run_case(args, scenario: str):
    with tempfile.TemporaryDirectory(prefix="nwa50be-guard-test-") as directory:
        scratch = Path(directory)
        for name in (STAGE.lstrip("/"), "sys/class/ubi", "proc", "upgrade"):
            (scratch / name).mkdir(parents=True, exist_ok=True)
        write(scratch / "proc/mtd", 'dev:    size   erasesize  name\nmtd2: 08000000 00020000 "rootfs"\n')
        write(scratch / "proc/sysrq-trigger", "")
        write(scratch / "tmp/sysinfo/board_name", "zyxel,nwa50be\n")
        for key, value in {"mtd_num": "2", "dev": "250:0", "avail_eraseblocks": "188", "eraseblock_size": "126976"}.items():
            write(scratch / "sys/class/ubi/ubi0" / key, value + "\n")
        for number, name in enumerate(("kernel", "ubi_rootfs", "rootfs_data")):
            write(scratch / f"sys/class/ubi/ubi0_{number}/name", name + "\n")
            write(scratch / f"sys/class/ubi/ubi0_{number}/dev", f"250:{number + 1}\n")
        shutil.copyfile(args.backup, scratch / "tmp/sysupgrade.tgz")
        for path in (args.packaged / "lib/upgrade").glob("*.sh"):
            shutil.copyfile(path, scratch / "upgrade" / path.name)
        source = args.packaged / "lib/upgrade" if args.original else args.guard
        shutil.copyfile(source / "nand.sh", scratch / "upgrade/nand.sh")
        shutil.copyfile(source / "do_stage2", scratch / "upgrade/do_stage2")
        (scratch / "upgrade/do_stage2").chmod(0o700)
        write(scratch / "upgrade/zz-test-hardware.sh", MOCKS)
        write(scratch / "tmp/entry.sh", f"export IMAGE={STAGE}/image.tar UPGRADE_BACKUP=/tmp/sysupgrade.tgz VERBOSE=1\nfor device in /dev/ubi0 /dev/ubi0_0 /dev/ubi0_1 /dev/ubi0_2; do : > \"$device\"; done\nexec /lib/upgrade/do_stage2\n")
        command = [
            "bwrap", "--unshare-all", "--die-with-parent", "--cap-drop", "ALL",
            "--ro-bind", str(args.packaged), "/",
            "--bind", str(scratch / "tmp"), "/tmp",
            "--bind", str(scratch / "sys"), "/sys",
            "--bind", str(scratch / "proc"), "/proc",
            "--dev", "/dev",
            "--ro-bind", str(scratch / "upgrade"), "/lib/upgrade",
            "--ro-bind", str(args.image), f"{STAGE}/image.tar",
            "--setenv", "PATH", "/usr/sbin:/usr/bin:/sbin:/bin",
            "--setenv", "SCENARIO", scenario,
        ]
        # Entry creates ordinary files in bwrap's private /dev, not host nodes.
        command += ["--", "/bin/busybox", "sh", "/tmp/entry.sh"]
        with (scratch / "output.log").open("w+") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + 30
            held = False
            while process.poll() is None:
                events_path = scratch / "tmp/events"
                events = events_path.read_text() if events_path.exists() else ""
                if "FAILSTOP_WAIT" in events:
                    held = True
                    os.killpg(process.pid, signal.SIGTERM)
                    break
                if time.monotonic() > deadline:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                    raise AssertionError(f"{scenario}: sandbox timed out without a fail-stop marker")
                time.sleep(0.05)
            process.wait(timeout=5)
            output.seek(0)
            captured = output.read()
        events_path = scratch / "tmp/events"
        events = events_path.read_text() if events_path.exists() else ""
        backup = scratch / "tmp/persisted-overlay/sysupgrade.tgz"
        return {
            "events": events, "output": captured, "returncode": process.returncode,
            "held": held, "sysrq": (scratch / "proc/sysrq-trigger").read_text(),
            "backup_ok": backup.is_file() and digest(backup) == digest(args.backup),
            "ram_backup_ok": (scratch / "tmp/sysupgrade.tgz").is_file()
            and digest(scratch / "tmp/sysupgrade.tgz") == digest(args.backup),
        }


def check_failure(result, scenario: str) -> None:
    assert f"INJECT {scenario}" in result["events"], "fault was never reached"
    assert "REBOOT" not in result["events"], "reboot called after injected failure"
    assert not result["sysrq"], "sysrq reboot fallback called after failure"
    assert "sysupgrade successful" not in result["output"], "NAND reported success after failure"
    assert "Upgrade completed" not in result["output"], "stage2 reported completion after failure"
    assert "NWA50BE_GUARD_VERIFIED" not in result["output"], "guard reported verification after failure"
    assert "NWA50BE_GUARD_FAILED" in result["output"], "guard did not announce failure"
    assert result["held"], "stage2 did not remain in the fail-stop wait"
    assert "UNEXPECTED" not in result["events"], "unexpected hardware operation"
    if scenario in ("prep_failure", "missing_available", "malformed_available", "malformed_eraseblock_size"):
        assert "write " not in result["events"], "payload written after preparation failure"
    if scenario == "kernel_write_failure":
        assert "write root " not in result["events"], "root written after kernel failure"


def check_success(result) -> None:
    assert result["returncode"] == 80, "successful stage2 did not reach fake reboot"
    assert result["events"].count("REBOOT\n") == 1, "expected exactly one reboot"
    assert "INJECT" not in result["events"] and "UNEXPECTED" not in result["events"], "unexpected hardware/fault operation"
    assert not result["held"] and not result["sysrq"], "success used failure or fallback path"
    assert "NWA50BE_GUARD_FAILED" not in result["output"], "success announced failure"
    assert "NWA50BE_GUARD_VERIFIED" in result["output"], "guard never announced complete verification"
    assert result["events"].count("write kernel ") == 1, "kernel not written exactly once"
    assert result["events"].count("write root ") == 1, "root not written exactly once"
    mounts = [line for line in result["events"].splitlines() if line.startswith("mount ")]
    assert len(mounts) == 2 and "-o ro" in mounts[1], "backup not checked across a read-only remount"
    assert result["backup_ok"], "preserved backup bytes do not match the original"
    assert result["ram_backup_ok"], "original RAM backup was not retained"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packaged", type=Path, required=True, help="unpacked rootfs of the image under test")
    parser.add_argument("--guard", type=Path, required=True, help="guard directory made by make-flash-guard.sh")
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--backup", type=Path, required=True)
    parser.add_argument("--original", action="store_true", help="exercise original package, expecting regression tests to fail")
    parser.add_argument("--case", choices=(*FAILURE_CASES, "success", "all"), default="all")
    args = parser.parse_args()
    for name in ("packaged", "guard", "image", "backup"):
        setattr(args, name, getattr(args, name).resolve())
    global STAGE
    STAGE = (args.guard.parent / "stage-dir").read_text().strip()
    cases = (*FAILURE_CASES, "success") if args.case == "all" else (args.case,)
    failures = 0
    for scenario in cases:
        result = run_case(args, scenario)
        try:
            if scenario == "success":
                check_success(result)
            else:
                check_failure(result, scenario)
        except AssertionError as error:
            print(f"FAIL {scenario}: {error}", flush=True)
            print(result["events"])
            print(result["output"], flush=True)
            failures += 1
        else:
            description = "verified firmware and backup, then one reboot" if scenario == "success" else "injected failure held; no success, reboot, or sysrq"
            print(f"PASS {scenario}: {description}", flush=True)
    print(f"{len(cases) - failures}/{len(cases)} offline upgrade guard cases passed")
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
