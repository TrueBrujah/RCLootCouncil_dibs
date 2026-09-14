# B12 Quickstart and Validation

This document validates the B12 design and, after implementation, the release candidate. It does not replace real Retail testing.

## Prerequisites

- Windows PowerShell in the repository root.
- Fengari or the repository-supported Lua test runtime available to `tests/run.lua`.
- Workspace diagnostics available for the changed Markdown and source files.
- A local WoW Retail installation for manual validation.
- Optional RCLootCouncil installation and a way to test it absent, late-loaded, degraded, and operational.
- Developer Mode available for sandbox-only checks, with production SavedVariables kept separate.

## Focused Automated Validation

Run the smallest affected B12 slice first. The exact filenames should match the tests added during implementation. The command shape is:

```powershell
$env:DIBS_TEST_FILES = "tests/unit/<b12-ui-spec>.lua;tests/contract/<b12-release-ui-contract>.lua;tests/integration/<b12-ui-workflow>.lua"
npx --yes fengari tests/run.lua
Remove-Item Env:DIBS_TEST_FILES
```

The focused slice must cover:

- one active page/content owner and pooled-widget cleanup;
- separate Player/Officer window positions and one-time restoration;
- route aliases and display/domain-value normalization;
- shared context-menu opening, replacement, and cleanup;
- request category/status projections without persistence changes;
- request privacy and protected action delegation;
- historical search/review/confirm/reject projection and idempotency;
- absent, late, degraded, and unsupported RCLootCouncil states;
- bounded sandbox behavior and fail-closed provider isolation.

If the repository uses a different Fengari executable name locally, retain the same `DIBS_TEST_FILES` selection and invoke the supported command documented by the test harness.

## Full Automated Validation

Run the explicit full suite through the repository harness after the focused slice:

```powershell
Remove-Item Env:DIBS_TEST_FILES -ErrorAction SilentlyContinue
npx --yes fengari tests/run.lua
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
git diff --check -- specs/012-release-ui-stabilization
```

The full result must include pass/fail counts. If the known unrelated baseline remains at `tests/integration/rclootcouncil_buttons_spec.lua:155` with the historical `2/2` versus `1/1` mismatch, record it as a pre-existing baseline and do not weaken or relabel it as a B12 failure. Any new failure in a touched B12 slice blocks the candidate.

Run workspace diagnostics for every changed Markdown and source file. Markdown-only planning work must not create `tasks.md` or alter Lua/source files.

## Manual Single-Client Retail Matrix

Record a result and evidence note for each scenario:

1. Open Player and Officer windows repeatedly; verify stable positions, no top-edge jumps, no duplicate headers, and correct independent restoration.
2. Navigate every exposed route repeatedly; verify one current page, no stale pooled content, no duplicate routed title, and readable empty/error states.
3. Exercise narrow and wide windows; verify stable table columns, readable labels, and no overlap or clipped critical action.
4. Open, replace, and close context menus from supported rows; verify the previous menu closes and no menu survives page/window close.
5. Display request categories and every existing request state; verify presentation labels do not change persisted state or service semantics.
6. As a player, verify safe disclosure and request actions. As an authorized Officer/GM, verify guarded review actions and confirmation/reason prompts.
7. Exercise Pre-Dibs, Settings, Loot Eligibility, Debug, and RCLootCouncil pages only through their existing services and permission boundaries.
8. Test RCLootCouncil absent, late-loaded, degraded, operational, and unsupported states.
9. Test combat entry for protected/dangerous actions; verify deferral or safe failure according to existing readiness behavior.
10. Run historical search, review, confirm, reject, duplicate, stale, ambiguous, and unknown-field cases without modifying RCLootCouncil history.
11. Test Developer Mode sandbox limits and confirm production data/provider isolation. If `SANDBOX_STORE_TOO_LARGE` remains, verify the documented developer-only conditions and normal-user impact.

Release readiness remains false until this single-client matrix is completed on real Retail.

## Conditional Two-Client Matrix

Run two-client validation only when the B12 implementation changes synchronization, cross-client state propagation, coordinator/recovery behavior, or another cross-client contract. In that case, add evidence for request visibility, historical confirmation propagation, duplicate/idempotent replay, late join/recovery, and authorization on both clients. Otherwise record “not required: no B12 cross-client behavior change.”

## Release Candidate Checks

Before publication:

- Confirm `src/RCLootCouncil_dibs.toc` and its source version owner contain the explicit B12 release version.
- Confirm `CHANGELOG.md` has a dated B12 release-candidate entry.
- Confirm affected player, Officer, and operator documentation is aligned.
- Attach focused and full automated outputs, diagnostics, `git diff --check`, and Retail evidence.
- List the unrelated baseline failure and any accepted developer-only sandbox limitation.
- Verify no `tasks.md` was created by `/speckit.plan`; create it only through the separate task-generation workflow.
- Do not call the build Retail-certified until the real-client evidence is present.
