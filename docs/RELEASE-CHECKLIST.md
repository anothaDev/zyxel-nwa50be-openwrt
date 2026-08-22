# Release checklist

- [ ] Repository visibility is private.
- [ ] `scripts/audit-public-tree.sh` passes from a fresh clone.
- [ ] Git history contains only sanitized commits.
- [ ] Commit author metadata is project-neutral.
- [ ] No private files are present in Git objects, releases, Actions artifacts,
      issues, or pull requests.
- [ ] Installation warnings are visible before any write command.
- [ ] Source pins and patch order reproduce a clean build.
- [ ] A second person reviews NAND geometry and installer commands.
- [ ] Every selected package has a reviewed license inventory.
- [ ] Firmware-blob redistribution terms are explicit and archived.
- [ ] A release image contains no ART, calibration, credentials, SSH keys,
      usernames, hostnames, or local paths.
- [ ] Public claims distinguish observation, inference, and unknown intent.
- [ ] The repository remains private until every applicable item passes.
