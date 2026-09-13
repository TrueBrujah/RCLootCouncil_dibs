# B08 Retail Validation Checklist

`RETAIL_RUNTIME_VALIDATION = PENDING_B10_RELEASE_GATE`

This checklist has not been executed in a live Retail client. Automated tests
cover guards, coalescing, ownership, and idempotency only; they cannot prove
the absence of real-client taint or forbidden-action errors.

## Out of combat

- Open the RCLootCouncil loot and voting UIs.
- Confirm original RCLootCouncil controls retain their normal click behavior.
- Confirm a Dibs-owned projection/button appears at most once and works as a
  projection/request control only.
- Confirm no Lua error appears and no Dibs action writes RCLootCouncil history.

## Combat and recovery

- Open RCLootCouncil UI, enter combat, and trigger a loot/voting refresh.
- Confirm no forbidden-action error and no RC control is moved, enabled,
  disabled, hidden, or script-replaced by Dibs during combat.
- Leave combat and confirm exactly one coalesced Dibs refresh applies the latest
  state without duplicate controls.
- Re-enter combat before a pending refresh can apply and confirm it remains
  deferred.

## Late loading and reload

- Load Dibs first, then RCLootCouncil outside combat; confirm the B07 optional
  capability becomes available and the projection initializes once.
- Repeat late RCLootCouncil load during combat; confirm projection mutation is
  deferred until leaving combat.
- Reload UI out of combat and around combat transitions; confirm no duplicate
  hooks, buttons, columns, or event handlers.

## Taint and error monitoring

- Capture Lua errors and forbidden-action messages during each scenario.
- Enable the guild's normal taint logging procedure when available.
- Attribute any issue to the exact Dibs/RCLootCouncil frame, action, combat
  state, and addon versions; do not infer causality from a generic taint log.
