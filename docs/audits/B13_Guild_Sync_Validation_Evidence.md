# B13 Guild Sync Validation Evidence

Status: pending two-client Retail execution.

Automated protocol, privacy, recovery, isolation, and conflict evidence is
recorded in [B13_Implementation_Evidence.md](B13_Implementation_Evidence.md).
This document records the live roster and addon-message checks that Fengari
cannot provide.

## Clients and scope

- [ ] Client A and Client B are different characters in the same guild.
- [ ] Both clients have a fresh, visible guild roster.
- [ ] Record addon version, Retail build, guild key context, and weekly reset.
- [ ] Prepare a third context for cross-guild rejection.

## Same-guild convergence

- [ ] Record or confirm one acquisition on Client A.
- [ ] Confirm Client B receives a bounded digest and requests missing detail.
- [ ] Confirm Client B stores one matching acquisition and eligibility projection.
- [ ] Replay digest and detail; confirm an idempotent acknowledgement and no
      duplicate record or eligibility effect.
- [ ] Disconnect Client B, create one additional record on Client A, reconnect B,
      and confirm bounded recovery.

## Rejection and privacy

- [ ] Cross-guild detail is rejected without mutation.
- [ ] A non-authorized sender cannot apply protected Vault detail.
- [ ] Private Officer evidence is not visible in a player projection or wire
      payload.
- [ ] Live candidates, votes, responses, and loot-session fields are rejected.
- [ ] A stale or conflicting identity becomes reviewable rather than last-write-
      wins replacement.
- [ ] An incomplete transfer expires without creating a partial acquisition.

## Ownership and migration

- [ ] Changing guild does not expose the old guild's Vault history.
- [ ] An unguilded character sees only its own migrated and newly recorded data.
- [ ] Full-data import repeated twice remains deduplicated and preserves review
      decisions.
- [ ] A migration preview does not create a ledger transaction.

## Evidence

- Client A:
- Client B:
- Guild/build:
- Digest/fetch/detail/ack observations:
- Reconnect/recovery observations:
- Rejection observations:
- Screenshots or chat logs:
- Notes:
