# RF-0012 Retail Validation Record

Feature: `026-canonical-idempotent-corrections` — canonical idempotent dispute
corrections.

Status: **PENDING_MANUAL_VALIDATION**

This document is the manual in-game validation record required before the
canonical correction path can be enabled in a release build. It has **not** been
executed. Every automated result in the repository is a Fengari/Lua result; it
is not a Retail certification, and this file must not be read as one.

## 1. Why this record exists

FR-041 requires that automated test success is never presented as Retail client
certification. Release readiness for RF-0012 needs both:

1. the automated evidence recorded in
   `specs/026-canonical-idempotent-corrections/IMPLEMENTATION-STATUS.md` and in
   `tasks.md`; and
2. the multi-client observations recorded below.

Until every row in section 5 is marked `PASS` with an actual observation, the
canonical correction path stays closed in the release source. The Ledger writer
gate, the private runtime readiness probe, and the protected-boundary flag
remain fail-closed, and the SyncV2 `ledgerOperationCommit` capability is not
advertised.

## 2. Prerequisites before starting

| Prerequisite | Requirement |
|---|---|
| Build | An explicitly enabled pre-release candidate. The stock release build keeps the canonical path closed. |
| Guild | A dedicated test guild. Do not use a live production guild. |
| Accounting | No live production accounting. Use a test season with synthetic allocations. |
| Clients | Four clients, each with its own SavedVariables. |
| Addon version | The candidate build under test, on every client. Record the exact version string. |

## 2a. How the pre-release build exercises the canonical path

This section answers a question that must be settled before the session
starts: **how does a test build open the canonical correction path without
creating a way for a player to open it?**

**The release flag is compiled into the source.** The single control is the
constant `Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED` in `src/Core.lua`:

```lua
Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = false
```

- The **stable release** ships `false`. The canonical correction path is
  closed on every client, in every guild, for every player.
- The **pre-release candidate** ships `true`. The release owner changes that
  one line in a reviewed source revision and builds the candidate. Nothing
  else differs.

**There is no runtime switch.** The flag is not:

- a user preference, and there is no UI control for it;
- a SavedVariables value, and no `/dibs` subcommand writes it;
- settable by a client, a peer, or a received message.

A player who hand-edits `RCLootCouncil_dibsLocalDB` to add
`canonical_operations = true` changes nothing: no code reads such a value.
`tests/integration/t013_lock_verification_spec.lua` asserts exactly that —
that a hand-edited SavedVariables value does not open the path, and that the
local settings table never contains such a key.

**The flag alone is not sufficient.** Even with the flag `true`, the shared
runtime gate `Sync.CanonicalOperationGate` still requires, before any
accounting effect:

- the Governance authority to be `ACTIVE` and not in a recovery or handoff
  state (`Governance.GetDibUseGate`);
- the client not to be `SYNC_BEHIND`;
- the Ledger's own `verifyCanonicalCursor` to find a contiguous validated
  epoch, sequence, and root hash;
- an approved explicit ledger and a verifiable original transaction in that
  ledger;
- a verified current coordinator with the required authority.

So a candidate build with the flag enabled still refuses visibly — with an
explicit diagnostic and no accounting effect — whenever the guild, the
authority, the recovery state, the sequence, or the peer capability is not
ready. This is the FR-028 requirement: *the same gate guards every direct
writer, the coordinator acceptance path, and every receiving path*.

**The stable build remains in the test guild** for scenario S5/S10. It is
the incompatible peer: it advertises no `ledgerOperationCommit` capability,
refuses an operation record, and stays visibly behind. That observation is
part of the evidence that the closed path really is closed.

**The flag is changed only in a reviewed source revision.** The change is
recorded in the release notes, and the candidate build version is recorded
in section 4 below. The stable release line keeps the flag `false` until T041
is fully recorded and the release owner approves.

## 2b. What happens if the flag is wrong

| Situation | Observable result | Interpretation |
|---|---|---|
| The candidate build does not load | A Lua error at login, or `/dibs overview` does not answer. | A Lua 5.1 compilation limit was hit. Run `tests/powershell/Test-DibsLua51Compilation.ps1`. |
| The candidate loads but the flag is `false` | The Officer cannot accept a correction; the reason names a disabled feature. | The candidate was not rebuilt with the flag set. |
| The candidate loads, the flag is `true`, but the guild has no V2 authority | The correction is refused with an explicit reason; nothing is written. | The guild configuration is incomplete. Use **Guild Configuration** first. |
| The candidate loads, the flag is `true`, but a peer is on the stable build | The candidate accepts; the stable peer refuses and stays behind. | Expected. This is scenario S5. |
| A player claims the stable build opened the path | Not reproducible. The stable build has no runtime switch. | — |

## 3. Roles and roster

The scenario needs one coordinator, one non-coordinator Officer, one
compatible follower, and one offline/reconnecting member.

| Slot | Character | Guild rank | Notes |
|---|---|---|---|
| Coordinator | `TBD` | Guild Master | The only client that may accept a canonical correction. |
| Officer | `TBD` | Officer | Proposes a correction; must never accept one locally. |
| Follower | `TBD` | Member | Compatible client. Receives and projects the accepted correction. |
| Reconnecting member | `TBD` | Member | Goes offline before the correction and reconnects afterwards. |

## 4. Client and build identification

Record for every client. A row that is not filled in means the corresponding
observation is not evidence.

| Client | Character | Addon version | SavedVariables path | Notes |
|---|---|---|---|---|
| 1 | `TBD` | `TBD` | `TBD` | |
| 2 | `TBD` | `TBD` | `TBD` | |
| 3 | `TBD` | `TBD` | `TBD` | |
| 4 | `TBD` | `TBD` | `TBD` | |

Confirm for each client that the SavedVariables are genuinely independent:
a change on the coordinator must not appear in the other clients' files before
synchronization.

## 5. Observations

Each row must record what was actually seen in the game, not what the code is
expected to do.

| # | Observation | Expected in Retail | Result | Notes |
|---|---|---|---|---|
| 1 | Actual guild identity and rank are resolved for every client. The coordinator identity in the authority state matches the real Guild Master. | Matches | `PENDING` | |
| 2 | The Officer creates a correction for a dispute that references a real, verifiable original transaction. | Accepted for review | `PENDING` | |
| 3 | The Officer's attempt is **not** accepted locally. No balance, transaction, sequence, or root hash changes on the Officer client. | Refused with an explicit reason | `PENDING` | |
| 4 | The proposal reaches the coordinator with a stable proposal ID, operation ID, payload hash, request ID and revision, evidence, ledger, entries, reason, and verified proposer identity. | Preserved | `PENDING` | |
| 5 | The coordinator accepts the correction. Exactly one canonical commit is appended at exactly one sequence position. | One commit | `PENDING` | |
| 6 | The original transaction is unchanged. The correction is appended; no historical row is edited or deleted. | Append-only | `PENDING` | |
| 7 | The accepted commit is announced on the canonical GUILD route without waiting for a later fetch. | Announced | `PENDING` | |
| 8 | The follower receives the commit and applies it in order. Balances, the sequence, and the root hash match the coordinator. | Converged | `PENDING` | |
| 9 | A duplicate delivery of the same commit changes nothing: no second sequence entry, no second transaction, no balance change. | Idempotent | `PENDING` | |
| 10 | A commit delivered beyond a missing sequence is not applied out of order. The client shows a behind/recovery state and requests the missing commits. | Behind, then caught up | `PENDING` | |
| 11 | The reconnecting member applies the missing commits in order after reconnecting and converges with the coordinator. | Converged | `PENDING` | |
| 12 | After a `/reload`, the coordinator observes the accepted operation still present, and the operation-state projection is rebuilt from the accepted history. | Retained | `PENDING` | |
| 13 | An accepted operation whose projection was interrupted is rebuilt on the next startup. No second canonical commit is created. | Rebuilt, single commit | `PENDING` | |
| 14 | A client running an incompatible version refuses the operation record, shows an update/incompatible status, stays behind, and applies no part of the record. | Refused, behind | `PENDING` | |
| 15 | A stale epoch or a wrong ledger scope is refused with an explicit reason and no partial effect. | Refused | `PENDING` | |
| 16 | The same operation ID with a different payload is refused as a conflict, with no mutation. | Conflict | `PENDING` | |
| 17 | A correction whose original transaction cannot be verified is refused with an explicit reason and no accounting effect. | Refused | `PENDING` | |
| 18 | The historical correction report is read-only. It classifies candidates and applies nothing. | Read-only | `PENDING` | |
| 19 | The officer UI shows one explicit outcome and its reason for every correction result, with no durability or universal-propagation claim. | Visible and explicit | `PENDING` | |
| 20 | The correction view exposes no live loot candidate, vote, or session data, and no other guild's data. | Isolated | `PENDING` | |

## 6. Failures observed

Record every failure separately from the automated results. A failure here
blocks the release; it is not a documentation item.

| # | Observation | Observed behavior | Client | Investigation |
|---|---|---|---|---|
| — | `NONE RECORDED` | | | |

## 6a. Per-observation execution detail

The table in section 5 is the record. This section states, for each
observation, the **preconditions**, the **exact actions**, the **expected
result**, the **result that constitutes a failure**, the **data to collect**,
and the **way back to the initial state**. The narrative procedure with the
exact commands is in
[the RF-0012 test runbook](rf-0012-retail-test-runbook.md); the scenario
ids below map one-to-one to that document.

| # | Preconditions | Exact actions | Expected result | Failure result | Data to collect | Back to initial state |
|---|---|---|---|---|---|---|
| 1 | All four clients online in the test guild; the candidate build on Coordinator, Officer, and Follower. | S1: open Synchronization on the Coordinator; open the Officer window on the Officer and the Follower. | The coordinator is the real Guild Master; the Officer sees a read-only queue; the Follower sees no dossier. | A different name is shown as coordinator, the Follower sees the dossier, or the Officer reaches Guild Configuration. | Coordinator display name per client; Synchronization screenshot. | Nothing to undo. |
| 2 | A request referencing a real transaction id exists (from `/dibs history`). | S2: on the Officer, open the request, note its revision, use **Adjust Dibs**, enter amount and reason, tick the acknowledgement, **Review**, **Confirm action**. | The Officer changes no balance and appends no transaction; the request stays open with a proposal sent. | The Officer's balance changes, a transaction appears, or the Officer reports it as accepted. | Request id and revision; Officer balance and transaction count before and after; the exact pending wording. | Restore the Officer from its backup if anything changed. |
| 3 | S2 passed; the request is visible on the Coordinator. | S3: on the Coordinator, open the same request and confirm the revision; apply the correction; record the outcome label and explanation; record the affected balance, the transaction count, the epoch, the sequence, and the root hash; open the corrected character's ledger history. | Exactly one new transaction; the original row is unchanged; the sequence advances by exactly one; the root hash changes once; the outcome is Accepted in Session, Replayed, or Rejected. | Two or more transactions, a modified original, a sequence advancing by more than one, or wording claiming a disk save or a guild-wide receipt. | Request id and revision; outcome label and explanation verbatim; balance, transaction count, epoch, sequence, and root hash before and after; screenshots of the outcome panel and the ledger history. | Restore the Coordinator from its backup. |
| 4 | S3 passed. | S3 continued: compare the proposal the Coordinator received against what the Officer submitted (proposal id, operation id, payload hash, request id and revision, evidence, ledger, entries, reason, proposer identity). | Every identity is preserved exactly. | Any identity differs, or a new identity was minted at acceptance. | The proposal and operation identity as displayed on both clients. | Restore the Coordinator from its backup. |
| 5 | S3 passed. | S3 continued: compare the affected character's balance with the approved correction amount. | The balance change equals the approved correction exactly. | The balance differs from the approved correction, or two characters' balances moved. | Balance before and after per affected character. | Restore the Coordinator from its backup. |
| 6 | S3 passed. | S3 continued: open the corrected character's ledger history on the Coordinator. | The original transaction is present and byte-for-byte unchanged; the correction is appended. | The original row was edited, removed, or reordered. | The original row before and after; the ledger history screenshot. | Restore the Coordinator from its backup. |
| 7 | S3 passed; a follower is online. | S4: on the Follower, wait for the commit; record the epoch, sequence, root hash, balance, and transaction ids. | The Follower's values are identical to the Coordinator's and the Follower reports itself current. | Any value differs, or the Follower reports a gap. | Follower epoch, sequence, root hash, balance, and transaction id; the Coordinator's matching values. | Nothing to undo. |
| 8 | S7 passed. | S7: re-submit the same correction for the same request and revision; record the outcome, the transaction count, and the sequence. | The outcome is Replayed; the transaction count, the sequence, and the balance are unchanged. | A second transaction appears, the sequence advances, or the outcome is not Replayed. | Outcome label; transaction count and sequence before and after. | Restore the Coordinator from its backup if a second transaction appeared. |
| 9 | S7 passed. | S4 continued on the Follower: confirm the Follower's transaction id equals the Coordinator's, and that only one row was added. | One identical transaction id on both clients; no duplicate row. | The ids differ, or a duplicate row exists on one client. | The transaction id on each client; the row count on each client. | Restore the affected client from its backup. |
| 10 | S4 passed; a stable build is installed on a fifth character. | S5: on the stable client, record its status and peer list; accept one more correction on the Coordinator; re-check the stable client. | The stable client advertises no `ledgerOperationCommit`, refuses the record with an explicit diagnostic, applies no part, and shows a visible behind/incompatible status. | The stable client applies the correction, shows no status, or claims to be current. | The stable client's status text and diagnostic; a screenshot. | Nothing to undo. |
| 11 | S4 and S5 passed. | S6: take the Reconnecting member offline; accept a correction on the Coordinator; bring the member back online; record the epoch, sequence, root hash, balance, and transaction count; then `/reload` and record them again. | The missing commits are applied **in order** and the client converges to the Coordinator's values; after the reload the values are unchanged and nothing is duplicated. | A commit is applied out of order, a permanent gap remains, a value differs, or a transaction is duplicated after the reload. | The Reconnecting member's epoch, sequence, root hash, balance, and transaction count before, after the catch-up, and after the reload; the Coordinator's matching values. | Restore the Reconnecting member from its backup if the catch-up failed. |
| 12 | S3 passed. | S3 continued: after the acceptance, `/reload` the Coordinator and record the transaction count, the balance, the sequence, the root hash, and the operation state. | The same values are present after the reload and the state is reported as observed after reload, never as persistence unconfirmed once observed. | A value is lost, a duplicate commit appears, or the state is claimed without verification. | The four values before and after; the operation state text; the recovery classification text. | Restore the Coordinator from its backup. |
| 13 | S12 passed. | S11: force an interruption between the canonical acceptance and the projection, then `/reload`; record the transaction count, the balance, the sequence, and the root hash. | The projections are rebuilt from the accepted history; exactly one canonical commit exists; the balance is correct. | A second canonical commit is created, a balance is wrong, or the projections stay incomplete. | The four values before and after; the canonical commit count; the recovery classification. | Restore the Coordinator from its backup. |
| 14 | S10 passed. | S5: confirm the stable client refuses the operation record and shows the incompatible/behind status, with no part of the record applied. | An explicit refusal, no applied entry, and a visible status. | Any entry is applied, or the status is absent. | The refusal diagnostic and the status text; a screenshot. | Nothing to undo. |
| 15 | S9 passed; a second approved ledger exists if the guild has one. | S10: attempt a correction whose original lives in another ledger while a different ledger is active; repeat after a coordinator handoff if available. | Each attempt is refused with an explicit reason naming the scope or epoch problem; nothing is written to the active ledger. | The correction is applied to the active ledger, or the scope is silently changed. | The refusal reasons verbatim; the balance and transaction count per ledger before and after. | Restore the Coordinator from its backup. |
| 16 | S8 passed. | S8: attempt a correction for the same request with a different amount than the accepted one. | The attempt is refused with an explicit conflict reason; no balance, transaction, sequence, or root hash changes. | The second amount is applied, or the refusal has no reason. | The refusal reason verbatim; the before/after values. | Restore the Coordinator from its backup. |
| 17 | S8 passed. | S9: file a report referencing a non-existent transaction id and attempt a balance correction on it. | The correction is refused with an explicit reason naming the missing original; nothing changes; the dossier does not resolve. | The correction applies, or the dossier resolves anyway. | The refusal reason verbatim; the before/after values. | Restore the Coordinator from its backup. |
| 18 | S11 passed. | S12: open the historical correction report; record the classification counts; record the transaction count, balance, sequence, and root hash before and after. | The report classifies the candidates and applies nothing; the four values are unchanged; no historical row is edited. | The report applies a correction, a balance moves, or a historical row changes. | The classification counts; the before/after values; a screenshot. | Restore the Coordinator from its backup. |
| 19 | S12 passed. | S13: open the request detail narrow and then wide; confirm the status and reason are fully readable; open the historical report and confirm each classification has its own label; confirm the empty state. | No clipped or ambiguous status; the reason is plain visible text; each classification has a distinct label; the empty state is explicit. | The status is truncated, the reason is hover-only, two classifications share a label, or the empty state is blank. | Screenshots of the narrow and wide layouts, the outcome panel, the report, and the empty state. | Nothing to undo. |
| 20 | S13 passed. | S14: try to read the request id from another guild; on the Officer, open a request during a live raid and check for loot data. | The dossier is not readable outside its guild; the correction view exposes no live loot candidate, vote, or session data. | A dossier is readable from another guild, or live loot data appears. | The cross-guild read result; a screenshot of the correction view. | Nothing to undo. |

**A scenario that cannot be executed is recorded as `PENDING`, never as
`PASS`.** A pending observation keeps T041 open.

## 7. Automated evidence referenced by this record

These are the Fengari results that this record complements. They are not Retail
evidence.

| Evidence | Result |
|---|---|
| Focused feature regression set (T036) | 128 passed, 0 failed across 14 suites. |
| Combined targeted run | 213 passed, 0 failed across 22 suites. |
| Complete repository suite (T037) | See `IMPLEMENTATION-STATUS.md`. |
| Distributed convergence | The real `Ledger` and `SyncV2` modules run in separate Lua environments with independent SavedVariables. |
| Library integrity | `audit_guard.py verify` reports application-Lua differences only and zero `PROTÉGÉ` deltas. |

## 8. Release decision

| Item | State |
|---|---|
| All observations in section 5 recorded as `PASS` | `PENDING` |
| All failures in section 6 resolved | `PENDING` |
| Release owner approval | `PENDING` |
| Canonical correction path enabled in the release source (T043) | `NOT ENABLED` |

Until every row above is `PASS`, the correct state is:

**IMPLEMENTATION COMPLETE — PENDING RETAIL VALIDATION.**
