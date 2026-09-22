# Feature Specification: Player Notifications

**Feature Branch**: `016-player-notifications`
**Status**: Implemented pending Retail validation
**Source**: Etape 3 in `docs/PUBLIC-ROADMAP.md`

## Goal

Provide discreet, localized notifications for the local player when an auditable Pre-Dib, award, request, or Great Vault event reaches a relevant state.

## Requirements

- Notifications MUST be local-only and MUST never disclose another player's private event.
- Notifications MUST be localized through the existing locale registry.
- Notifications MUST be disableable per local character/profile without changing guild policy.
- Each notification MUST have a stable event identity and MUST be emitted at most once after reload or replay.
- Notifications MUST use the existing `Dibs.Message` presentation path.
- Notifications MUST NOT mutate Pre-Dibs, ledger, Great Vault, synchronization, or RCLootCouncil state.
- The deduplication store MUST be bounded and use only the existing per-character SavedVariables boundary.
- Missing or unavailable optional integrations MUST not create a notification.

## Covered Events

- Local Pre-Dib accepted or cancelled.
- Local request resolved.
- Local finalized award and Dib consumption.
- Local Great Vault acquisition recorded.

## Acceptance

1. A local event produces one localized message.
2. A replay of the same event identity produces no second message.
3. A reload preserves deduplication state.
4. An event for another player produces no message.
5. Disabling local notifications produces no message without changing domain state.
6. Automated tests pass and Retail certification remains a separate gate.
