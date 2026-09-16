# B12f Release Candidate Checklist

Release candidate: `RCLootCouncil_Dibs 0.6.0`
Date: `2026-09-15`
Starting branch: `dev`
Starting commit (`B12_RELEASE_START_COMMIT`): `224f878800f79c76aa58ef1de6bc36d4d697ba26`

## Release audit

- [x] `git status --short --branch` captured before release edits: clean
  `dev...origin/dev`.
- [x] Existing B12 source changes were already present at the starting commit;
  no unrelated worktree changes were overwritten.
- [x] `git diff --check` passed before and after the release edits.
- [x] Version owners aligned: `src/Core.lua` `Dibs.VERSION` and the TOC are
  both `0.6.0`.

## Automated release gate

- [x] Full Fengari suite: `455 passed, 0 failed (91 files)`.
- [x] B12 module-management suite: `18 passed, 0 failed`.
- [x] Request workflow specs: `12 passed, 0 failed (3 files)`.
- [x] Module-management specs: `18 passed, 0 failed (1 file)`.
- [x] RCLootCouncil integration specs: `71 passed, 0 failed (17 files)`.
- [x] Player/Officer lifecycle and Retail UI specs: `41 passed, 0 failed
  (9 files)`.
- [x] Lua diagnostics: no new diagnostics in touched files. Existing warnings
  remain for dynamic `Dibs.Midnight` and `Dibs.Debug` fields in `OfficerUI.lua`.
- [x] `git diff --check` passed after documentation and metadata changes.

The repository test runner did not provide automatic discovery in this
environment, so the full suite was run with an explicit semicolon-separated
`DIBS_TEST_FILES` list generated from `tests/**/*_spec.lua`. This is an
execution-environment limitation, not a test failure.

## Package review

- [x] Retail Interface is `120100` in the TOC and was reviewed for the target
  Retail package.
- [x] SavedVariables are `RCLootCouncil_dibsDB`,
  `RCLootCouncil_dibsSandboxDB`, and `RCLootCouncil_dibsLocalDB`.
- [x] Required bundled libraries are included through `embeds.xml`.
- [x] The TOC contains addon source and developer-mode runtime surfaces only;
  test files are not loaded by the package.
- [x] No absolute local paths, VS Code workspace paths, temporary screenshots,
  logs, or development secrets were found in the release-facing package scan.
- [x] RCLootCouncil is documented and declared as an optional dependency.

## Manual Retail checks remaining

- [ ] Install the packaged ZIP in a clean Retail AddOns directory and verify the
  TOC loads without Lua errors.
- [ ] Verify the GM governance bootstrap, module toggles, hidden navigation,
  stale-window handling, slash-command fail-closed behavior, and re-enable data
  preservation in a real guild.
- [ ] Verify Player and Officer layout at supported scales and during combat
  lockdown/deferred refresh.
- [ ] Validate RCLootCouncil absent, late-loaded, supported, degraded, and
  unsupported profiles, including balance/max projection and finalized award
  authority.
- [ ] Validate Adventure Guide item selection, loot eligibility, historical
  reconciliation, backups/imports, and restore behavior on Retail.
- [ ] Run the two-client synchronization, coordinator handoff, partition,
  recovery, and exact-sequence checks.
- [ ] Record WoW build, RCLootCouncil version/profile, actor roles, observed
  results, and debug reports/screenshots before publishing.

Retail validation is intentionally not claimed by this checklist. The release
candidate is ready for final Retail validation only after these manual checks
are completed and recorded.
