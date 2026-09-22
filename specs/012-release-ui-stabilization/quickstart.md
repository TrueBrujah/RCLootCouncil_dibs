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

Run the smallest affected B12 slice first. The current B12 manifest is:

```powershell
$env:DIBS_TEST_FILES = "tests/unit/b12_ui_projection_spec.lua;tests/unit/b12_historical_candidate_projection_spec.lua;tests/integration/b12_page_cleanup_spec.lua;tests/contract/b12_page_cleanup_contract_spec.lua;tests/integration/b12_responsive_ui_spec.lua;tests/contract/b12_release_ui_contract_spec.lua;tests/contract/b12_release_candidate_spec.lua;tests/integration/b12_requests_support_ticket_spec.lua;tests/contract/b12_requests_actions_spec.lua;tests/integration/b12_requests_context_menu_spec.lua;tests/integration/b12_requests_primary_actions_spec.lua;tests/contract/b12_advanced_request_actions_spec.lua;tests/contract/b12_request_disclosure_spec.lua;tests/integration/b12_historical_transfer_spec.lua;tests/contract/b12_historical_transfer_actions_spec.lua;tests/integration/b11_request_eligibility_ui_spec.lua;tests/integration/b11_responsive_ui_spec.lua"
$focusedExit = 0
npx.cmd --yes fengari tests/run.lua
$focusedExit = $LASTEXITCODE
Remove-Item Env:DIBS_TEST_FILES -ErrorAction SilentlyContinue
if ($focusedExit -ne 0) { exit $focusedExit }
```

The current focused result is `56 passed, 0 failed (17 files)`. Record the
actual pass/fail count when B12 tests are added, and report any failure by file
before changing the implementation. A non-zero command exit blocks the next
validation stage.

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

Run the explicit full suite through the repository harness after the focused slice.
The runner requires `DIBS_TEST_FILES`; exclude only `tests/run.lua` while keeping
helpers in the manifest so the reported file count remains traceable:

```powershell
$root = (Get-Location).Path
$env:DIBS_TEST_FILES = (Get-ChildItem -Path tests -Recurse -Filter *.lua |
	Where-Object { $_.Name -ne "run.lua" } |
	ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace("\", "/") }) -join ";"
$fullExit = 0
npx.cmd --yes fengari tests/run.lua
$fullExit = $LASTEXITCODE
Remove-Item Env:DIBS_TEST_FILES -ErrorAction SilentlyContinue
if ($fullExit -ne 0) { exit $fullExit }
```

The full result must include pass/fail counts. The current repository result is
`542 passed, 0 failed (129 files)`. If the known unrelated baseline appears at
`tests/integration/rclootcouncil_buttons_spec.lua:155` with the historical
`expected 2/2, got 1/1` mismatch, record it separately as pre-existing; do not
weaken the assertion or relabel it as a B12 failure. Any new failure in a
touched B12 slice blocks the candidate.

Run workspace diagnostics for every changed Markdown, Lua, and test file in the
VS Code Problems view (or the workspace diagnostics command). Then run the
whitespace check for the complete changed surface:

```powershell
git diff --check -- specs/012-release-ui-stabilization src tests docs
```

Markdown-only planning work must not create `tasks.md` or alter Lua/source
files.

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

Before publication, complete every item below:

- [ ] Install the candidate ZIP into a clean AddOns directory and confirm the TOC, folder name, and SavedVariables declarations.
- [ ] Open the supported Player routes: Overview, Requests, Pre-Dibs, History, Settings, Loot Eligibility, and Debug where exposed.
- [ ] Open the supported Officer/GM routes: Dashboard, Requests, Pre-Dibs, History, Seasons, Rank Rules, Loot Rules, Announcements, RCLootCouncil, Settings, Diagnostics, Loot Eligibility, Developer, and Debug where permitted.
- [ ] Confirm `src/RCLootCouncil_dibs.toc` and its source version owner contain the explicit B12 release version.
- [ ] Confirm `CHANGELOG.md` has a dated B12 release-candidate entry.
- [ ] Confirm affected Player, Officer, operator, and developer-only documentation is aligned.
- [ ] Attach the focused and full automated outputs from `docs/audits/B12_Release_UI_Hardening_Evidence.md`.
- [ ] Attach the dated real-client result from `docs/audits/B12_Retail_Validation_Evidence.md`.
- [ ] Record the conditional two-client decision and link the applicable evidence.
- [ ] List the unrelated baseline failure and the accepted developer-only `SANDBOX_STORE_TOO_LARGE` limitation.
- [ ] Verify no `tasks.md` was created by `/speckit.plan`; create it only through the separate task-generation workflow.
- [ ] Keep readiness false while any required Retail evidence, diagnostics, or package check is incomplete.

The candidate is not Retail-certified or publishable until the real-client evidence
record is complete and every required gate is explicitly checked.
