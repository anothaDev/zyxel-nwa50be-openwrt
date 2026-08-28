# Release checklist

- [x] Repository visibility is private as of 2026-08-28.
- [ ] No GitHub tags, releases, Actions artifacts, or packages exist.
- [x] Actions is restricted to the required SHA-pinned actions.
- [ ] Before public visibility, `main` blocks force-pushes and deletion and
      requires the `audit` check. If private-plan branch rules are unavailable,
      the repository stays private until this can be configured.
- [ ] `scripts/audit-public-tree.sh` passes from a fresh clone.
- [x] Reachable Git history passed the private-data and forbidden-file audit.
- [x] Commit author metadata is project-neutral.
- [x] No private files are present in reachable Git objects, releases, Actions
      artifacts, issues, or pull requests.
- [x] Installation warnings are visible before any write command.
- [x] Source pins and patch order reproduce a clean build.
- [x] The prepared-source fingerprint still passes after the build.
- [ ] Every OpenWrt 25.12.5 security item affecting an installed or enabled
      component is backported, removed, disabled, or explicitly documented.
- [ ] A second person reviews NAND geometry and installer commands.
- [ ] Every selected package has a reviewed license inventory.
- [ ] Firmware-blob redistribution terms are explicit and archived.
- [ ] A release image contains no ART, calibration, credentials, SSH keys,
      usernames, hostnames, or local paths.
- [x] Public claims distinguish observation, inference, and unknown intent.
- [x] The repository remains private until every applicable item passes.
