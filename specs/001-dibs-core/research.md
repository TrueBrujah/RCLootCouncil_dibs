# Research: Independent Dibs Core

## Decision 1: Ledger Is the Only Authoritative Balance Source

- Decision: Remaining Dib balance is always derived from authoritative transaction history for the selected season.
- Rationale: This enforces auditability and prevents silent divergence between displayed balance and historical accounting.
- Alternatives considered:
  - Storing mutable precomputed balances as authority: rejected because it can drift from history and weakens audit guarantees.
  - Recomputing from mixed UI state and transactions: rejected because UI state is non-authoritative.

## Decision 2: Compensating Corrections Instead of Mutation

- Decision: Errors are corrected only with new compensating transactions (refund/revoke/admin adjustment), never by deleting or rewriting existing rows.
- Rationale: Preserves immutable history and aligns with constitution audit requirements.
- Alternatives considered:
  - In-place editing of mistaken transactions: rejected because it erases historical truth.
  - Hard deletion of rows: rejected because it breaks traceability.

## Decision 3: Idempotency Keyed by Transaction Identifier

- Decision: Each authoritative transaction must carry a unique transaction identifier; repeats of an already-applied identifier are treated as no-op for accounting effect.
- Rationale: Enables safe replay and duplicate delivery tolerance.
- Alternatives considered:
  - Timestamp-only deduplication: rejected because collisions and ambiguous retries are possible.
  - Content-hash-only deduplication: rejected because semantically distinct events can share partial payload overlap.

## Decision 4: Rank Allocation Is Configuration Data

- Decision: Per-rank Dib allocations are season-scoped configuration values managed by authorized actors.
- Rationale: Prevents hard-coded policy and supports guild-specific governance.
- Alternatives considered:
  - Static rank allocation table embedded in code: rejected due to constitution violation.
  - Single allocation for all ranks: rejected because it fails requirement for rank differentiation.

## Decision 5: Rank Snapshot Preserved Per Transaction

- Decision: Every authoritative transaction stores guild rank at transaction time, and later rank changes affect only future transactions.
- Rationale: Maintains historical integrity while allowing operational rank updates.
- Alternatives considered:
  - Dynamic rank lookup when reading history: rejected because historical rows would change interpretation over time.
  - Bulk restatement after promotion/demotion: rejected because this rewrites past context.

## Decision 6: Role Foundation Is Explicit and Extensible

- Decision: Core permission context supports Player, Officer, and GM roles. Legacy configurable Dibs Administrator appointments remain auditable but do not authorize a non-GM/non-Officer; the core remains independent from external loot-role authority.
- Rationale: Establishes stable governance primitives for later integration features.
- Alternatives considered:
  - Permission checks only in UI layer: rejected because authoritative acceptance must enforce role checks.
  - Deferring all role logic to future features: rejected because core needs safe mutation boundaries now.

## Decision 7: Core Feature Boundary Excludes RC/EJ/Sync Runtime Coupling

- Decision: Dibs Core interfaces and data ownership are independent of RCLootCouncil, Encounter Journal, loot-session runtime data, and cross-raid synchronization.
- Rationale: Preserves modular architecture and allows future adapters without polluting core invariants.
- Alternatives considered:
  - Embedding RC-specific status in core entities: rejected because core would no longer be standalone.
  - Designing core around network sync payloads first: rejected because sync is a later dedicated feature.
