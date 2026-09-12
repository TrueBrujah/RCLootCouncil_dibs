# P1 Architecture Decision Record

**Status:** Accepted architecture baseline before B00  
**Date:** 2026-09-12  
**Related documents:**
[P1 Remediation Plan](P1_Remediation_Plan.md) and
[P1 Architecture Challenge](P1_Architecture_Challenge.md)

## Context

RCLootCouncil_dibs must reconcile Dibs across simultaneous raids without a
server, reliable delivery, cryptographic client attestation, or safe automatic
leader election. The decision record therefore chooses deterministic canonical
state and explicit recovery over continuous availability during a partition.

The word *authorized* below means attributed sender plus current WoW guild-roster
validation. It does not imply cryptographic proof that a client is unmodified or
truthful.

## ADR-001 — No automatic Dib consumption while coordinator is unavailable

**Decision:** During `COORDINATOR_UNAVAILABLE` or `RECOVERY_PENDING`, no client
creates a canonical ledger transaction, reserves a balance, or consumes a Dib.
It may create an attributable `AWARD_PROPOSAL` with
`PENDING_RECONCILIATION` status. Only an `ACTIVE(E)` coordinator can issue
`AWARD_COMMIT` through the core `CommitDibUse(coordinatorContext, awardEvidence)`
command.

**Why:** A non-coordinator local debit can race a delayed coordinator commit or
a forced takeover and double-spend the same final Dib.

**Consequences:** The Dibs path is visibly unavailable during coordinator loss.
Non-Dib loot distribution may continue. A later GM/officer reconciliation can
accept, reject, or compensate a proposal; it is never auto-converted.

## ADR-002 — Guild Master controls governance changes

**Decision:** Only the current Guild Master, confirmed by fresh guild-roster
data, may adopt or alter governance policy. Governance contains initial policy
adoption, officer authority rules, policy-writer rules, coordinator identity,
ledger epoch, normal handoff, forced recovery, protocol cutover, and canonical
baseline adoption.

Authorized officers may change only the allowlisted operational policy after a
valid governance record exists. Operational changes cannot change governance,
the coordinator, `ledgerEpoch`, protocol state, or baseline.

**Why:** Allowing an officer-rank rule to authorize its own modification makes
policy authority circular and lets stale/local policy become self-authorizing.

**Consequences:** Governance is intentionally unavailable while the GM cannot be
validated. This is safer than an automatic timeout promotion. Governance and
operational records have separate revision chains; normal operational changes do
not increment `ledgerEpoch`.

## ADR-003 — Normal handoff requires predecessor closure and root

**Decision:** A normal transition from `ACTIVE(E)` begins with
`HANDOFF_CLOSING(E)`. The predecessor closure must state previous epoch, final
sequence, and ledger root hash. The GM governance record for `ACTIVE(E+1)` binds
that exact tuple as its parent.

**Why:** The new coordinator needs a fixed, verifiable boundary. Without it, two
coordinators can both believe they are producing the next valid event.

**Consequences:** Receivers reject predecessor events above the declared final
sequence and new-epoch events with a mismatched parent. The old coordinator marks
the epoch closed locally and cannot resume production commits after closure.

## ADR-004 — Forced takeover requires GM-led reconciliation

**Decision:** If predecessor closure cannot be verified, the guild enters
`RECOVERY_PENDING`; it does not immediately activate a new writer. The GM
collects peer evidence, reconciles divergent records, approves a baseline hash,
and publishes a forced-recovery governance record for `ACTIVE(E+1)`.

Late old-epoch records excluded from the approved baseline are stored as
orphaned evidence. They are never appended automatically to the canonical
ledger.

**Why:** A network partition cannot distinguish an old coordinator that is slow
from one that is still committing. Epoch and sequence identify branches but do
not decide which branch should win after an irreversible award.

**Consequences:** Forced recovery may delay Dibs consumption. It produces an
explicit audit trail and preserves all evidence instead of silently dropping or
double-counting it.

## ADR-005 — V2_ENFORCED requires GM cutover and compatible active writers

**Decision:** Protocol states are `LEGACY_LOCAL`, `CUTOVER_PREPARED`, and
`V2_ENFORCED`. Canonical distributed ledger operation is enabled only when the
GM sets `V2_ENFORCED`, the baseline is approved, and all active policy/award
writers advertise the required protocol version/capabilities.

**Why:** Legacy clients can still create local ledger activity that the new
canonical coordinator cannot order safely. Passive coexistence would hide a
second ledger authority.

**Consequences:** A legacy client may remain a player client, but its post-cutover
legacy policy/ledger activity is evidence requiring reconciliation, not a
canonical write. The UI and release notes must name clients that need upgrading
before cutover.

## ADR-006 — The first canonical epoch requires a GM-confirmed legacy baseline

**Decision:** Before the first canonical ledger epoch, the GM explicitly
reconciles available legacy ledger/history evidence. The reconciliation records
include, exclude, and compensating-adjustment decisions, source summary, and a
reproducible `legacyBaselineHash`. The first active epoch binds to that hash.

**Why:** Current clients can have divergent SavedVariables because no canonical
distributed ledger exists. Choosing the first loaded client database would
silently lose or duplicate history.

**Consequences:** All source records remain untouched and exportable. Historical
Pre-Dibs remain historical; an active legacy request requires owner
reconfirmation before entering the new protocol.

## ADR-007 — RCLootCouncil automatic award integration is optional and fail-closed

**Decision:** The core ledger command accepts generic verified `awardEvidence`.
RCLootCouncil is one optional producer of that evidence through a declared,
version-tested adapter capability. Unsupported, absent, degraded, or unknown RC
integration cannot automatically consume a Dib, but it does not disable
Standalone ledger, policy, or reconciliation capabilities.

**Why:** RCLootCouncil internal APIs and UI structures are not a stable authority
contract. Treating them as a core dependency would make ledger correctness rely
on an optional integration.

**Consequences:** Dibs never writes synthetic reservations into RC history.
Existing `dibsOrigin` entries remain display-only legacy data and cannot qualify
as award evidence. Manual, audited evidence can use the core command when the
adapter is unavailable.

## Cross-Decision Invariants

- `policyRevision` and `ledgerEpoch` are distinct. Only governance transition
  changes `ledgerEpoch`.
- Full Name-Realm is the wire identity; events store immutable identity snapshots,
  aliases are GM-reviewed, and GUID is an optional witness only.
- GUILD messages are digest/notification hints; WHISPER details are fetched from
  entity-specific authoritative sources.
- Ledger events apply only at exact `nextSeq` with matching `previousHash`.
  Missing gaps create `SYNC_BEHIND`, which bars coordinator activation and
  canonical consumption.
- SavedVariables migration is additive, backed up, idempotent, and does not
  rewrite legacy ledger/history or RC-owned history.
- Every implementation batch requires recorded `git status`, starting commit,
  checkpoint commit, independent result commit, and non-destructive handling of
  user changes.

## Implementation Mapping

| Decision | First implementation batch | Required before |
|---|---|---|
| ADR-001 unavailable/proposal behavior | B05b | B06 activation and automatic RC consumption |
| ADR-002 governance authority | B02a | B02b, B05a, B05b, B06 |
| ADR-003 normal fenced handoff | B05b | B06 activation |
| ADR-004 forced recovery | B05a then B05b | B06 activation |
| ADR-005 protocol cutover | B04 | B06 activation |
| ADR-006 legacy baseline | B05a | First active canonical epoch |
| ADR-007 optional RC adapter | B09 | Automatic RC award consumption only |

This record is the binding decision baseline for B00 fixtures and all later
implementation-batch acceptance criteria.
