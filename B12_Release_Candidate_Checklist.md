# v0.8.0 Release Checklist

Release candidate: `RCLootCouncil_Dibs 0.8.0`
Date: `2026-09-29`
Branch: `dev`
Candidate base commit: `f294e70` (`origin/dev` before final candidate fixes)

## Release audit

- [x] `src/Core.lua` and the TOC both declare `0.8.0`.
- [x] `CHANGELOG.md` has a `0.8.0` entry dated `2026-09-26`.
- [x] No local or remote `v0.8.x` tag exists; `v0.8.0` is available for this
  candidate if it has not been published outside this repository.
- [x] Candidate work started from synchronized `dev`; `main` remains unchanged.
- [x] `git diff --check` passes for the candidate changes.

## Automated release gate

- [x] Full Fengari suite: `824 passed, 0 failed (144 files)`.
- [x] Focused Cosmetic/Loot Rules and RCLootCouncil button suites:
  `73 passed, 0 failed (4 files)`.
- [x] B11 Retail UI-003 suite: `9 passed, 0 failed (1 file)`.
- [x] The channel-probe UI preserves and displays the probe ID returned by
  `Sync.StartChannelTest`.
- [x] No actionable Pylance errors remain in `RCLootCouncil.lua` or the changed
  channel-probe code. Pylance still reports the repository's custom `@doc.*`
  annotations in `OfficerUI.lua` as unknown.

The test runner was invoked with an explicit semicolon-separated
`DIBS_TEST_FILES` list generated from `tests/**/*_spec.lua`.

## Package review

- [x] Build and inspect the release ZIP for Retail Interface `120100`, the
  expected SavedVariables, required embedded libraries, and absence of tests,
  local paths, temporary files, or development secrets.
- [x] Install the ZIP in a clean Retail AddOns directory and verify the TOC
  loads without Lua errors.
- [x] Confirm RCLootCouncil remains an optional dependency in the packaged TOC.

The operator reports that the package and Retail checks below passed on
`2026-09-29`, except for the historical-confirmation positive path called out
explicitly below.

## Manual Retail checks

- [x] Verify the GM governance bootstrap, module toggles, hidden navigation,
  stale-window handling, slash-command fail-closed behavior, and re-enable data
  preservation in a real guild.
- [x] Verify Player and Officer layout at supported scales and during combat
  lockdown/deferred refresh.
- [x] Validate RCLootCouncil absent, late-loaded, supported, degraded, and
  unsupported profiles, including balance/max projection and finalized award
  authority.
- [x] Validate Adventure Guide item selection, loot eligibility, historical
  reconciliation, backups/imports, and restore behavior on Retail.
- [ ] Verify historical confirmation with a current guild member after refreshing
  the roster. Deferred until the next raid: the operator is not GM and cannot
  exercise this positive path beforehand. `UNKNOWN_ROSTER_MEMBER` for a
  non-member is expected fail-closed behavior, not a release defect. The release
  owner accepts this one validation exception; the positive path is not claimed
  as tested.
- [x] Run the two-client synchronization, coordinator handoff, partition,
  recovery, and exact-sequence checks.
- [x] Record local environment metadata: WoW `12.1.0.69933`, RCLootCouncil
  `3.23.3`, operator role non-GM. Detailed screenshots/debug reports were not
  added to this repository.

Release decision: all other checks are reported passed by the operator. The sole
deferred check is documented above and accepted for `v0.8.0`; do not describe it
as a successful in-guild historical confirmation.
