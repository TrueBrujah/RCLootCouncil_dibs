# Quickstart: Addon Release Operations

Use this checklist for every release. The detailed workflow and package layout are documented in [the developer release guide](../../docs/developer/releasing.md).

## One-Time Setup

- [ ] Install the repository-scoped GitHub App on `TrueBrujah/RCLootCouncil_dibs` with Contents read/write only.
- [ ] Add repository variable `RELEASE_TAG_APP_ID` and secret `RELEASE_TAG_APP_PRIVATE_KEY` under Settings > Secrets and variables > Actions. Never commit or share the private key.
- [ ] Confirm the root `.pkgmeta` maps repository `src/` into `RCLootCouncil_dibs/` and the package contains `RCLootCouncil_dibs/RCLootCouncil_dibs.toc` at its root.
- [ ] Connect the CurseForge project to the GitHub repository/tag packager and confirm beta/stable channel mapping.

## New CurseForge Project Approval

- [ ] Complete the project title, description, game/version, addon category, license, source link, and relevant icon/media with accurate information.
- [ ] Keep the first release ZIP available for review; verify its addon folder and TOC layout from the GitHub release asset.
- [ ] If CurseForge says the project is awaiting moderator approval, treat file visibility/synchronization as blocked until approval. Do not create a duplicate project or repeatedly push tags to work around the review gate.
- [ ] If CurseForge requests clarification, answer in the project review flow. If the review exceeds CurseForge's stated guidance, contact support with the project URL; do not include credentials.

## Beta Release

- [ ] Push validated changes to `dev`.
- [ ] In Actions, confirm **Run addon test suite** and **Build addon package** succeed.
- [ ] Confirm **Tag tested dev build** succeeds and the generated `v<VERSION>-beta.<RUN_NUMBER>` tag points to the tested commit.
- [ ] Open the GitHub prerelease and verify the addon ZIP and `.sha256` checksum are present.
- [ ] After CurseForge approval, verify the matching beta file appears in the project's Files page and is classified as Beta.

## Stable Release

- [ ] Merge validated `dev` into `main` through a reviewed pull request.
- [ ] Verify the TOC version and explicitly create/push the matching stable `v<VERSION>` tag.
- [ ] Verify the normal GitHub release contains the addon ZIP and checksum.
- [ ] Verify the file appears on CurseForge in the stable channel.

## RC Caution

Do not push `-rc.<N>` tags while the CurseForge integration processes every tag unless RC tags are explicitly excluded or mapped. GitHub marks RC tags as prereleases, but CurseForge may classify them as Release.