# Licensing and release boundary

The project scripts and original documentation use BSD-3-Clause. Patch files
modify TIP/OpenWiFi, OpenWrt, Linux, and package sources and remain under their
respective upstream licenses.

| Patches | Upstream file license |
| --- | --- |
| `0001`, `0005` | GPL-2.0-or-later OR BSD-3-Clause |
| `0002`, `0003`, `0004`, `0010`, `0011`, `0012`, `0013`, `0016`, `0017`, `0019`, `0022`, `0026`, `0027`, `0028`, `0029`, `0030`, `0031`, `0032`, `0033`, `0034`, `0035`, `0036`, `0037`, `0038`, `0040`, `0041`, `0042`, `0043`, `0044`, `0045`, `0046`, `0047`, `0048`, `0049`, `0050`, `0051`, `0052`, `0053`, `0054`, `0056`, `0058`, `0059`, `0060`, `0061`, `0062` | GPL-2.0-only |
| `0006`, `0007` | ISC |
| `0008`, `0009`, `0015` | BSD-3-Clause TIP package wrapper |
| `0014`, `0018`, `0020`, `0039`, `0055`, `0057`, `0063` | Apache-2.0 LuCI collection |
| `0024`, `0025` | BSD-3-Clause hostapd source |
| `0021` | BSD-3-Clause-Clear ath12k source |

Each patch carries an SPDX identifier. Applicable license texts are included
under `LICENSES/`; the root `LICENSE` covers only this project's original
scripts and documentation. `NOTICE` retains the concrete upstream copyright
and Apache NOTICE attributions for the BSD, ISC, and LuCI source represented in
the patch files.

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
