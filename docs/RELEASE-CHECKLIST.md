# Release checklist

Public source visibility and public binary distribution are separate gates.
Passing the source checklist does not authorize publishing firmware images.

## Public source visibility

- [x] No GitHub tags, releases, Actions artifacts, or packages exist.
- [x] Actions is restricted to the required SHA-pinned actions.
- [x] The visibility transition is complete and `main` blocks force-pushes and
      deletion, requires the `audit` check, and applies the rule to
      administrators. If those controls cannot be configured immediately after
      the repository becomes public, restore private visibility.
- [x] `scripts/audit-public-tree.sh` passes from a fresh clone.
- [x] Reachable Git history passed the private-data and forbidden-file audit.
- [x] Commit author metadata is project-neutral.
- [x] No private files are present in reachable Git objects, releases, Actions
      artifacts, issues, or pull requests.
- [x] Installation warnings are visible before any write command.
- [x] Source pins and patch order reproduce a clean build.
- [x] The prepared-source fingerprint still passes after the build.
- [x] Every reviewed upstream security item published through 2026-08-28 and
      affecting an installed or enabled
      component is backported, removed, disabled, or explicitly documented.
- [x] A clean private artifact build passed structural, package, security, and
      build-metadata verification; it remains device-specific and private.
- [x] Public claims distinguish observation, inference, and unknown intent.
- [x] An unauthenticated clone of the public repository passes the same audit.

## Binary release blockers

- [ ] A second person reviews NAND geometry and installer commands.
- [ ] Every selected package has a reviewed license inventory.
- [ ] Firmware-blob redistribution terms are explicit and archived.
- [ ] A release image contains no ART, calibration, credentials, SSH keys,
      usernames, hostnames, or local paths.
- [ ] A release candidate is rebuilt from clean public source and receives an
      independent installation and recovery review.

No tag, release, package, Actions artifact, or firmware download may be
published until every binary-release item passes.
