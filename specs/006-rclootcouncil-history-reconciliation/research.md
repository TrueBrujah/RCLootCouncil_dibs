# Research: RCLootCouncil History Reconciliation

## Decision 1: Preview before mutation

History is treated as evidence, not as an automatic ledger source. The addon performs no
scan or import on load, reload, login, RCLootCouncil initialization, or history viewing.
An authorized administrator explicitly selects scope and receives a read-only preview
before any candidate can be confirmed.

## Decision 2: Explicit response aliases

The guild configures exact response labels or stable response identities. Matching trims
surrounding whitespace and ignores case, while retaining the original response text as
evidence. Fuzzy matching, guessed translations, and unconfigured labels remain outside
the guided path.

## Decision 3: Strong evidence and manual exception

Guided confirmation requires final status, item, winner, stable award/history identity,
and an explicit alias. Ambiguous or legacy rows may be confirmed only through a separate
manual action that requires an acknowledgement and reason.

## Decision 4: Append-only and idempotent accounting

A confirmed row uses the existing protected award/accounting action. Its stable identity or
explicit evidence link is the deduplication key; repeat confirmation returns the existing
result and never debits twice. Existing transactions are never rewritten.

## Decision 5: Evidence is split by visibility

Officers receive complete source, identity, response, status, timestamps, actor, and reason
fields. Players see only their own concise source and reason. Unknown fields are displayed
as `unknown` or `unavailable`, never inferred.

## Rejected alternatives

- Import every row matching `Dibs`: rejected because labels are configurable and history may
  contain pending, test, or unrelated records.
- Run reconciliation automatically after installation: rejected because a missing or
  changed ledger requires human review.
- Match by player and item alone: rejected because duplicate awards are possible and stable
  identity is required for safe idempotency.
