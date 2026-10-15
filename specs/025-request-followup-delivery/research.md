# Research decisions

- **Decision**: Reuse SyncV2 private chunk transfers and capability negotiation.
  **Rationale**: Existing sender/guild/online resolution and developer guards;
  no second transport. **Alternative**: Guild ticket broadcast rejected for privacy.
- **Decision**: Coordinator-only delivered mutations, epoch-pinned dossiers.
  **Rationale**: Isolated optimistic replicas cannot prevent double compensation.
  **Alternative**: Multi-writer last-write-wins rejected; handoff without proof blocked.
- **Decision**: Explicit capacity rejection (500 dossiers, 120 audit events).
  **Rationale**: Preserve complete retained evidence without unbounded growth.
  **Alternative**: Existing terminal pruning/audit truncation rejected.
- **Decision**: Per-character reminder/outbox state, 60-second retry/heartbeat,
  at most four sends per pump and 128 pending operations.
  **Rationale**: Bounded online work; disabled or offline clients cannot notify.
- **Decision**: Reuse existing detail forms and queue dropdowns.
  **Rationale**: Midnight design and existing confirmed reconciliation remain intact.
- Extension hooks absent at specification/planning time. No external research or
  delegated agents required; decisions grounded in repository contracts.
- **Decision**: Add a production-module client/reload fixture instead of asserting
  delivery using `distributed_ledger_fixture.lua` alone. **Rationale**: That file
  explicitly models B00 architecture contracts without loading addon code; it
  cannot prove the new runtime transport or persistent outbox. The new fixture
  runs actual Disputes/RequestDelivery/SyncV2 with isolated SavedVariables,
  synthetic current rosters, controlled authority epochs and bounded wire frames.
- **Decision**: Preserve legacy local-only review, but stop initial sharing when
  a dossier was already changed before coordinator binding. **Rationale**: Never
  submit an incomplete or already-compensated local dossier as a fresh shared one.
- **Decision**: Bound replication fanout to owner plus 16 online capable officer
  peers, catching up eight dossiers per pump. **Rationale**: Bounded online work;
  this is not a claim of unlimited all-officer replication.
- **Decision**: Due reminders use a persisted three-per-minute batch budget and
  rotating request cursor in addition to the one-per-request/hour limit.
  **Rationale**: Prevent login/reload bursts without starving later due dossiers.
