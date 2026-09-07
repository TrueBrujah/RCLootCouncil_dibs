# Security and Design Review — September 6, 2026

This review covers the local repository state, including uncommitted changes at
the time of the original audit. It preserves the audit baseline and its findings;
the fixes described below are now integrated into the source files. The review
covers permissions, transport, identity, the ledger, and RCLootCouncil
integration. It is not certification against a live WoW client.

## Result

The modular structure and the ProtectedActions entry point are retained. The
baseline found several permission, transport, and integrity defects; they were
fixed and covered by the test suite.

Requested policy for Dibs administrative actions:

| Verified role | Standalone | RCLootCouncil integration |
| --- | --- | --- |
| GM of the relevant guild | All Dibs rights | All Dibs rights |
| Officer according to that guild's rank policy | All Dibs rights | All Dibs rights |
| Current RCLootCouncil Master Looter | RCLootCouncil loot management only; automatic consumption after a finalized DIB response | RCLootCouncil loot management and automatic consumption after a finalized DIB response |
| Current council member | No Dibs administrative rights from this role alone | No Dibs administrative rights from this role alone |
| Ordinary player | Viewing and permitted personal operations | Viewing and permitted personal operations |

“All Dibs rights” applies to Dibs rules and the Dibs ledger. It does not give the
council control over loot reserved for the Master Looter in RCLootCouncil. The
Master Looter can manage the RCLootCouncil session and send a non-accounting
reminder, but cannot arbitrarily grant, remove, or set Dibs.

## State after correction

- `AUTO`, `STANDALONE`, and `RCLootCouncil` are persistent modes; administrative
  actions always require a verified GM or Officer.
- Former administrator appointments remain historical data and grant no power.
- RCLootCouncil callbacks consume a Dib only for a finalized `DIB` response and
  a verifiable Master Looter; tests and non-DIB responses are ignored.
- Core APIs, Adventure Guide settings, and season transitions pass through the
  protected authorization boundary.
- Synchronization messages validate guild, owner, role, revision, size, and
  state transitions before writing.
- Officer views, logs, snapshot/digest exports, and the full relay fail closed
  without exposing data when called by an ordinary player.
- A RCLootCouncil callback received on a client that is not the local Master
  Looter is ignored; identity is not trusted solely from an actor object supplied
  by the caller.

The following sections describe the baseline findings and the decisions that led
to these corrections.

## High-priority baseline findings resolved in the current implementation

### 1. High — permissions differed from the requested policy

References: `src/modules/Permissions.lua:82`,
`src/integrations/RCLootCouncil.lua:1721`.

In Standalone mode, `EvaluateStandalone` authorized the local GM and named
administrators in SavedVariables but did not consult `IsOfficer`. In operational
integration mode, `EvaluateAuthority` compared the actor only with the Master
Looter; neither the GM nor the council had an exception.

Reproduction: a local GM with another player as Master Looter received `false`
for `ledger.adjust`.

Correction: apply the matrix above through one policy. Identify Officer ranks by
their configured guild indices instead of assuming rank 1 is the only Officer
rank. Revalidate rights after a guild, rank, Master Looter, or council change.
Update tests and documentation whenever the policy changes.

### 2. High — implicit authority changes when RCLootCouncil is degraded

Reference: `src/modules/Permissions.lua:94`.

Every RCLootCouncil state other than `operational` fell through to
`EvaluateStandalone`, including `degraded` and detection errors. That could
restore Standalone rights while the installation was configured for
RCLootCouncil.

Correction: persist an explicit `standalone` or `rclootcouncil` choice. In
RCLootCouncil mode, retain verified GM access as requested but reject unverifiable
Master Looter or council claims. A RCLootCouncil failure must not change the
authority policy.

### 3. High — serialization did not match the embedded library

References: `src/integrations/Ace3.lua:43`,
`src/libs/AceSerializer-3.0/AceSerializer-3.0.lua:122`,
`tests/helpers/load_addon.lua`.

The adapter expected `true, payload` from the library, while the embedded library
returns the serialized string directly. The adapter therefore returned `nil`.
`Sync.Send` fell back to a text message containing only the type and an ID, so
request and manifest data were lost.

Reproduction with the embedded library: the native result was a string while the
adapter result was `nil`. The simulator returned the false contract and hid the
defect.

Correction: read `ok, payload = pcall(...)`, validate that `payload` is a string,
and add a round-trip test using the embedded library that checks received content,
not only send success.

### 4. High — Dibs were consumed for awards that were not DIB awards

References: `src/integrations/RCLootCouncil.lua:1806`,
`src/modules/ProtectedActions.lua:222`.

`OnAwardSuccess` forced `finalized = true` and did not verify the selected
response. An eligible candidate could therefore lose a Dib for ordinary loot.
`test_mode` also reached the production path.

Reproduction: calling `OnAwardSuccess` with `test_mode` reduced the real local
balance by one.

The [upstream RCLootCouncil code](https://github.com/evil-morfar/RCLootCouncil2/blob/develop/ml_core.lua)
emits `RCMLAwardSuccess` with statuses including `test_mode`, `normal`,
`manually_added`, and `indirect`, as well as a `responseText` argument. The event
alone does not prove that a real DIB spend occurred.

Correction: verify the DIB response and real award mode before writing. Exclude
tests from the production ledger. Define how re-awards are handled, including a
compensating refund and a new debit when appropriate.

### 5. High — award references were not unique across sessions

Reference: `src/integrations/RCLootCouncil.lua:1812`.

The reference used the session index, winner, and item ID but did not include a
unique loot-session ID or season. Identical items awarded to the same player at the
same index in different sessions were treated as one award.

Correction: distinguish the persistent loot-session identifier from the awarded
item identifier and include guild/season scope. Test retransmission and a new
award in separate sessions.

### 6. High — synchronization did not sufficiently validate sender or content

References: `src/modules/Sync.lua:48`, `src/modules/PreDibs.lua:564`,
`src/modules/PreDibs.lua:593`.

Reception mainly checked that `playerName` matched the sender. It did not verify
guild membership, reservation policy, or the role authorized for an acknowledgement.
`UpsertFromSync` accepted a new confirmed request directly and did not reapply
transition rules to updates. A local final status could therefore be replaced by
an active status with a higher revision. Received fields were copied too broadly.

Correction: use only the sender supplied by the transport, verify guild and
channel, validate an allowlisted field set, and reapply creation/transition
invariants. Verify acknowledgement authority and exact revision. Bound requests,
revisions, size, depth, and per-sender frequency. SavedVariables or an actor ID in
the payload are not proof of remote authority.

### 7. High — recovery protocol was incomplete and messages could raise errors

Reference: `src/modules/Sync.lua:48`.

`MANIFEST` built a `FETCH` request but the network handler did not send it. `FETCH`
returned `true` without data. `TRANSFER_END` applied `message.request` without
assembling or verifying all fragments. Fragments were not tied to the original
sender and the global transfer count was unbounded. The manifest covered only the
local player's active requests and omitted cancellations needed for recovery.

Reproduction: `TRANSFER_BEGIN` without `chunkCount` caused
`attempt to compare nil with number`. An ACK without a revision could also reach
an invalid numeric comparison when the request existed.

Correction: implement and test the complete two-client cycle, including
cancellations, loss, and retransmission. Validate every message before access or
comparison. Add global caps, a total byte budget, integer indices, complete
assembly, and transfer/sender binding.

Seasons, rank rules, and transactions do not have an operational network exchange
here. `SyncSnapshot`/`ApplySnapshot` alone do not provide convergence.

### 8. High — two conflicting balance calculations and zero rules were overwritten

References: `src/modules/Ledger.lua:74`, `src/modules/Ledger.lua:326`,
`src/Core.lua:361`.

`GetBalance` used the allocation stored in ledger state. `GetPlayerSeasonState`
used the current rank rule. The RCLootCouncil column and eligibility checks could
therefore use different amounts. `ApplyDefaultRules` also replaced a configured
zero allocation with 1 at startup.

Correction: use one balance calculation everywhere. If the ledger is authoritative,
record allocations and adjustments as events instead of recalculating them from the
current rank. Distinguish a missing rule from a rule whose value is zero.

### 9. High — ledger writes were insufficiently validated

References: `src/modules/Ledger.lua:95`, `src/modules/Ledger.lua:219`,
`src/modules/ProtectedActions.lua`, `src/modules/Sync.lua:220`.

Normal mutations used `AddTransaction` without calling `ValidateTransaction`.
`Use` accepted a negative number and inverted its sign; it did not enforce a
sufficient balance. `ApplySnapshot` also injected transactions through
`AddTransaction` without provenance context.

Reproduction: `Use(player, -2)` increased the balance by 2.

Correction: use one validated write path with type, finite-number, integer, action
sign, season, and reason checks. Prevent spending more than the balance when debt
is not allowed. Reserve signed values for explicit administrative adjustments. Do
not expose `ApplySnapshot` to the network without provenance validation.

Lua globals are not a security boundary against the owner of a client. The
inter-player risk depends on what other clients accept; no network path directly
calling `ApplySnapshot` was found in the audited state.

### 10. High — possible refresh loop in the voting window

References: `src/integrations/RCLootCouncil.lua:1437`,
`src/integrations/RCLootCouncil.lua:1593`.

The `Update` hook scheduled `apply`. `apply` cleared the pending flag before
installers and `refreshVotingColumns`, which called `Update` again. Once installed,
the refresh could schedule its own next timer.

Correction: keep a re-entry guard for the entire operation, do not call `Update`
from its own hook, and reinstall columns only after a structural change. Run the
timer queue until it reaches a stable state.

### 11. Medium — identity resolution was ambiguous across realms

References: `src/Core.lua:282`, `src/modules/Permissions.lua:50`,
`src/modules/Ledger.lua:21`.

`GetPlayerName` retained only the first result of `UnitName`. `IsOfficer` then
compared that value without normalizing the roster name. The ledger also accepted
the first short-name match even when the requested name specified another realm.
Two same-named characters could be confused. The simulator supplied a qualified
name and hid part of the issue.

Correction: centralize GUID and Name-Realm identity, prefer complete matches, and
reject ambiguous short-name resolution. Never append a realm to a string that is
already a GUID. Test same-named characters and a roster that is not yet available.

### 12. Medium — RCLootCouncil-owned history was modified automatically

Reference: `src/integrations/RCLootCouncil.lua:1151`.

`sanitizeRCLootCouncilHistory` walked every RCLootCouncil history entry and
replaced identifiers that did not match its expected format during initialization.
It did not limit the operation to entries created by Dibs.

Correction: keep Dibs audit data separate. If a migration of Dibs-owned
RCLootCouncil entries is required, restrict it to a provenance marker, version it,
and preserve the previous identifiers.

## Design proposal and work order

1. **Permissions and installation.** Keep one package with RCLootCouncil as an
   optional dependency, as declared by the TOC. Store an explicit installation
   mode and centralize the requested matrix. Identify Officer ranks in guild
   configuration and do not use named Standalone administrators as a third policy.
2. **Accounting.** Use one validated mutation service, one balance calculation,
   and explicit allocation and compensation events. Correct DIB awards, test-mode
   handling, and award identifiers before deployment.
3. **Transport.** Fix AceSerializer, then run a real two-client scenario covering
   shared season configuration, request, acknowledgement, cancellation,
   disconnect, and recovery. Each client must verify the sender and authority
   before adopting a mutation.
4. **Concurrency.** Master Looters, council members, and Officers can have their
   own operational roles, but two writers must not spend the last unit for the same
   player at the same time. Use a scoped mutation sequence or another explicit
   concurrency rule, especially across raids. Identifier merging alone does not
   guarantee a coherent balance.
5. **Integration.** Keep RCLootCouncil adaptations inside the adapter, remove
   refresh cycles, preserve RCLootCouncil history, and test against the version
   actually installed by the guild.

## Validation and limits

- The existing Lua suite was run through a temporary Lua 5.1 engine: **102 tests
  passed, 0 failed, 33 files**.
- Independent probes covered the real AceSerializer contract, TRANSFER_BEGIN
  validation, conflicting balances, zero allocation preservation, negative
  quantities, GM authority under RCLootCouncil, degraded-mode fallback, test-mode
  debits, reference collisions, and unauthorized requests/acknowledgements.
- The simulator uses a false Serialize contract and already-qualified UnitName
  values. These tests do not replace loading the real libraries or exchanging data
  between two clients.
- The UI refresh loop, same-name client behavior, and RCLootCouncil history changes
  were reviewed statically. No live-game test or validation against the installed
  WoW version was performed.
- This security review addresses Dibs integrity between clients. It does not claim
  to demonstrate compromise of a Battle.net account or computer.
