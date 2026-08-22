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

## Supported state

Only the pinned source revisions and exact NWA50BE NAND layout documented in
this repository have been tested. Other models and board revisions are outside
the support boundary.
