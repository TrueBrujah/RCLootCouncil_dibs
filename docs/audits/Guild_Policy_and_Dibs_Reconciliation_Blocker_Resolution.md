# Guild Policy and Dibs Reconciliation Blocker Resolution

Status: Read-only architecture decision. No production code, tests, or
SavedVariables were modified.

## 1. Executive Decision

Resolve the three blockers as follows:

1. **Negative delta: no negative reconciliation and no negative
   retroactivity.** A seasonal rank allocation is an initial earned allocation
   with manually approved positive top-ups. A demotion changes the next
   season's expected allocation; it does not revoke an allocation already
   granted in the current season.
2. **Canonical audit: store the decision basis with the canonical ledger
   transaction.** The transaction records who requested and committed the
   change, the target, positive delta, before-allocation, expected allocation,
   current rank observation, required reason, season/catalog revision, policy
   and governance revisions, and proposal link when relayed. Derived values
   stay derived; no parallel audit database is introduced.
3. **Coordinator relay: reuse `AWARD_PROPOSAL` -> `AWARD_COMMIT`.** A
   non-coordinator's explicit action becomes one immutable proposal with
   compare-and-set preconditions. The current coordinator revalidates those
   preconditions and commits through the existing Ledger. The requester's
   `PENDING_RECONCILIATION` state becomes `COMMITTED` only after the matching
   canonical commit is applied. Stale and permanently rejected proposals
   become terminal and are returned to the requester.

No reconciliation mode may automatically mutate the ledger. Guild Policy may
allow `MANUAL` and `RECOMMEND_ONLY`; `AUTO_POSITIVE` is not enabled, and
`AUTO_ALL` is not a valid mode. The current code already supports positive
season allocations; the audit and proposal contracts below are required
implementation work, not unresolved domain choices.

**Final decision: READY FOR IMPLEMENTATION**, subject to the invariants and
compatibility gates in this document.

Evidence reviewed: [Ledger](../../src/modules/Ledger.lua),
[ProtectedActions](../../src/modules/ProtectedActions.lua),
[RankRules](../../src/modules/RankRules.lua), [Governance](../../src/modules/Governance.lua),
[SyncV2](../../src/modules/SyncV2.lua), [award proposal relay tests](../../tests/integration/award_proposal_relay_spec.lua),
and the prior [architecture audit](Guild_Policy_and_Dibs_Reconciliation_Architecture.md).

## 2. Current Ledger Semantics

- `SEASON_ALLOCATION` accepts positive integers only. Applying one increases
  `playerStates[seasonId][memberKey].allocation`; that allocation contributes
  to `Ledger.GetBalance`.
- Spendable balance is not assigned allocation. It is the assigned/base
  allocation plus non-`SEASON_ALLOCATION` transaction deltas. `DIB_USED`,
  `DIB_REFUNDED`, and `DIB_ADMIN_ADJUSTMENT` affect spendable balance; a
  refund does not rewrite assigned allocation.
- Normal `DIB_USED` commits reject a negative resulting balance unless an
  explicit debt policy is supplied. `DIB_ADMIN_ADJUSTMENT` is signed and
  current adjustment paths can produce a negative computed balance;
  `GetBalance` does not clamp it. One old manual path explicitly supplies
  `allowDebt=true`.
- Consequently, a negative `ledger.adjust` is a balance correction, not an
  allocation correction. `rank.reconcile` currently calls
  `RegisterSeasonAllocation`, which rejects zero/negative amounts.
- The season rank rule is a target for starting allocation. The old
  “Reconcile missing Dibs” operation only grants positive shortfalls. There
  is no supported negative allocation event and no automatic rank-change
  ledger writer.

### Explicit Answers

| Question | Decision |
|---|---|
| Q1. Can balances currently be negative? | Yes. Authorized signed admin adjustments can make the computed balance negative; normal spending is separately guarded unless debt is explicitly allowed. |
| Q2. Should balances ever be negative? | Not as a normal player balance and never as a side effect of rank reconciliation. This decision does not remove the existing separately authorized admin-debt/correction capability. |
| Q3. Is assigned allocation equivalent to spendable balance? | No. Allocation is one Ledger component; spendable balance is that component plus later grants, uses, refunds, and adjustments. |
| Q4. Is rank allocation an entitlement or an initialization event? | It is a seasonal starting-allocation event, with explicitly approved positive top-ups when current expected allocation exceeds assigned. It is not a continuously revocable entitlement. |
| Q5. Should rank promotion grant missing Dibs immediately? | It may grant a positive top-up only after an explicit GM/Officer action and coordinator validation. It is never automatic. |
| Q6. Should rank demotion remove already-granted Dibs? | No. Current-season allocation remains earned; the lower rule applies to the next season's starting allocation. |
| Q7. Should negative reconciliation ever be automatic? | No. Under the selected semantics negative reconciliation is not an operation. A separate correction for an erroneous ledger grant remains a reviewed admin correction, not a rank-demotion rule. |
| Q8. What if the player already spent the extra Dib? | Nothing is debited or clawed back. The spend remains valid, no debt is created, and the demotion only affects future-season allocation. |

## 3. Negative Delta Models Compared

For comparison, the example is a current-season allocation of 2, a new rank
expectation of 1, and a computed difference of -1. The dimensions below include
fairness, current Ledger fit, spending/refunds, seasons and rank changes,
guild-admin/accidental changes, abuse/reversibility/audit, SavedVariables, and
existing-player effects.

### A. BALANCE CORRECTION

- **Fairness / rank changes:** Treats a guild demotion as a financial debit.
  Guild-admin and accidental rank changes can punish a player for an event
  outside the player's control; a promotion/demotion pair is not symmetric if
  the granted Dib was already spent.
- **Current ledger / spending / refunds:** `ledger.adjust` can subtract from
  spendable balance, but does not lower the assigned allocation projection.
  If the Dib was spent, the correction can create debt. A later refund adds
  balance but does not restore rank allocation metadata.
- **Season behavior:** A debit can affect spendable balance after the season
  transition if the Ledger's season/state policy allows, while the allocation
  event remains recorded as +2. That is not a coherent season-allocation
  correction.
- **Administration / accidents:** An Officer/GM can correct an erroneous
  grant through the existing manual adjustment route, but rank change alone is
  not evidence that the original grant was erroneous. Accidental rank changes
  are especially harmful under automatic debit.
- **Abuse / reversibility / audit:** Could be abused as a punitive debit. A
  compensating positive adjustment is possible but creates more balance
  history and does not restore the original allocation semantics. Audit can
  show the debit, but cannot make it fair.
- **Compatibility / impact:** Existing `DIB_ADMIN_ADJUSTMENT` records already
  express signed balance changes, so no SavedVariables migration is needed;
  however, existing players would lose earned/spent Dibs. **Rejected.**

### B. ALLOCATION CORRECTION ONLY

- **Fairness / rank changes:** Could stop future allocation growth without
  clawing back previously earned spendable Dibs. This is fairer than A if
  “earned” is separately modeled.
- **Current ledger / spending / refunds:** Not representable as a metadata-only
  change today. `state.allocation` is directly included in spendable balance;
  lowering it changes the balance. A separate vested/earned component or
  allocation projection would be needed. Refunds currently affect balance,
  not allocation.
- **Season behavior:** Needs a new per-season distinction between current
  rank expectation, assigned starting allocation, and any protected earned
  amount. Without that, a UI label change would hide a balance mutation.
- **Administration / accidents:** Could handle rank changes consistently only
  after defining which guild rank snapshot is authoritative and whether a
  later rank restoration reopens the entitlement.
- **Abuse / reversibility / audit:** Reversible as metadata only if a complete
  event history is retained; otherwise changes become last-write-wins. It
  requires a new canonical projection and audit schema.
- **Compatibility / impact:** Existing `SEASON_ALLOCATION` records do not
  distinguish vested allocation. Existing players cannot be safely migrated
  to a new decomposition by inference. **Rejected for this release.**

### C. FLOOR-AT-ZERO / PARTIAL CORRECTION

- **Fairness / rank changes:** Players with the same rank change receive
  different results depending on how much they spent. One player may be
  debited while another with zero available balance is not.
- **Current ledger / spending / refunds:** Could clamp a balance debit to the
  current available amount, but would still be a `ledger.adjust`, not an
  allocation correction. If applied to allocation, current allocation and
  spendable balance remain coupled. Refund timing could make a previously
  uncollectable portion collectible later unless additional state is added.
- **Season behavior:** A partial debit can persist past the season and leaves
  no principled answer about whether the remaining expected/assigned
  difference is still actionable.
- **Administration / accidents:** A mistaken demotion can cause an
  irreversible partial loss before the roster is corrected.
- **Abuse / reversibility / audit:** Spending before a demotion changes the
  amount collected, so spending behavior can game the correction. Reversal
  requires a separately reasoned grant and cannot reconstruct the intended
  allocation from the partial debit alone.
- **Compatibility / impact:** Existing transaction types could record the
  balance part, but allocation semantics still need new data; affected players
  get inconsistent partial clawbacks. **Rejected.**

### D. DEBT MODEL

- **Fairness / rank changes:** Makes a downgrade fully collectible regardless
  of prior spending, effectively turning a guild rank change into debt.
  Accidental changes can burden the player until future income arrives.
- **Current ledger / spending / refunds:** Negative computed balances are
  already representable through authorized adjustments, and future positive
  grants/refunds can offset them. Normal `DIB_USED` then remains blocked until
  the balance recovers unless debt is separately enabled.
- **Season behavior:** A debt could carry across seasons unless a separate
  forgiveness/reset rule is designed. A season boundary does not inherently
  cancel Ledger transactions.
- **Administration / accidents:** A guild administrator can unintentionally
  impose debt by changing a rank; restoring the rank does not automatically
  reverse the debt.
- **Abuse / reversibility / audit:** Automated debt is highly abusable as a
  sanction and can make future balances opaque. Reversal requires a new
  audited credit, not rollback. Auditability is technically possible but does
  not resolve the policy harm.
- **Compatibility / impact:** Existing signed adjustment records can express
  the arithmetic, but applying this to every existing rank downgrade changes
  expected player balances. **Rejected.**

### E. MANUAL-ONLY NEGATIVE RECONCILIATION

- **Fairness / rank changes:** Human review may catch an accidental rank
  change, but does not define whether review removes balance, allocation, only
  unspent Dibs, or creates debt. Different Officers could reach different
  outcomes for the same player.
- **Current ledger / spending / refunds:** It can route through the existing
  signed `ledger.adjust`, but that still changes balance rather than assigned
  allocation. If a refund arrives later, it does not reverse the adjustment's
  allocation meaning.
- **Season behavior:** Needs a separately defined current-season versus
  next-season effect. An explicit click is not enough to resolve that.
- **Administration / accidents:** A second reviewer and required reason reduce
  mistakes, but rank-change origin (guild admin versus accidental) still
  matters and is not in the current reconciliation projection.
- **Abuse / reversibility / audit:** Less automatable but still exposed to
  privileged misuse. It is reversible only through a second audited
  transaction; it does not make the underlying policy consistent.
- **Compatibility / impact:** Does not require a new SavedVariables schema if
  it is only a balance adjustment, but has the same player impact as A/C/D.
  Manual-only is a safety gate, not a complete negative-delta semantic.
  **Not selected as reconciliation behavior.**

### F. NO NEGATIVE RETROACTIVITY

- **Fairness / rank changes:** Protects already granted allocations from
  retroactive loss when guild administration changes rank. It makes rank
  changes affect future allocation, with a deliberately one-way current-season
  rule: promotions can receive a reviewed positive top-up; demotions do not
  claw back.
- **Current ledger / spending / refunds:** Matches the positive-only
  `SEASON_ALLOCATION` transaction. A later spend or refund remains a normal
  balance event and does not change the allocation history.
- **Season behavior:** The selected season is the boundary. A demotion
  determines the next season's starting allocation; the current season's
  already-issued amount remains. Positive reconciliation uses the existing
  append-only allocation event.
- **Administration / accidents:** A rank change by an authorized guild
  administrator and an accidental rank change have the same no-clawback
  protection. A promotion top-up remains an explicit, reasoned action after a
  fresh rank check.
- **Abuse / reversibility / audit:** No automatic debit exists to exploit.
  An erroneous positive grant may be corrected only through the separate
  reviewed admin-correction process, with its own reason and audit; a rank
  demotion is not a correction reason by itself.
- **Compatibility / impact:** Existing positive allocation records remain
  unchanged; no historical balances are rewritten and no new negative event
  is required. Existing players retain what was already granted. **Selected.**

## 4. Selected Negative Delta Semantics

Use **F: NO NEGATIVE RETROACTIVITY**. Allocation is a seasonal initial grant
plus explicit positive catch-up, not a revocable live-rank entitlement.

For `Expected = 1`, `Assigned = 2`, `Difference = -1`:

- do not call `ledger.adjust`, `rank.reconcile`, or any other ledger mutation;
- keep the assigned allocation and spendable balance unchanged;
- show the row as “retained from prior allocation” / “applies next season,”
  not as a debt or actionable error;
- do not offer a negative `Reconcile` action. The current-season difference
  remains visible for explanation; the lower rank rule applies when the next
  season's initial allocation is issued;
- correct a provably erroneous transaction only through the separate,
  explicitly confirmed admin-correction workflow.

The assigned allocation projection remains as-is for existing records. Do not
rewrite `SEASON_ALLOCATION` history or infer that old players should lose
amounts. If a player's rank changes again before an explicit positive
reconciliation, calculate a new fresh projection; never queue a stale old
delta.

## 5. Promotion Behavior

For Member -> Guild Master, expected 1 -> 2, assigned 1, difference +1:

- In `MANUAL`, the Automatic Dibs page may show the +1 row; an Officer/GM must
  open a confirmation, supply a reason, and choose Reconcile. No roster event
  grants it automatically.
- In `RECOMMEND_ONLY`, the system may surface/notify the same recommendation.
  The Officer/GM must still explicitly confirm it; “recommend” never means
  “commit.”
- The coordinator verifies that the target is still a guild member at the
  current rank and the current rank rule still expects 2 while assigned is
  still 1. If any precondition changed, reject as stale and require refresh.
- The accepted +1 uses the append-only season allocation path and is
  idempotent. It does not use a balance adjustment.

## 6. Demotion Behavior

For Guild Master -> Veteran, expected 2 -> 1, assigned 2, difference -1:

- keep assigned at 2 for the remainder of the season;
- do not reduce spendable balance, even if some or all of the Dib was spent;
- do not create a negative transaction, debt, partial correction, or automatic
  Officer task;
- show that the earlier allocation is retained and that the lower rank rule
  applies to the next season;
- let the next season's normal starting-allocation workflow use the rank then
  in the fresh guild roster.

This rule is the same whether the demotion was deliberate, administrative, or
accidental. A later rank restoration does not create an extra grant if
assigned already meets the restored expected allocation.

## 7. Spent-Dib Edge Cases

| State at demotion | Result |
|---|---|
| Extra Dib is unspent | It remains in the player's current balance; no clawback occurs. |
| Extra Dib was spent | The spend remains valid; do not create debt or a negative balance. |
| Extra Dib was later refunded | The refund remains a positive balance transaction; the rank change does not consume or reverse it. |
| Rank change was accidental | Restore the guild rank if appropriate. No automatic debit is emitted while the rank is wrong. |
| Earlier positive allocation was independently erroneous | Use the separately reviewed, reason-required admin correction flow. Record the correction as such, not as rank reconciliation. |
| New season begins after demotion | Calculate and explicitly issue the new season's starting allocation from the current rank rule. Prior-season Ledger records remain untouched. |

This prevents spending order from changing the consequences of a rank
demotion. It also preserves the existing meaning of refunds and
season-scoped allocation.

## 8. Canonical Audit Context

Store the reconciliation basis in a versioned `reconciliation` metadata
section on the canonical `LEDGER_TRANSACTION`. Include it in the transaction's
canonical content hash. This is an extension to the existing Ledger record,
not a second audit subsystem. The transaction's `SEASON_ALLOCATION` amount
remains positive; negative reconciliation is not encoded as a transaction.

For a relayed action, the existing `AWARD_PROPOSAL` stores the immutable
request snapshot and the canonical `AWARD_COMMIT.proposalId` links the commit
to that request. The committed transaction must also retain the requester
identity, because its canonical writer/actor may be the coordinator rather
than the Officer who initiated the action. The canonical commit already
contains coordinator identity, epoch, sequence, and commit hash.

The transaction itself is the authoritative explanation of the balance
change. `Governance.authority.auditLog` may retain bounded proposal lifecycle
events, but is not the only place the rank/rule basis is stored.

## 9. Required Immutable Fields

### Mandatory Canonical Data

Existing transaction fields continue to carry the transaction ID/type, target
identity snapshot, season ID, positive amount/delta, reason, source, committed
timestamp, actor snapshot, and authorization action. Add the following
canonical reconciliation metadata:

| Field | Why it is required |
|---|---|
| `requestedBySnapshot` | Identifies the Officer/GM who requested the change when the coordinator is the Ledger transaction actor. For a direct coordinator action it matches the initiating actor. |
| `assignedBefore` | Compare-and-set basis and proof of what was assigned when the decision was made. |
| `expectedAllocation` | Proves the amount currently permitted by the rank rule. |
| `currentRankIndex`, `currentRankName` | Immutable coordinator-verified guild-rank observation used to select the expected allocation. WoW exposes rank index/name, not a stable rank ID. |
| `seasonCatalogRevision`, `seasonCatalogHash` | Identifies the exact SEASON_CATALOG record/rank rules used. Do not copy the full catalog into every transaction. |
| `governanceRevision` | Identifies the authorization rules under which the coordinator revalidated the requesting actor. |
| `operationalPolicyRevision` and `reconciliationMode` | Identifies the published MANUAL/RECOMMEND_ONLY mode used for the action. If the mode is absent in a legacy guild, record MANUAL as the effective default and the absent revision explicitly. |
| `trigger` | Controlled value such as `MANUAL_RECONCILIATION` or `RECOMMENDATION_ACCEPTED`; distinguishes explicit user action from a surfaced recommendation without claiming an automatic rank event. |
| `proposalId` when relayed | Stable link from this transaction/commit to the initiating AWARD_PROPOSAL. Direct coordinator operations omit it. |

The transaction's existing `amount` is the delta; a positive rank
reconciliation must satisfy `amount == expectedAllocation - assignedBefore`
and `expectedAllocation > assignedBefore` at commit. The existing
`transactionId` is the ledger transaction ID; do not duplicate it in the
metadata. Existing transaction actor/target/timestamp/reason/source fields are
mandatory and immutable, not repeated in this subrecord.

### Optional Diagnostic Data

- `previousRankIndex` and `previousRankName`, only when a fresh, attributable
  previous-rank snapshot actually exists. There is no stable guild-rank ID in
  the current roster API, and existing ledger entries may not contain the
  previous rank.
- `previousExpectedAllocation`, only when the previous rank and the catalog
  revision defining that previous expectation are both known.
- A display label or explanatory sentence; never use it instead of the
  controlled trigger/reason fields.

Do not claim a promotion/demotion if the old rank cannot be proven. A manual
positive reconciliation remains explainable from the current rank, active
rule revision, prior assigned allocation, and explicit reason.

### Derivable Data

- Direction is derivable from signed transaction amount; selected rank
  reconciliation only permits a positive amount.
- `assignedAfter = assignedBefore + amount`.
- Current spendable balance at any sequence is derivable by replaying that
  season's ledger transactions; do not store a second balance authority.
- Canonical order, transaction ID, coordinator identity, epoch, sequence, and
  commit result/hash are already in the transaction/`AWARD_COMMIT`; do not
  duplicate coordinator ID or a free-form `result` in reconciliation metadata.
- The effective rule value can be checked against the referenced
  SEASON_CATALOG revision. Keep the numeric expected value in the transaction
  as an immutable decision snapshot so future rule changes do not rewrite the
  reason for an old grant.

### Explicit Answers

| Question | Decision |
|---|---|
| Q1. What data reconstructs why balance changed? | Canonical amount, target, season, actor/requester, reason/source/trigger, assigned-before, expected allocation, current rank snapshot, exact catalog/policy/governance revisions, and commit sequence. Replay gives resulting balance. |
| Q2. What must be immutable? | All canonical transaction fields above, transaction hash, request snapshot/preconditions, proposal link, and canonical commit identity/order. |
| Q3. What can be derived? | Direction, assigned-after, resulting balance, canonical sequence/result, coordinator identity from AWARD_COMMIT, and rank-rule value verification from the catalog record. |
| Q4. Which revision proves the Rank Rule? | `seasonCatalogRevision` plus its `seasonCatalogHash`; the transaction also stores the expected numeric value used. |
| Q5. How prove rank at reconciliation time? | Store rank index/name observed by the current coordinator after it re-resolves the member from its current guild roster. AWARD_COMMIT identifies that coordinator. WoW provides no signed historical roster revision, so this proves the coordinator's observation, not a Blizzard-signed rank event. |
| Q6. How do manual and automatic reasons differ? | All current commits are explicitly manual: require nonempty human reason and controlled manual trigger. A recommendation has no transaction/reason until accepted. No automatic commit mode is permitted. |
| Q7. What if rank changes before application? | Coordinator revalidation fails; mark the proposal STALE, append no Ledger transaction, and require a refreshed row and new confirmation. |

## 10. Coordinator Proposal Flow

Reuse the existing Governance `AWARD_PROPOSAL` queue and SyncV2 relay. Do not
add a second rank-reconciliation proposal table, custom transport, or alternate
Ledger writer.

### Current Flow and Gaps

1. `ProtectedActions.Execute("rank.reconcile", ...)` authorizes a GM/Officer
   and calls `Ledger.RegisterSeasonAllocation`.
2. Under V2, `CommitSeasonAllocation` checks local coordinator authority. A
   non-coordinator path can call `Governance.RecordAwardProposal` for a
   `SEASON_ALLOCATION`; the proposal has `PENDING_RECONCILIATION`, identity,
   amount, season, rank index/name, source/context, and a content hash.
3. `Sync.RelayAwardProposal` whispers a bounded `AWARD_PROPOSAL` detail to the
   current coordinator. `Governance.ReceiveRelayedProposal` checks payload
   hash, guild, sender identity/role, and that the receiver is the current
   coordinator; duplicates with the same ID are accepted idempotently.
4. SyncV2 sends `AWARD_PROPOSAL_ACK` on receipt. For `SEASON_ALLOCATION`, it
   immediately calls `Ledger.CommitAwardProposal`; a human loot-judgment
   confirmation is not required. The resulting `AWARD_COMMIT` contains
   `proposalId`, sequence, epoch, transaction, and coordinator and is
   announced.
5. The lower-level flow is real, but the UI boundary is incomplete:
   `RegisterSeasonAllocation` returns only value/reason, discarding the
   proposal object; ACK means relay receipt, not applied; applying an
   AWARD_COMMIT on the submitter does not currently mark its local proposal
   committed; and the received proposal lacks before-state/catalog/rank
   preconditions.

### Chosen Flow

For the example Officer seeing Expected 2 / Assigned 1 / +1:

1. The Officer explicitly confirms the row and required reason. Local
   ProtectedActions authorizes the initiating actor and validates the positive
   decision basis.
2. The Ledger builds the same immutable allocation command it would use for a
   local coordinator. If the actor is not coordinator, it records one existing
   `AWARD_PROPOSAL` with `proposalId`, actor snapshot, target, season, catalog
   revision/hash, rank, assigned-before, expected, delta, reason, trigger,
   policy/governance revision, authority epoch, and intended coordinator ID.
3. ProtectedActions returns a structured `proposal-pending` outcome with the
   proposal ID to the UI. It must not report failure or success as if no
   proposal existed.
4. SyncV2 relays to the current coordinator. The coordinator verifies
   proposal schema/hash, guild scope, current sender role and identity, active
   authority epoch, intended coordinator, current roster rank, active season
   catalog/rule, current assigned allocation, positive amount, actor
   authorization, and reason.
5. Only when all compare-and-set preconditions match does the coordinator call
   `Ledger.CommitAwardProposal` / `Ledger.CommitSeasonAllocation`. It uses a
   deterministic transaction ID derived from the proposal ID/epoch; repeated
   receipt or retry returns the same commit, never a second allocation.
6. The coordinator marks its proposal COMMITTED and broadcasts the canonical
   AWARD_COMMIT. The submitter applies the commit through
   `Ledger.ApplyAwardCommit`, then marks its matching local proposal COMMITTED
   from the verified commit's proposalId/commitHash.
7. A stale or permanently invalid proposal is not committed. The coordinator
   returns a terminal `STALE` or `REJECTED` outcome to the requester through
   the existing AWARD_PROPOSAL_ACK message extended with a result/reason code.

The current AWARD_PROPOSAL_ACK remains a **receipt ACK**, not an application
ACK. Its UI wording must be “Received / awaiting canonical commit.” Only the
matching AWARD_COMMIT is proof of APPLIED. A terminal rejection response is
needed because current rejected detail transfers have no proposal-level result
stored at the submitter.

## 11. Proposal State Machine

Use current states wherever they already exist. Add only terminal states
needed to prevent a rejected/stale request from remaining pending forever.

| User-facing state | Persisted equivalent | Meaning |
|---|---|---|
| PENDING | `status=PENDING_RECONCILIATION`; local `relayStatus=RELAY_PENDING` or no coordinator yet | Stored locally; not a ledger mutation. |
| RECEIVED | Existing `relayStatus=RELAY_ACKED`; coordinator record has `receivedAt` and remains `PENDING_RECONCILIATION` | Delivery accepted by coordinator. Not committed. No new persisted ACCEPTED state. |
| APPLIED | `status=COMMITTED`, commitHash, plus matching canonical AWARD_COMMIT | Mutation is canonical. This is the only success state. |
| STALE | New terminal `status=STALE` plus reason code | Rank, assigned, catalog, season, policy, or authority precondition changed. No commit. |
| REJECTED | New terminal `status=REJECTED` plus reason code | Invalid payload, identity/permission, unsupported schema, or other permanent rejection. No commit. |
| SUPERSEDED | Represent as `STALE` with reason `AUTHORITY_CHANGED` | No separate state is needed. |
| FAILED / RETRYING | Existing `RELAY_PENDING` / `RELAY_ATTEMPTS_EXHAUSTED` delivery metadata; proposal remains PENDING | Transport/temporary coordinator failure. Not a canonical rejection and not a ledger mutation. |

Terminal status and resolution reason are lifecycle metadata on the existing
proposal. Immutable proposal content/hash must not be rewritten when status
changes. In particular, keep request content hashing separate from mutable
relay/status fields. `AWARD_COMMIT.proposalId` and its canonical commit hash
remain the proof of application.

Duplicate handling must compare the existing immutable request hash, not only
the caller-supplied proposal ID. Same operation/precondition returns the same
proposal/commit; same ID with different contents is rejected as a conflict.
Use a deterministic operation key based on target, season, catalog hash,
assigned-before, current rank, expected allocation, and operation kind. A
changed reason for the same pending key must not create a second mutation.

## 12. Coordinator Change Handling

- Bind a pending proposal to the active `ledgerEpoch`, governance revision/hash,
  coordinator member key, and policy/catalog basis used at submission.
- A proposal remains retryable only while those authority coordinates are
  current. `Sync.RelayAwardProposal` currently resolves the coordinator again
  on each retry; the new reconciliation path must not silently retarget a
  proposal created for an earlier authority epoch.
- If a coordinator handoff/recovery changes epoch or coordinator identity
  before commit, the new coordinator marks the proposal STALE with
  `AUTHORITY_CHANGED`. It does not apply the old delta and does not
  automatically rebase it. The Officer refreshes and resubmits against the new
  state.
- A commit by the old coordinator is rejected by the existing epoch/current
  coordinator checks in `Ledger.ApplyAwardCommit`; canonical history already
  committed before a valid handoff remains history and is not rolled back.
- Governance currently preserves proposal maps and audit log when a new
  authority record is applied, but does not reclassify pending proposals. The
  reconciliation receiver/authority transition must perform the stale
  classification before any pending proposal can be committed.

## 13. Stale Proposal Handling

The coordinator performs validation immediately before commit, not just when
the proposal first arrives. Any mismatch is terminal STALE and has zero Ledger
effect:

- target is missing, ambiguous, or no longer resolves to the same member key;
- target current rank index/name differs from the coordinator-verified
  proposal snapshot;
- current assigned allocation differs from `assignedBefore`;
- active season changed or the selected season is no longer valid;
- SEASON_CATALOG revision/hash or expected rank allocation changed;
- OperationalPolicy mode/revision or Governance authorization revision
  changed;
- coordinator/ledger epoch changed or the coordinator is no longer active;
- proposed amount is not exactly the current positive shortfall.

The coordinator never recomputes a different amount and silently applies it.
It returns the stale reason; the Officer refreshes the row, reviews the new
values, and explicitly submits a new operation. This covers rank change,
expected-allocation change, duplicate click after another commit, and stale
Officer screens.

## 14. Reconcile All Model

Choose **C: one orchestrated UI action producing independent canonical
operations**. Each non-coordinator row uses one existing AWARD_PROPOSAL; each
successful row produces one AWARD_COMMIT. A local coordinator commits each
row directly through the same Ledger command. There is no batch proposal and
no all-or-nothing claim.

| Model | Partial failure / retry | Audit / load / rollback | Decision |
|---|---|---|---|
| A. One proposal per player | Natural independent stale/retry result per target. Can produce partial success. | Best audit linkage and small bounded messages; proposal/commit count scales with changed rows. No rollback of committed ledger operations. | Use as the per-row transport inside C. |
| B. One batch proposal with many players | One stale row forces an unclear all-or-partial decision; retrying the whole batch risks duplicate sub-operations. | Larger payload, new batch lifecycle/atomicity and per-row state required; existing Ledger commits one transaction at a time and has no atomic multi-player transaction. Rollback would require compensating writes. | Reject. |
| C. UI orchestrator, independent operations | Preview all rows, submit each row with its own stable ID, revalidate each at coordinator, report APPLIED/PENDING/STALE/REJECTED individually. Retry only unresolved IDs. | Uses current bounded AWARD_PROPOSAL transfer and canonical one-transaction commits; load is linear and can be throttled. No batch rollback; successful rows remain committed. | Select. |

Before execution, show positive rows, retained negative rows, aligned rows,
total proposed positive change, selected season/catalog revision, and number
of operations. Process a bounded number at a time using existing transport
limits. If the existing proposal capacity is reached, stop submitting, report
remaining rows as not submitted, and resume only with the same per-row
idempotency keys. Never silently drop rows or label partial success as full
success. The existing proposal limit/retry cap remain enforced; their capacity
and terminal-record retention are release risks noted below.

## 15. Guild Policy Modes

The valid published values are `MANUAL` and `RECOMMEND_ONLY`. An absent legacy
value defaults to `MANUAL`. Invalid/unknown values fail closed to no automatic
mutation and display a warning. `AUTO_POSITIVE` is disabled; `AUTO_ALL` is not
accepted or migrated as an active mode.

| Mode | Promotion | Demotion | Officer action | GM action | Coordinator behavior | Audit behavior |
|---|---|---|---|---|---|---|
| MANUAL | No unsolicited grant. Show positive shortfall when the page is opened; explicit Reconcile may grant it. | Keep current-season allocation; mark retained/next-season, no write. | May reconcile a positive row after reason and confirmation, subject to Permissions. | Same ledger action authority; may also publish the Guild Policy mode under policy-writer rules. | Commit locally if active coordinator; otherwise existing proposal relay and full precondition revalidation. | One canonical positive allocation transaction with human reason and immutable context. No audit transaction for a no-op demotion. |
| RECOMMEND_ONLY | Surface/notify a positive recommendation; a human must still explicitly confirm to grant. | Surface only explanatory retained-allocation status; no write or debt. | May accept a positive recommendation with required reason and confirmation. | Same; no bypass of Permissions or second canonical path. | Same existing coordinator/proposal path; no automatic commit merely because a recommendation exists. | Same immutable manual transaction after acceptance; no ledger transaction for an unaccepted recommendation. |
| AUTO_POSITIVE | Invalid/disabled. Fail closed to MANUAL behavior; no automatic grant. | Retain allocation; no write. | Only explicit MANUAL/RECOMMEND_ONLY action is available. | Must publish an allowed mode; cannot enable this enum. | Never auto-commits this mode. | No automatic audit transaction; any explicit manual action is recorded normally. |
| AUTO_ALL | Invalid/removed. No positive or negative automatic mutation. | Retain allocation. | Only explicit MANUAL/RECOMMEND_ONLY action is available. | Cannot publish this enum. | Never auto-commits this mode. | No automatic audit transaction. |

If the mode becomes part of OperationalPolicy, add it as a versioned,
allowlisted field there. Do not store a second copy in SEASON_CATALOG or rank
rules. The current policy revision/hash is included in a committed positive
reconciliation for audit.

## 16. Safety Invariants

Implementation MUST enforce all of the following at the domain/command
boundary, not only in the UI:

1. Rank reconciliation never directly mutates balance or SavedVariables.
2. The canonical Ledger transaction path is the only durable allocation
   writer; the transaction is positive and season-scoped.
3. No rank demotion, rank-rule decrease, or policy mode creates a negative
   allocation transaction or automatic debit.
4. A positive reconciliation is allowed only when current expected allocation
   is greater than assigned-before and `amount == expected - assignedBefore`.
5. Coordinator revalidates target, current guild rank, season, SEASON_CATALOG
   revision/hash, rank rule, assigned-before, Governance authorization, and
   policy revision immediately before commit.
6. Stale proposal means no mutation. Never recompute and apply a new delta
   without fresh user confirmation.
7. An idempotency key and deterministic transaction ID prevent duplicate
   commits on double-click, replay, retry, or repeated `Reconcile All`.
8. The requesting actor and coordinator are separately identifiable; never
   overwrite the initiating Officer with the coordinator as the sole audit
   actor.
9. Reason is required and validated by ProtectedActions for every manual
   reconciliation. UI-only validation is insufficient.
10. Canonical audit context is immutable and included in transaction/commit
    hashes. Proposal lifecycle status changes do not rewrite proposal content.
11. Only the active coordinator commits a V2 operation. No-coordinator,
    coordinator-offline, sync-behind, or authority-recovery states remain
    pending or fail closed; they never fall back to local balance mutation.
12. Old/unknown peers that cannot validate reconciliation metadata must not
    originate or apply this operation. Unknown compatibility fails closed for
    this feature.
13. A local relay receipt ACK is not presented as commit success. Only a
    verified matching AWARD_COMMIT is APPLIED.
14. No negative balance is created as a consequence of rank reconciliation.
    The existing explicit admin correction/debt path remains separate.
15. Reconcile All reports each row's actual result and does not imply atomicity
    or attempt automatic rollback of committed rows.

## 17. Migration/Compatibility Impact

- Keep all existing `SEASON_ALLOCATION` transactions and player states
  unchanged. Do not backfill previous rank, expected allocation, or reason
  fields that were never recorded; display the historical context as
  unavailable rather than inferred.
- Keep existing negative `DIB_ADMIN_ADJUSTMENT` entries and debt behavior
  unchanged. They are not rank allocations and must not be relabeled.
- Make reconciliation metadata optional for legacy transactions and required
  for new `rank.reconcile` commands. Do not change the root SavedVariables
  schema solely to add an optional transaction subrecord/proposal lifecycle
  field; update the canonical transaction content/hash version as required by
  the implementation.
- Because older clients hash fewer canonical fields, they cannot safely apply
  a new transaction that includes reconciliation context. Require the new
  reconciliation-capable addon/protocol version; known older minors and
  unknown versions must fail closed for proposal receipt and commit. Do not
  downgrade to a context-free `SEASON_ALLOCATION` on compatibility failure.
- New proposal fields are included in a versioned AWARD_PROPOSAL content hash.
  Old pending `SEASON_ALLOCATION` proposals have no compare-and-set basis; do
  not auto-commit them after upgrade. Mark them for refresh/review or leave
  them non-committable until resubmitted.
- The requested actor snapshot is stored in the proposal and copied into the
  canonical transaction context. The coordinator remains the canonical
  committer in V2; the requester's identity is not lost.
- Preserve existing AWARD_COMMIT epoch/sequence/replay behavior. A repeated
  canonical commit remains idempotent. Add the proposal-to-commit completion
  hook on the submitter without mutating the immutable transaction.

## 18. Test Requirements

Implementation is not releasable until focused tests cover:

- Current ledger arithmetic: allocation versus spendable balance; normal
  insufficient-balance `DIB_USED`; explicit manual adjustment/debt; refund
  affects balance but not allocation.
- Q1-Q8 semantics: Member -> GM positive +1 requires explicit confirmation;
  GM -> Veteran negative -1 creates no transaction/debt; spent Dib stays
  spent; accidental demotion/restoration does not claw back; next-season
  allocation follows the current rank.
- Manual and recommendation-only modes: no automatic ledger mutation;
  required reason; invalid `AUTO_POSITIVE`/`AUTO_ALL` values fail closed.
- Canonical audit: every mandatory field is hash-protected; transaction replay
  reconstructs assigned-after and balance; optional historical rank remains
  unknown when absent; catalog/policy/governance references resolve to the
  revisions used.
- Stale officer view: current rank, assigned allocation, season, catalog/rank
  rule, policy, authority epoch, or actor permission changes before commit;
  every case returns STALE/REJECTED with no ledger mutation.
- Single coordinator positive commit and non-coordinator relay/commit; actor
  and coordinator remain separately recorded; submitter marks COMMITTED only
  after applying the matching AWARD_COMMIT.
- Receipt ACK is not APPLIED; terminal rejection/stale result reaches the
  submitter and does not loop as a pending relay.
- Coordinator offline/no known coordinator, bounded retries, reconnect retry
  cycle, relay-attempt exhaustion, and retry after recovery.
- Coordinator/epoch change while pending: old proposal is STALE and is not
  silently retargeted; old coordinator commit is rejected by epoch fencing.
- Duplicate clicks/proposal delivery, same-ID/different-content conflict,
  AWARD_COMMIT replay, and retry after lost commit broadcast all produce at
  most one allocation.
- Reconcile All with all-success, partial success, stale rows, capacity limit,
  transport interruption, and retry; successful rows are never repeated and
  failed rows are individually reported.
- Unsupported/unknown addon version and old proposal/transaction schema fail
  closed without partial mutation; existing legacy transactions still load.

## 19. Remaining Risks

- WoW does not provide a DIBS-verifiable, immutable historical guild-roster
  revision. The canonical transaction can prove the current coordinator's
  rank observation and commit ordering, not a Blizzard-signed rank event.
  Require a fresh roster and fail closed if the member/rank is ambiguous.
- Rank index and rank name are observations, not durable guild rank IDs. Store
  both at commit and use the exact catalog revision for allocation value.
- Current proposal state is bounded (`MAX_PROPOSALS`) and relay retries are
  capped. Reconcile All must respect the bounds and report unsubmitted rows;
  implementation should verify terminal proposal retention does not exhaust
  capacity in routine guild use.
- Existing code currently reports relay receipt as `RELAY_ACKED`, may not
  return a terminal rejection to the proposer, may discard proposal details
  through `RegisterSeasonAllocation`, and does not mark the submitter's local
  proposal COMMITTED when applying AWARD_COMMIT. These are explicit
  implementation requirements, not remaining design questions.
- Guild administrators can change rank during a season. The no-retroactivity
  rule avoids a debit but intentionally allows retained allocation to exceed
  current rank expectation until next season; the Automatic Dibs UI must
  explain that state without calling it a balance error.
- Existing manual admin corrections may intentionally or accidentally create
  negative balances. This architecture does not redefine that separate
  workflow; it only forbids rank reconciliation from creating debt.

## Final Decision

Negative delta semantics: **RESOLVED**

Audit context: **RESOLVED**

Coordinator proposal handling: **RESOLVED**

**FINAL: READY FOR IMPLEMENTATION**