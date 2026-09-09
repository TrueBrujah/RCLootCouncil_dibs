# Research: Raid Readiness and Dry-Run Center

## Decision 1: Separate standalone and live integration readiness

Guild administration, seasons, policy, and local UI can be Ready while a missing group,
channel, or RCLootCouncil capability is Unavailable/Degraded. This prevents an optional
integration problem from revoking valid Dibs administration.

## Decision 2: Readiness is fresh evidence, not authority by itself

The panel carries a timestamp and configuration fingerprint. Reload, profile/season/policy,
roster, lifecycle, and freshness changes invalidate it. The live finalized-award callback
revalidates current conditions before accounting.

## Decision 3: Dry-run reuses decisions but never side effects

The dry-run calls pure validation/classification helpers with a synthetic context. It does
not call RCLootCouncil award controls, inject global events, send addon/raid traffic, write
SavedVariables, or create idempotency records. `RCMLAwardSuccess` and `FinalizeAward` may be
shown as evidence references only.

## Decision 4: Safe reports are the default

Copied reports include versions, mode, statuses, reason codes, and dry-run outcome. They
omit candidates, votes, complete balances, private notes, item payloads, and unrelated
identities. Detailed evidence stays in the Officer scope.

## Decision 5: Status classes explain impact

`Ready` permits the existing qualifying award path; `Degraded` identifies optional or
recoverable limitations; `Blocked` prevents unverifiable production consumption;
`Unavailable` describes expected missing context such as no group or absent integration.

## Rejected alternatives

- Fire a fake `RCMLAwardSuccess` event for testing: rejected because it can trigger side
  effects in RCLootCouncil or other addons.
- Let a recent Ready panel authorize an award: rejected because ML, response, status, or
  identity can change after the check.
- Treat no raid channel as a security failure: rejected because standalone/local testing
  remains valid.
