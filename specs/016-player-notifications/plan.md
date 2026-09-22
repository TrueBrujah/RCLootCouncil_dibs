# Implementation Plan: Player Notifications

## Architecture

`Dibs.Notifications` is a local presentation service. It resolves a locale key, checks local ownership and enablement, deduplicates by stable event identity, stores a bounded replay map in `SavedVariablesPerCharacter`, and delegates display to `Dibs.Message`.

## Integration Points

- `PreDibs.UpdateStatus`: accepted, cancelled, and resolved notifications.
- `PreDibs.RecordVaultAcquisition`: newly recorded local acquisition notification.
- `ProtectedActions.FinalizeAward`: finalized award and Dib-consumed notifications after a successful non-duplicate result.
- `Core.lua`: local SavedVariables accessor and namespace declaration.

## Safety

No notification path calls a mutating domain API. A rejected operation, duplicate replay, disabled profile, or non-local target produces no user-facing message.
