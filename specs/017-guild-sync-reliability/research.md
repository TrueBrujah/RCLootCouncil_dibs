# Phase 0 Research: Guild Sync Reliability

## Decision 1: Reuse the DIGEST + WHISPER-detail pattern for both new entities

**Decision**: Model `AWARD_PROPOSAL` and `SEASON_CATALOG` using the exact same
shape already implemented for `GOVERNANCE` and `OPERATIONAL_POLICY` in
`SyncV2.lua`: a small `DIGEST` broadcast on `GUILD` carrying only
`{ entityType, entityId, revision, contentHash }`, followed by a `DETAIL_FETCH`
(`WHISPER`) when the receiver's local revision is behind, and a
`TRANSFER_BEGIN`/`TRANSFER_CHUNK`/`TRANSFER_END` sequence carrying the full
payload.

**Rationale**: This pattern is already implemented, already tested
(`tests/integration/b06_distributed_ledger_spec.lua` and friends), already
respects the envelope size/replay bounds (`MAX_BYTES`, `MAX_CHUNKS`,
`MAX_MESSAGES`), and already satisfies Constitution X (idempotent, deduplicatable,
recoverable after reconnect) and XVII (guild-scoped envelopes). Inventing a new
transport shape would duplicate this work and risk missing one of the existing
safety checks (sender verification, guild-key scoping, replay-key dedup).

**Alternatives considered**:
- A dedicated always-on stream per entity — rejected, adds a second transport to
  maintain and test with no behavioral benefit over reusing DIGEST/DETAIL_FETCH.
- Piggy-backing award proposals on the existing `LEDGER_DIGEST`/`AWARD_COMMIT`
  flow directly — rejected because that flow is coordinator-authored only by
  design (Constitution XI); proposals must travel from a non-coordinator *to*
  the coordinator, which is the opposite direction and needs its own entity type
  with different authorization rules (submitter must be a verified guild member,
  not necessarily the coordinator).

## Decision 2: Award proposal delivery target is "the current coordinator", resolved from already-synced Governance state

**Decision**: The submitting officer's client resolves the WHISPER target from
its own local `Dibs.Governance.GetAuthorityState().coordinator.displayName`
(already kept current via the existing `GOVERNANCE` DIGEST sync), not from a
guild-wide broadcast per proposal.

**Rationale**: Governance state (who the coordinator is) is already
synchronized guild-wide today. Reusing it avoids a new "who do I send this to"
discovery mechanism. If the coordinator is unknown/unreachable, the proposal
stays in a local pending queue and is retried on the existing heartbeat cadence
(`Sync.OnLifecycle`/`HEARTBEAT`), matching Constitution X's "recoverable after
clients reconnect" requirement.

**Alternatives considered**:
- Broadcast every proposal to the whole guild and let the coordinator pick it
  up — rejected: unnecessarily exposes award evidence to every guild member
  (not itself a live-loot leak, but unnecessary broadcast) and wastes bounded
  message budget; WHISPER-to-known-coordinator is strictly narrower and cheaper.

## Decision 3: Season catalog authority reuses the existing ProtectedActions authorization, sync only replicates

**Decision**: `Dibs.Sync.AnnounceSeasonCatalog()` is called only *after* a
`season.create`/`season.rename`/`season.archive`/`season.set` ProtectedAction
already succeeded locally (mirroring how `OperationalPolicy` calls
`AnnounceOperationalPolicy` after `Adopt`/`Amend`). Receivers apply the digest
only if the sender resolves to a verified roster member with the same writer
authority rule already enforced by `OperationalPolicy.writerAuthorized`
(GM, or rank within the configured `policyWriterRule`).

**Rationale**: Satisfies Constitution XI (receivers must verify actual sender
and authority, not trust a payload claim) by reusing an already-reviewed
authorization check rather than writing a new one for seasons.

**Alternatives considered**:
- Let any officer's local season list be authoritative and merge by
  last-write-wins — rejected outright by Constitution X.

## Decision 4: Diagnostics use the existing `/dibs debug <scope> 0-5` policy, not Developer Mode

**Decision**: New status signals (policy not adopted, protocol/version
mismatch, pending-proposal counts) are surfaced through: (a) a small,
always-visible status line/banner in Officer UI (not gated on any debug level,
since Constitution XVIII allows normal user-facing errors at level 1), and (b)
detailed traces added to the existing `sync` diagnostic scope
(`Dibs.GetDebugLevels().sync`), consistent with the rest of the module.

**Rationale**: Constitution XVIII requires diagnostics to go through the
Dibs-owned diagnostic policy with named scopes and 0-5 levels, not ad hoc
Developer-Mode-gated output. `/dibs debug report` already prints a `sync`
level field, so hooking into it is the smallest correct change.

**Alternatives considered**:
- Reusing the earlier session's Developer-Mode-only sync trace hook —
  rejected/superseded: it does not satisfy Constitution XVIII on its own for a
  production reliability signal (Developer Mode is off by default for regular
  officers who most need this visibility) and will be migrated onto the `sync`
  diagnostic scope as part of this feature.

## Open questions resolved

- **How is "no coordinator elected yet" handled for proposal relay?** Same as
  today's existing behavior for `Ledger.RecordAwardEvidence`: the proposal is
  recorded locally as `PENDING_RECONCILIATION` and relay is simply deferred
  until a coordinator becomes known via Governance sync; no new state machine.
- **Does this change the single-coordinator model?** No — confirmed against
  Constitution XI and the existing B06 test suite; this feature only adds
  reliable delivery *to* the existing single authority.
