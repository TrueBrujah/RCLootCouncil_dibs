# Contract: Finalized Award Consumption

`ProtectedActions.FinalizeAward(actor, payload)` consumes at most one Dib per unique finalized award reference.

## Required payload fields

- `awardRef` (stable string)
- `playerName`
- `itemID` (positive integer)
- finalization signal: `finalized=true` or final source status

## Behavior

- Non-final outcomes are no-op (no ledger write).
- Duplicate `awardRef` returns existing transaction without appending another.
- Successful finalize writes one `DIB_USED` transaction and may fulfill matching confirmed Pre-Dib after append.
