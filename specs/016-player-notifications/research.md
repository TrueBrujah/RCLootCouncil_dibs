# Research: Player Notifications

## Existing Authorities

- `Dibs.PreDibs.UpdateStatus` owns request lifecycle transitions.
- `Dibs.PreDibs.RecordVaultAcquisition` owns Vault acquisition creation and idempotent replay handling.
- `Dibs.ProtectedActions.FinalizeAward` is the protected award and ledger-consumption boundary.
- `Dibs.Message` is the existing local chat/status presentation path.
- `RCLootCouncil_dibsLocalDB` is declared as `SavedVariablesPerCharacter` and is appropriate for bounded local preference and replay state.

## Decisions

- Use a transient service with a bounded per-character `seen` map rather than a new guild-scoped schema.
- Filter by `targetPlayer` or `playerName` against `Dibs.GetPlayerName()` before recording an event.
- Notify only after the authoritative domain operation succeeds.
- Do not infer events from UI refreshes, sync payloads, or debug output.

## External Boundary

Real Retail verification is required for chat visibility, localization selection, reload persistence, and protected-frame/combat behavior. Fengari tests prove contract behavior only.
