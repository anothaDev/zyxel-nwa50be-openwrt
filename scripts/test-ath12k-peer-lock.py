#!/usr/bin/env python3
"""Execute the actual peer_create collision block with instrumented lock stubs.

Accepts reviewed, trusted driver source, not arbitrary untrusted input. This
compiles host C, not a kernel module. The optional single upstream hunk is
applied in memory with exact context matching for before/after regressions.
Firmware timing, concurrent CPUs, and complete station teardown are not modeled.
"""

import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def apply_single_hunk(source: str, patch: str) -> str:
    header = re.search(r"^@@ -(\d+),(\d+) \+(\d+),(\d+) @@[^\n]*\n", patch, re.M)
    if not header or len(re.findall(r"^@@ ", patch, re.M)) != 1:
        raise ValueError("Expected one counted unified diff hunk")
    old_count, new_count = int(header[2]), int(header[4])
    old, new = [], []
    for line in patch[header.end():].splitlines(keepends=True):
        if len(old) == old_count and len(new) == new_count:
            break
        if line.startswith("+"):
            new.append(line[1:])
        elif line.startswith("-"):
            old.append(line[1:])
        else:
            # The pinned upstream patch omits the context marker on several
            # tab-indented lines; preserve those bytes, as GNU patch does.
            context = line[1:] if line.startswith(" ") else line
            old.append(context)
            new.append(context)
    if (len(old), len(new)) != (old_count, new_count):
        raise ValueError("Patch hunk line counts do not match")
    before, after = "".join(old), "".join(new)
    if source.count(before) != 1:
        raise ValueError("Patch context must match the source exactly once")
    return source.replace(before, after, 1)


def collision_block(source: str) -> str:
    function = source[source.index("int ath12k_peer_create("):]
    start = function.index("\tspin_lock_bh(&ar->ab->dp->dp_lock);")
    end = function.index("\tret = ath12k_wmi_send_peer_create_cmd(ar, arg);", start)
    block = function[start:end]
    if "ath12k_peer_create" in block or "ath12k_wmi_send_peer_create_cmd" in block:
        raise ValueError("Unexpected collision block boundaries")
    return block


PRELUDE = r'''
#include <stdbool.h>
#include <stdio.h>
#include <errno.h>
#include <stddef.h>
typedef unsigned int u32;
struct ath12k_dp_link_peer { u32 vdev_id; bool mlo; };
struct fake_dp { int dp_lock; };
struct fake_ab { struct fake_dp *dp; };
struct ath12k { struct fake_ab *ab; int pdev_idx; };
struct ath12k_wmi_peer_create_arg { u32 vdev_id; unsigned char *peer_addr; };
struct scenario {
    const char *name;
    bool initial_peer, same_vdev, mlo, persistent_peer;
    int delete_result, expected_result, expected_delete;
};
static const struct scenario *active;
static struct ath12k_dp_link_peer existing;
static int locked, bh_depth, violations, lookups, deletions;
static void violation(const char *what) {
    violations++;
    printf("  VIOLATION [%s]: %s (locked=%d bh_depth=%d)\n",
           active->name, what, locked, bh_depth);
}
static void spin_lock_bh(int *lock) {
    (void)lock;
    if (locked) violation("locking an already held lock");
    if (bh_depth != 0) violation("lock entered with unbalanced BH nesting");
    bh_depth++;
    locked = 1;
}
static void spin_unlock_bh(int *lock) {
    (void)lock;
    if (!locked) violation("unlocking an unheld lock");
    if (bh_depth != 1) violation("unlock with unbalanced BH nesting");
    locked = 0;
    bh_depth--;
}
static struct ath12k_dp_link_peer *ath12k_dp_link_peer_find_by_pdev_idx(
    struct fake_dp *dp, int pdev, const unsigned char *addr) {
    (void)dp; (void)pdev; (void)addr;
    if (!locked || bh_depth != 1) violation("lookup without balanced lock");
    lookups++;
    if (lookups == 1) return active->initial_peer ? &existing : NULL;
    return active->persistent_peer ? &existing : NULL;
}
static int ath12k_peer_delete(struct ath12k *ar, u32 vdev_id,
                              unsigned char *addr, void *sta) {
    (void)addr; (void)sta;
    deletions++;
    if (locked || bh_depth != 0) violation("sleeping delete entered with lock/BH held");
    if (vdev_id != existing.vdev_id) violation("delete targets wrong original vdev");
    /* Real delete/unassign/wait helpers balance their internal locks and return
     * unlocked. Model that boundary, not hardware completion or concurrency. */
    spin_lock_bh(&ar->ab->dp->dp_lock);
    spin_unlock_bh(&ar->ab->dp->dp_lock);
    spin_lock_bh(&ar->ab->dp->dp_lock);
    spin_unlock_bh(&ar->ab->dp->dp_lock);
    return active->delete_result;
}
#define ath12k_warn(...) ((void)0)
static int tested_collision(struct ath12k *ar,
                            struct ath12k_wmi_peer_create_arg *arg) {
    struct ath12k_dp_link_peer *peer;
    int ret;
'''

POSTLUDE = r'''
    return 0;
}
int main(void) {
    const struct scenario cases[] = {
        { "no_peer",        false, false, false, false, 0, 0, 0 },
        { "same_vdev",      true,  true,  false, false, 0, -EINVAL, 0 },
        { "old_mlo",        true,  false, true,  false, 0, -EINVAL, 0 },
        { "delete_failure", true,  false, false, false, -EIO, -EIO, 1 },
        { "delete_success", true,  false, false, false, 0, 0, 1 },
        { "still_peer",     true,  false, false, true,  0, -EINVAL, 1 },
    };
    struct fake_dp dp = {0};
    struct fake_ab ab = { .dp = &dp };
    struct ath12k ar = { .ab = &ab, .pdev_idx = 0 };
    unsigned char address[6] = {2, 0, 0, 0, 0, 1};
    struct ath12k_wmi_peer_create_arg arg = { .vdev_id = 2, .peer_addr = address };
    int failures = 0;
    for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        active = &cases[i];
        locked = bh_depth = violations = lookups = deletions = 0;
        existing.vdev_id = active->same_vdev ? arg.vdev_id : 1;
        existing.mlo = active->mlo;
        int result = tested_collision(&ar, &arg);
        if (result != active->expected_result) violation("wrong branch result");
        if (deletions != active->expected_delete) violation("wrong delete call count");
        if (locked || bh_depth) violation("unbalanced state on function return");
        printf("%s: %s (ret=%d delete_calls=%d violations=%d)\n", active->name,
               violations ? "FAIL" : "PASS", result, deletions, violations);
        failures += !!violations;
    }
    printf("%d/6 ath12k peer-lock cases passed\n", 6-failures);
    return failures ? 1 : 0;
}
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="actual ath12k peer.c")
    parser.add_argument("--patch", type=Path, help="apply one upstream patch in memory")
    args = parser.parse_args()
    source = args.source.read_text()
    if args.patch:
        source = apply_single_hunk(source, args.patch.read_text())
    block = collision_block(source)
    with tempfile.TemporaryDirectory(prefix="nwa50be-peer-lock-") as scratch:
        binary = str(Path(scratch) / "peer-lock-test")
        subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-x", "c", "-", "-o", binary],
                       input=PRELUDE + block + POSTLUDE, text=True, check=True, timeout=30)
        return subprocess.run([binary], check=False, timeout=10).returncode


if __name__ == "__main__":
    raise SystemExit(main())
