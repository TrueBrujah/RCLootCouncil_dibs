# Contract: Local Candidate Status

`RCLootCouncil.GetStatusForCandidate(playerName, itemID)` returns local read-only Dibs projection.

## Projection fields

- `balance`
- `hasDibs`
- `hasPreDib`
- `canUseDib`
- `status`

## Rules

- Projection is derived only from Dibs ledger + Pre-Dibs state.
- Pre-Dib priority can mark non-pre-dib candidates ineligible for DIB response.
- Projection data is local and must not be synchronized cross-raid.
