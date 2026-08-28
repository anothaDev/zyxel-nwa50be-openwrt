# Security policy

## Sensitive material

Never attach or commit any of the following:

- ART, SPI NOR, NAND, or configuration dumps
- extracted calibration files
- Zyxel unlock tokens or device passwords
- serial numbers, MAC addresses, SSH keys, or serial-console captures
- private network topology, leases, IP addresses, or firewall exports
- firmware images built with another owner's ART

Treat generated firmware as device-specific unless its calibration provenance
is independently proven generic.

## Reporting

Use a private GitHub security advisory for vulnerabilities that could expose
credentials, overwrite protected flash, bypass regulatory enforcement, or
brick a device. Do not publish working destructive commands before a mitigation
exists.

## Management bootstrap

The image intentionally starts with an empty root password only for physical
UART setup. Dropbear, rpcd, and uHTTPd are disabled, LAN input defaults to
reject, and radios remain disabled until `/root/nwa50be-setup` sets a password
and trusted wired management host CIDR. HTTPS management survives upgrades
without requiring SSH; SSH is enabled only when an `authorized_keys` file
exists. Remote package feeds are disabled.

This is a downstream OpenWrt 25.12.3/TIP base with the selective backports
listed in `docs/BUILD.md`; it is not claimed to contain every security change
from a later upstream OpenWrt release. Before publication, every relevant
OpenWrt 25.12.5 or subsequent advisory must be backported, removed, disabled,
or given an explicit exposure-based disposition in the release review. The
current review cutoff and dispositions are recorded in `docs/SECURITY.md`.

## Supported state

Only the pinned source revisions and exact NWA50BE NAND layout documented in
this repository have been tested. Other models and board revisions are outside
the support boundary.
