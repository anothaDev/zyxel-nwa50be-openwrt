# Licensing and release boundary

The project scripts and original documentation use BSD-3-Clause. Patch files
modify TIP/OpenWiFi, OpenWrt, Linux, and package sources and remain under their
respective upstream licenses.

| Patches | Upstream file license |
| --- | --- |
| `0001`, `0005` | GPL-2.0-or-later OR BSD-3-Clause |
| `0002`, `0003`, `0004`, `0010` | GPL-2.0-only |
| `0006`, `0007`, `0009` | ISC |
| `0008` | BSD-3-Clause TIP package wrapper |

The pinned TIP/OpenWiFi repository is published under BSD-3-Clause and publicly
contains the Qualcomm firmware consumed by the NWA50BE profile. However, the
`ath12k-firmware` package does not declare `PKG_LICENSE`, and its package tree
contains no `LICENSE`, `NOTICE`, or `COPYING` file. Public availability is not,
by itself, a clear redistribution grant for a third-party firmware release.

The selected `qca-ssdk-shell` package also omits `PKG_LICENSE`. Its pinned
CodeLinaro source tree contains no license file or licensing notice. This
project does not redistribute that source or its build-race patch; the build
uses a bounded local dependency bootstrap instead.

Accordingly:

- this repository does not copy Qualcomm firmware blobs;
- this repository does not distribute a prebuilt image;
- local builders fetch the pinned upstream tree directly;
- binary release assets remain blocked until a complete selected-package
  inventory is reviewed and explicit redistribution terms are identified;
- all per-device ART and calibration remain private regardless of blob terms.

This document records an engineering release boundary, not legal advice.
