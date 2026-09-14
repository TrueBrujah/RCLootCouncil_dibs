# B12a Runtime UI Stabilization Evidence

## Scope and commits

- Branch: `dev`
- `B12A_START_COMMIT=b24798787892af490126e4f0ec9616fbf45da42d`
- `B12A_RESULT_COMMIT=HEAD (focused B12a result commit)`
- Scope: US1 runtime UI stabilization only. US2-US6, Requests redesign, Historical DIB Transfer redesign, general AceGUI/AceConfig rewrite, and B12f publication work were not started.
- Existing B11 V3 runtime ownership changes in `4193307` remain the production implementation for T013-T018; this B12a increment adds dedicated regression coverage and evidence without changing business authority, persistence, synchronization, or RCLootCouncil behavior.
- Unrelated worktree changes were preserved and excluded: `RCLootCouncil_dibs.code-workspace`, `docs/developer/README.md`, `tests/integration/officer_target_selector_spec.lua`, `docs/audits/B11_Retail_UI_003_Remediation_Evidence.md`, and `tests/integration/b11_retail_ui003_spec.lua`.

## US1 coverage

- T009: ten alternating Player/Officer open-close cycles, separate widget trees, one Officer page root, stale History cleanup, and nonblank repeated refreshes.
- T010: grouped TreeGroup callback normalization, programmatic `requests` alias routing, and canonical Pre-Dib values from visible labels.
- T011: separate Player/Officer position records, one-time restore, valid drag-save, off-screen recovery, and route-refresh isolation.
- T012: reusable context-menu replacement/close, tooltip argument ordering and item-link handling, raw-frame rejection, lib-st ownership/release, and combat refresh deferral.
- T013-T018: existing B11 V3 implementation verified by the focused regressions for permanent content ownership, recursive cleanup, window state, enum normalization, safe tooltip/table ownership, and callback/shell cleanup.

## Automated validation

Focused B12a suites:

```text
10 passed, 0 failed (4 files)
```

B11 UI ownership, navigation, Midnight, and lifecycle regressions:

```text
26 passed, 0 failed (5 files)
```

Full explicit Fengari suite (all `tests/**/*_spec.lua` files):

```text
395 passed, 1 failed (90 files)
```

The sole full-suite failure is the known unrelated baseline:

```text
FAIL RCLootCouncil DIB response projection /
  renders the voting Dibs value from a normalized RCLootCouncil row identity
tests/integration/rclootcouncil_buttons_spec.lua:155: expected 2/2, got 1/1
```

The B12a suites and B11 UI regression slice are green. The plain `npx --yes fengari tests/run.lua` form cannot discover tests in this Windows Fengari environment, so the full result used the repository-supported `DIBS_TEST_FILES` selection path. New B12a test files report no workspace diagnostics, and `git diff --check` passes.

## Retail validation

Automated mocks cannot establish zero live Retail BugSack errors. Manual Retail validation remains required for ten open-close cycles, every exposed Player/Officer route, grouped navigation callbacks, drag and reopen behavior, context-menu replacement/close, tooltip variants, combat deferral, and confirmation that no stale page content remains.

`B12a automated validation complete; manual Retail validation required.`
