# Research: Officer Audit and Dispute Center

## Decision 1: Reports are appeals, not commands

The player action creates a non-authoritative request. It never changes a balance, policy,
RCLootCouncil state, or live vote. Evidence is attached automatically where available so
the player does not have to copy technical identifiers.

## Decision 2: One queue with three common actions

The Officer view prioritizes **Correct balance**, **No correction**, and **Ask for
information**. Duplicate and advanced refund/revoke/import/adjustment actions remain
explicitly grouped and explain their accounting effect.

## Decision 3: Append-only corrections and concurrency safety

The original transaction remains immutable. A correction is a linked compensating transaction
created through protected actions, with request/evidence references, actor, reason, and time.
Request state and transaction idempotency prevent a second correction after replay or a
concurrent Officer decision.

## Decision 4: Progressive privacy

Players see only their requests, safe evidence summary, status, questions, replies, and
resolution explanation. Officers see complete queue/evidence and notes. Neither view changes
RCLootCouncil's award authority or exposes unrelated candidates/votes.

## Decision 5: Safe user text and optional integrations

Notes, replies, and explanations are bounded and rendered as inert text. Missing RCLootCouncil,
reconciliation, readiness, Curio, Tier Set, or main/alt evidence is shown as unavailable; the
basic Dibs accounting review remains usable.

## Rejected alternatives

- Allow players to edit their own ledger: rejected because reports are not authoritative.
- Put refund/import/adjustment beside routine actions: rejected because advanced actions have
  larger accounting effects and need deliberate confirmation.
- Show the full queue to all guild members: rejected because evidence and administrator notes
  are private.
