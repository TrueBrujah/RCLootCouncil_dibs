# Release process

Version numbers in commands below illustrate the intended next source version;
they do not prove that tag or download exists. Check GitHub Releases and the
TOC independently, then update published download links only after publication.
As checked on 2026-10-16, stable v0.8.9 is published and matches the TOC version.
See [the installation guide](../INSTALLATION.md) for the published ZIP.

CurseForge's native packager/webhook publishes packages when it receives Git tags. It determines Beta versus Release from the tag name, not from the branch. GitHub Actions do not upload directly to CurseForge.

CurseForge marks tags containing `alpha` as Alpha and tags containing `beta` as Beta; other tag names are marked as Release. Keep local development checkpoints on the `dev` branch and identify the loaded code with `/dibs build`; do not push a bare `v<VERSION>-dev` tag while the CurseForge repository webhook is active. The beta workflow tags tested builds as `v<VERSION>-dev-beta.<RUN_NUMBER>`, which keeps the development label and lets CurseForge recognize the Beta channel. The manual-only `Manual development tag check` workflow can inspect an existing development tag without publishing a CurseForge file. If a bare `-dev` file was already published as Release, change its Release Type to Beta in the CurseForge Author Dashboard (Projects > Files > Edit file), or archive it if it should no longer be downloadable.

For the repeatable pre-release, approval, beta, and stable release checklist, see the [Speckit release quickstart](../../specs/019-addon-release-operations/quickstart.md).

## Development beta

1. Push a validated change to `dev`.
2. The beta workflow runs the Fengari suite and reuses the addon package workflow.
3. After both succeed, it tags that exact commit as `v<VERSION>-dev-beta.<RUN_NUMBER>` and pushes the tag.
4. CurseForge's webhook packages the tag as a Beta. The tagged release workflow also creates a prerelease on GitHub.

Examples: `v0.8.11-dev-beta.1` and `v0.8.11-dev-beta.2` are CurseForge Beta files; `v0.8.11` is a CurseForge Release. A failed build or test does not create a tag. A rerun refuses to reuse an existing tag; push a new commit to get a new run number.

Automatic beta and `main` package workflows run only when `src/**` or the root `.pkgmeta` changes. Documentation-only and workflow-only pushes do not create a beta. The package workflow can still be started manually or reused by another workflow.

The GitHub release workflow also accepts `-rc.<N>` tags and marks their GitHub Releases as prereleases. CurseForge's native packager may classify an `rc` tag as a Release unless the CurseForge webhook is configured to exclude or map RC tags. Do not push an RC tag while the webhook publishes every tag unless that behavior has been configured.

The tag workflow uses a GitHub App installation token so the tag push triggers the existing tagged release workflow. Configure repository variable `RELEASE_TAG_APP_ID` and secret `RELEASE_TAG_APP_PRIVATE_KEY`; install that App on this repository with only the **Contents: read and write** permission.

## Stable release

1. Merge validated `dev` into `main` through a pull request.
2. Confirm `src/RCLootCouncil_dibs.toc` has the intended version.
3. Create and push the stable tag explicitly, for example:

   ```sh
   git tag -a v0.8.9 -m "RCLootCouncil_dibs 0.8.9"
   git push origin v0.8.9
   ```

4. The tagged release workflow creates a normal GitHub Release and attaches the package ZIP and checksum. CurseForge's webhook packages the tag as a Release.

A push to `main` that changes `src/**` or the root `.pkgmeta` runs the package artifact workflow; it does not create a stable tag or publish a CurseForge release. CurseForge selects its channel from tag naming, not the Git branch: tags containing `beta` are Beta and plain `v<VERSION>` tags are Release. `rc` tags are GitHub prereleases; their CurseForge behavior depends on webhook configuration.

## CurseForge package layout

The root `.pkgmeta` names the package `RCLootCouncil_dibs` and moves `RCLootCouncil_dibs/src` into `RCLootCouncil_dibs`. In PackageMeta, the source path includes the package directory; the destination is relative to the packager's release directory. Therefore the files under repository `src/` land directly in the package root, including `RCLootCouncil_dibs/RCLootCouncil_dibs.toc`. Repository documentation, scripts, specifications, and tests are excluded.
