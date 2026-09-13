# B08 Implementation Evidence

## Scope and commits

- Branch: `dev`
- `B08_START_COMMIT=fa9b143901849aed116922e7dc07b7c18e4b0591`
- `B08_CHECKPOINT_COMMIT=fa9b143901849aed116922e7dc07b7c18e4b0591`
- `B08_RESULT_COMMIT=4c5931fe0e8b984402afc55139b4503bf327c49b`

Unrelated user changes to `docs/RC_OPTIONS.md` and
`RCLootCouncil_dibs.code-workspace` were preserved and are not part of B08.

## Files in B08

- `src/integrations/RCLootCouncil.lua`
- `src/Core.lua`
- `tests/helpers/wow_api.lua`
- `tests/integration/b08_rclootcouncil_ui_safety_spec.lua`
- `docs/audits/B08_Retail_Validation_Checklist.md`

## Ownership and combat boundary

RCLootCouncil entries, their native response buttons, their layout, and their
click handlers are RC-owned. B08 no longer adopts a discovered RC DIB button,
does not replace its `OnClick`, does not disable/enable it, and does not
reposition RC buttons.

Dibs-created loot and voting-cell buttons are Dibs-owned. Only those controls
receive Dibs `OnClick` handlers and Dibs points. Dibs tooltips use `HookScript`
only when the surface supports it; Dibs does not fall back to replacing an
RC-owned tooltip script.

`Dibs.RCLootCouncil.uiProjection` is a small runtime-only scheduler. Unsafe
loot and voting projection operations check `InCombatLockdown`, coalesce work
by `loot`/`voting` surface, and retain no stale visual snapshots. Creating a
Dibs button, installing the loot hook, adding/refreshing voting columns, and
creating the Dibs voting-cell control are deferred in combat. `PLAYER_REGEN_ENABLED`
calls `OnCombatEnded`, which flushes each dirty surface once using current state.
If combat is still active, work remains pending.

The scheduler is part of the existing optional RCLootCouncil capability: an
initializer failure remains isolated by B07, while core Dibs continues.

## Non-authoritative protection

UI refresh requests do not create ledger transactions or alter governance,
policy, SyncV2, canonical sequence/root, `AWARD_COMMIT`, `AWARD_PROPOSAL`, or
RCLootCouncil history. B08 introduces no award adapter, status mapping, or
automatic award consumption; B09 and B10 are not implemented.

## Static mutation classification

The remaining RCLootCouncil `SetPoint` calls are exclusively on Dibs-created
loot and voting-cell buttons, both guarded by the scheduler. No B08-scoped
`SetScript("OnClick")` replacement is applied to a discovered RC-owned control.
RC-owned buttons are neither repositioned nor enabled/disabled by Dibs.

## Validation

Focused B08 tests: **3 passed, 0 failed**. They cover native RC click-handler
preservation, Dibs-only handler ownership, combat deferral, independent
surface coalescing, post-combat flush/idempotency, and no ledger mutation.

Targeted RC UI/combat/B07/B06 tests: **39 passed, 1 failed**, where the sole
failure exactly matches the established baseline:

```text
FAIL RCLootCouncil DIB response projection /
  renders the voting Dibs value from a normalized RCLootCouncil row identity
tests/integration/rclootcouncil_buttons_spec.lua:155: expected 2/2, got 1/1
```

Full suite: **307 passed, 1 failed (65 files)** with the same exact unrelated
baseline failure and no B08 regression.

## Retail validation

`RETAIL_RUNTIME_VALIDATION = PENDING_B10_RELEASE_GATE`.

The required live-client matrix is in
`docs/audits/B08_Retail_Validation_Checklist.md`. Automated tests validate
guards and scheduling, not real-client taint/forbidden-action behavior.

## Known limitations

The projection intentionally retains stale visuals in combat. Runtime tests
cannot establish that taint is impossible; the Retail checklist remains a B10
release gate.
