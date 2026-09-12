# RCLootCouncil_Dibs Technical Audit

**Date:** 2026-09-12  
**Mode:** Read-only static audit  
**Scope:** src/, tests/, docs/, specs/, package metadata and embedded Ace3 libraries.

No source files were modified. The full test suite was not rerun, as requested.
The repository documentation reports 226 passing tests across 54 suites; this
report treats that as existing evidence, not as a new validation run. Retail
live-client validation, real two-client traffic, and validation against the
currently installed RCLootCouncil build remain outside this audit.

## Executive Summary

The project has a strong modular foundation: Dibs domain modules are separated
from the RCLootCouncil adapter, accounting is append-oriented, protected actions
centralize most UI mutations, and the test suite covers many baseline authority,
reconciliation, combat and compatibility cases.

The project is not ready for another production implementation phase without
addressing the distributed-state boundary. The most important gap is that the
documented multi-raid/shared-guild behavior is not implemented as a convergent
protocol:

- configuration changes such as Pre-Dib mode are written only to the local
  SavedVariables;
- automatic sync is sent to RAID, not GUILD, and is triggered mainly by roster
  changes;
- ledger transactions are not exchanged by the live protocol;
- transfer chunks are stored but not assembled or decoded at TRANSFER_END;
- snapshots are lossy, non-atomic and have no authenticated/provenance envelope.

The second major risk is the client trust model. WoW addon Lua and SavedVariables
are editable by the local player and other loaded addons. The current role
configuration is also local. Therefore a determined player can make their own
client believe they are an officer or alter local accounting data. This cannot
be solved completely inside a normal addon, but remote acceptance must be made
more explicit and a central authoritative source must be chosen before enabling
cross-client ledger writes.

## Critical Findings

### C-001 — Shared guild policy is local-only

- **Severity:** P1
- **Files:** src/modules/PreDibs.lua:384-396; src/modules/Sync.lua:29-119;
  src/ui/PlayerUI.lua; src/ui/OfficerUI.lua
- **Function/module:** Dibs.PreDibs.SetModePolicy, Dibs.Sync, local policy readers
- **Description:** SetModePolicy validates local authority and writes
  db.preDibs.modePolicies[seasonId], but emits no sync message. The protocol
  has no configuration message, revision, hash or authoritative snapshot.
- **Why it matters:** An officer changing Wild Open to Encounter updates that
  officer's client only. Other clients can continue creating requests under the
  old mode, producing contradictory decisions.
- **Recommended remediation:** Add a guild-policy envelope containing an
  allowlisted configuration snapshot, monotonic revision, author identity,
  timestamp, guild scope and content hash. Accept only higher authorized
  revisions; reject same-revision content conflicts and audit every adoption.
- **Estimated complexity:** High

### C-002 — Multi-raid convergence is not implemented

- **Severity:** P1
- **Files:** src/modules/Sync.lua:237-247; src/modules/RaidRelay.lua:63-78;
  src/Core.lua:1242-1246; docs/developer/sync-protocol.md
- **Function/module:** Dibs.Sync.OnRosterChanged, Dibs.RaidRelay.Broadcast
- **Description:** The automatic manifest path sends on the RAID channel. The
  relay also defaults to the current raid destination. There is no guild
  backbone, relay election, guild-wide digest exchange or conflict merge for
  simultaneous raids.
- **Why it matters:** Players in two raids cannot reliably discover the same
  active Pre-Dibs or accounting state. A roster change in one raid does not
  make the other raid converge.
- **Recommended remediation:** Separate guild control-plane traffic from
  raid-scoped reminders. Use GUILD for bounded manifests/configuration and
  WHISPER for owner/detail transfer; define relay election, deduplication,
  conflict policy and privacy limits before sending ledger data.
- **Estimated complexity:** High

### C-003 — Live ledger writes have no distributed commit rule

- **Severity:** P1
- **Files:** src/modules/Ledger.lua:131-185,278-368;
  src/modules/Sync.lua:294-351; src/integrations/RCLootCouncil.lua:2826-2884
- **Function/module:** Dibs.Ledger.AddTransaction, Use, FinalizeAward,
  Dibs.Sync.SyncSnapshot
- **Description:** The live protocol exchanges Pre-Dib metadata but does not
  exchange or commit ledger transactions. Two authorized clients can finalize
  awards from different raids against different local balances. seenTransactions
  is exposed but is not used by the transaction append path.
- **Why it matters:** The append-only shape and local idempotency do not guarantee
  one coherent balance when two writers act concurrently. The last imported
  state can differ by client.
- **Recommended remediation:** Choose one authoritative writer/relay or add a
  scoped operation sequence with deterministic conflict resolution. Define
  reservation, commit, rejection and compensation semantics for concurrent
  awards before enabling cross-raid accounting.
- **Estimated complexity:** High

### C-004 — Sync transfer chunks are not actually assembled

- **Severity:** P1
- **Files:** src/modules/Sync.lua:155-182
- **Function/module:** TRANSFER_BEGIN, TRANSFER_CHUNK, TRANSFER_END
- **Description:** Chunks are stored and size-checked, but TRANSFER_END validates
  message.request supplied by the final message and passes that table directly
  to UpsertFromSync. The stored chunk payload is never concatenated, deserialized
  or compared with the final request.
- **Why it matters:** The advertised fragmented recovery protocol is incomplete.
  It can silently accept a different final payload, and the chunk data provides
  no integrity value.
- **Recommended remediation:** Assemble exactly the expected chunk count, verify
  a transfer checksum/content hash and decode the assembled payload. Bind the
  result to the sender, transfer ID, request ID and revision before applying it.
- **Estimated complexity:** Medium

### C-005 — Identity and authority depend on editable local policy

- **Severity:** P1
- **Files:** src/modules/Permissions.lua:96-164,232-262;
  src/Core.lua:106-123,560-563; src/modules/Sync.lua:42-58
- **Function/module:** rankIsOfficer, GetGuildRole, CanonicalPlayerId,
  senderIsGuildAdmin
- **Description:** Officer rank configuration is read from local
  db.settings.officerMaxRankIndex/officerRankIndices. GetPlayerName returns
  only the first UnitName("player") result, while normalization appends the
  local realm to short names.
- **Why it matters:** A player can edit local settings and make their own
  client classify a guild rank as officer. Short-name and same-name cross-realm
  collisions can also select the wrong player. This is especially dangerous
  when future configuration or ledger messages are accepted from remote admins.
- **Recommended remediation:** Use stable GUID where available, preserve full
  Name-Realm identities, reject ambiguous short-name matches, and make the
  authoritative guild policy explicit and versioned. Treat local SavedVariables
  as untrusted claims, not proof of remote authority.
- **Estimated complexity:** High

## Security Findings

### S-001 — Public mutation APIs bypass the protected action boundary

- **Severity:** P1
- **Files:** src/modules/Ledger.lua:131-185,278-368;
  src/modules/PreDibs.lua:462-484,593-729
- **Function/module:** Ledger.Grant/Use/Refund/AdminAdjust,
  PreDibs.UpdateStatus/Confirm/Cancel/Invalidate/Fulfill
- **Description:** These mutation functions are globally reachable through
  Dibs and do not themselves require an actor or authorization decision.
  CancelForPlayer has an owner check, but lower-level Cancel and UpdateStatus
  do not.
- **Why it matters:** Any loaded addon or local script can call the public
  functions and mutate the local ledger or request state. The protected UI path
  reduces accidental misuse but is not a security boundary.
- **Recommended remediation:** Keep mutators private or require a validated
  authorization/provenance context on every mutation. Return immutable copies
  from read APIs so callers cannot mutate SavedVariables through references.
- **Estimated complexity:** Medium

### S-002 — Ledger use does not enforce sufficient balance

- **Severity:** P1
- **Files:** src/modules/Ledger.lua:299-309;
  src/modules/ProtectedActions.lua:152-157,319-395
- **Function/module:** Dibs.Ledger.Use, executeLedgerUse, executeAwardFinalize
- **Description:** Use validates a positive input amount and stores a negative
  transaction, but does not reject a spend larger than the available balance.
  Finalized awards call the same path.
- **Why it matters:** Unless negative balances are explicitly allowed by guild
  policy, a malformed or repeated authorized action can create debt and make
  different clients display incompatible eligibility.
- **Recommended remediation:** Make debt an explicit policy. Otherwise perform
  an atomic balance/reservation check immediately before append and record a
  clear exception when a confirmed Pre-Dib is allowed to override a zero
  balance.
- **Estimated complexity:** Medium

### S-003 — Same transaction ID with different content is silently accepted

- **Severity:** P1
- **Files:** src/modules/Ledger.lua:135-139,159-165,240-262
- **Function/module:** AddTransaction, AppendTransaction
- **Description:** An existing transactionId returns the stored transaction and
  marks it as an idempotent replay. Incoming fields are not compared against
  the stored content.
- **Why it matters:** A collision or forged replay can be presented as a valid
  duplicate while hiding a different player, amount, season or action.
- **Recommended remediation:** Compute a canonical transaction content hash and
  reject same-ID/different-hash conflicts. Keep replay, duplicate and conflict
  outcomes distinct and auditable.
- **Estimated complexity:** Medium

### S-004 — Snapshot application has weak provenance and ignores its actor

- **Severity:** P1
- **Files:** src/modules/Sync.lua:316-424
- **Function/module:** SyncSnapshot, ApplySnapshot
- **Description:** ApplySnapshot(snapshot, actor) checks only that the local
  client is an officer/GM. The supplied actor is not used. The snapshot has no
  required guild key, author, revision, content hash or source signature.
- **Why it matters:** A local admin can unknowingly apply data from the wrong
  guild or an altered package. The method is not safe to expose as a remote
  synchronization primitive.
- **Recommended remediation:** Separate local import from remote apply. Require
  explicit scope, author, revision, hash, confirmation and audit context; never
  treat payload actor fields as proof.
- **Estimated complexity:** High

### S-005 — Remote request updates copy arbitrary fields

- **Severity:** P2
- **Files:** src/modules/PreDibs.lua:627-671
- **Function/module:** Dibs.PreDibs.UpsertFromSync
- **Description:** Basic request fields and status are validated, but the update
  loop copies almost every incoming key except a small immutable set.
- **Why it matters:** Unexpected fields, oversized strings, timestamps or nested
  tables can enter persistent request records and influence UI, audit display
  or later logic.
- **Recommended remediation:** Use an allowlist of mutable fields with per-field
  type/length/range validation. Bound nested context depth and copy sanitized
  values only.
- **Estimated complexity:** Medium

### S-006 — Replay and rate controls are incomplete

- **Severity:** P2
- **Files:** src/modules/Sync.lua:85-90,124-224
- **Function/module:** Receive, transfer tracking
- **Description:** Request revisions limit some stale updates, but there is no
  message nonce/epoch, timestamp window, per-sender rate limit or replay cache
  for HELLO, MANIFEST, FETCH and transfer control messages. seenTransactions
  is not a protocol replay mechanism.
- **Why it matters:** A guild member can replay valid control traffic, cause
  repeated fetches, or consume bounded transfer slots. Replayed old snapshots
  remain difficult to distinguish from current state.
- **Recommended remediation:** Add message IDs, sender-scoped replay windows,
  bounded request rates and a protocol epoch. Retain only bounded recent IDs.
- **Estimated complexity:** Medium

### S-007 — Normal addon messages are not cryptographic authentication

- **Severity:** P2
- **Files:** src/modules/Sync.lua:42-75,212-224;
  src/integrations/Ace3.lua:85-103
- **Function/module:** transport and envelope validation
- **Description:** Sender identity comes from the WoW transport and membership
  is checked, which is useful against malformed traffic. The payload itself is
  not signed and cannot prove that the claimed client state is truthful.
- **Why it matters:** A modified client can send a valid-looking request,
  configuration, inventory claim or snapshot. This is inherent to the addon
  environment and must be reflected in the trust model.
- **Recommended remediation:** Use transport validation only for routing and
  guild membership. Restrict remote mutations to an authoritative writer,
  label client-reported inventory as advisory, and use a server/companion
  service only when stronger authority is required.
- **Estimated complexity:** High

## Architecture Findings

### A-001 — Configuration, policy and persistence have no single ownership service

- **Severity:** P1
- **Files:** src/Core.lua:125-196; src/modules/PreDibs.lua:127-457;
  src/modules/RaidPrompts.lua:20-40; src/modules/Profiles.lua:52-123
- **Function/module:** SavedVariables projections and policy setters
- **Description:** Multiple modules read and write db.settings directly.
  Profiles, announcements, raid prompts and Pre-Dib mode can change related
  state without a unified revision/audit/sync pipeline.
- **Why it matters:** A future shared-options feature can synchronize some
  settings while leaving others local, or apply a profile without updating the
  revision expected by another client.
- **Recommended remediation:** Introduce a guild-policy service with a schema,
  allowlist, revision, diff/merge rules and one commit callback. Keep local
  presentation settings in a separate store.
- **Estimated complexity:** High

### A-002 — RCLootCouncil-owned data is mutated by the adapter

- **Severity:** P1
- **Files:** src/integrations/RCLootCouncil.lua:1814-1873
- **Function/module:** Dibs.RCLootCouncil.LogPreDibRequest
- **Description:** The adapter calls RCLootCouncil history's
  OnHistoryReceived or writes through GetHistoryDB() to create a synthetic
  Pre-Dib history entry.
- **Why it matters:** This couples Dibs persistence to RCLootCouncil's internal
  history schema and can make a reservation look like loot history. It also
  conflicts with the documented boundary that Dibs must not rewrite
  RCLootCouncil data.
- **Recommended remediation:** Keep Pre-Dib history in Dibs and expose a
  read-only projection to RCLootCouncil only through a supported extension
  point. If synthetic RC history is retained, make it explicitly opt-in,
  versioned and isolated from awarded-loot history.
- **Estimated complexity:** Medium

### A-003 — Large modules concentrate change risk

- **Severity:** P2
- **Files:** src/integrations/RCLootCouncil.lua (3618 lines);
  src/integrations/EncounterJournal.lua (1886 lines);
  src/ui/OfficerUI.lua (2446 lines); src/Core.lua (1270 lines)
- **Function/module:** adapter, UI controllers and composition root
- **Description:** These files combine capability discovery, compatibility
  fallbacks, UI construction, data projection and lifecycle retries.
- **Why it matters:** A change to one RCLootCouncil version or one UI page can
  affect unrelated lifecycle, combat or accounting behavior and is difficult
  to review in isolation.
- **Recommended remediation:** Split by stable contracts: capability probe,
  supported adapter API, history adapter, loot-frame projection, voting
  projection, policy controller and UI page controllers. Preserve one public
  facade per subsystem.
- **Estimated complexity:** High

### A-004 — Read APIs expose mutable persistent tables

- **Severity:** P2
- **Files:** src/modules/PreDibs.lua:732-840;
  src/modules/Ledger.lua:91-101,386-418; src/modules/Sync.lua:265-279
- **Function/module:** GetHistory, GetAcquisitions, GetPlayerState,
  GetAllTransactions, RegisterPeer
- **Description:** Several getters return records or arrays backed directly by
  SavedVariables.
- **Why it matters:** UI or integration code can accidentally mutate
  authoritative data without validation, and a malicious loaded addon can do
  so intentionally.
- **Recommended remediation:** Return copies or immutable projections. Keep
  mutation through domain commands only.
- **Estimated complexity:** Medium

### A-005 — Authority sources are not clearly separated

- **Severity:** P2
- **Files:** src/modules/Ledger.lua:76-125,177-184;
  src/modules/RankRules.lua:108-125; src/modules/Sync.lua:316-424
- **Function/module:** balance and snapshot projections
- **Description:** playerStates.allocation, rank rules and transaction history
  all participate in balance-related views. Snapshots project only a subset of
  fields and apply by merge.
- **Why it matters:** A future change can update a derived state but not the
  event source, causing different clients or views to calculate different
  balances.
- **Recommended remediation:** Define one canonical event stream and rebuild
  all indexes from it. Treat playerStates as a cache with a consistency checker,
  or remove the duplicated persisted derivation.
- **Estimated complexity:** High

## Synchronization Findings

### SYNC-001 — Requests are not broadcast when they are created or changed

- **Severity:** P1
- **Files:** src/modules/PreDibs.lua:496-551,593-615;
  src/modules/Sync.lua:237-245
- **Function/module:** CreatePublic, UpdateStatus, OnRosterChanged
- **Description:** The only automatic manifest send is tied to
  GROUP_ROSTER_UPDATE. Creating, confirming, cancelling or fulfilling a
  request does not directly publish a revision.
- **Why it matters:** An officer can remain unaware of a new request while the
  raid roster is unchanged. Reconnect behavior is timing-dependent.
- **Recommended remediation:** Publish a bounded change notification after each
  committed request mutation, coalesced through a throttle. Include tombstones
  for cancellations and terminal revisions.
- **Estimated complexity:** Medium

### SYNC-002 — Terminal request states are omitted from manifests

- **Severity:** P1
- **Files:** src/modules/Sync.lua:93-100; src/modules/PreDibs.lua:732-740
- **Function/module:** BuildManifest, GetActiveRequests
- **Description:** Manifests contain active requests only. A cancellation,
  invalidation or fulfillment that occurs before another client sees the
  original record has no tombstone in the manifest.
- **Why it matters:** A stale client can retain a request that no longer exists
  or reintroduce it during recovery.
- **Recommended remediation:** Maintain bounded terminal tombstones or a
  monotonically versioned request index. Define retention and season boundaries.
- **Estimated complexity:** Medium

### SYNC-003 — Snapshot projection is lossy

- **Severity:** P1
- **Files:** src/modules/Sync.lua:328-351
- **Function/module:** SyncSnapshot
- **Description:** Transaction projection omits fields such as evidenceId,
  timestamp, actionType, quantityDelta and some identity/audit fields. Request
  projection omits revision, modeAtCreation, validationContext, difficulty,
  source and delivery metadata.
- **Why it matters:** Applying a snapshot can change the meaning or audit
  quality of a request/transaction even when the operation succeeds.
- **Recommended remediation:** Version an explicit snapshot schema and include
  every authoritative field, or state that the snapshot is a non-authoritative
  diagnostic projection and prohibit applying it.
- **Estimated complexity:** Medium

### SYNC-004 — Snapshot application is not atomic

- **Severity:** P1
- **Files:** src/modules/Sync.lua:384-422
- **Function/module:** ApplySnapshot
- **Description:** Transactions are appended before all Pre-Dib records are
  validated. A later validation failure returns false after earlier writes have
  already occurred.
- **Why it matters:** A failed import can leave a partially applied ledger and
  request state, making retry and reconciliation ambiguous.
- **Recommended remediation:** Validate the complete snapshot into temporary
  structures first, detect all conflicts, then commit in one guarded operation
  or use a rollback/safety snapshot.
- **Estimated complexity:** High

### SYNC-005 — Protocol versioning is exact-match only

- **Severity:** P2
- **Files:** src/modules/Sync.lua:66-75,212-224; src/Core.lua:63-65
- **Function/module:** envelope validation and protocol constants
- **Description:** Any nonmatching protocol version is rejected. HELLO does not
  negotiate a supported range or feature set.
- **Why it matters:** A harmless patch-level difference can disable recovery for
  an entire guild, while the UI may only report a generic unavailable state.
- **Recommended remediation:** Add protocol major/minor compatibility, feature
  capabilities, minimum supported schema and an actionable mismatch diagnostic.
- **Estimated complexity:** Medium

### SYNC-006 — Compact fallback is not a complete transport

- **Severity:** P1
- **Files:** src/modules/Sync.lua:106-119,212-224;
  src/integrations/Ace3.lua:60-90
- **Function/module:** Sync.Send, OnAddonMessage
- **Description:** Without AceSerializer, the compact fallback sends only the
  message type plus request ID/revision and explicitly refuses request,
  manifest and snapshot payloads. The direct fallback also does not register
  the DIBS prefix itself.
- **Why it matters:** A client can report successful transport while no useful
  request data is delivered, and the claimed standalone fallback may fail on a
  path where AceComm is unavailable.
- **Recommended remediation:** Either make AceComm/AceSerializer a required
  embedded transport and report unavailable, or implement and test a complete
  bounded fallback with explicit prefix registration and send-result handling.
- **Estimated complexity:** Medium

## Performance Findings

### PERF-001 — Candidate display repeatedly scans ledger history

- **Severity:** P2
- **Files:** src/integrations/RCLootCouncil.lua:1972-2003;
  src/modules/Ledger.lua:91-125,420-478
- **Function/module:** getRemainingDibsText, GetPlayerSeasonState, GetBalance
- **Description:** Each voting-row Dibs display can call a full transaction scan,
  followed by a balance scan for the player. Voting-frame refreshes can repeat
  this work.
- **Why it matters:** Long histories or frequent RCLootCouncil updates can
  create avoidable CPU cost and garbage during a live loot session.
- **Recommended remediation:** Maintain validated per-player/per-season
  aggregates, invalidate them on append, and cache row projections for the
  current session.
- **Estimated complexity:** Medium

### PERF-002 — Permission and manifest paths repeatedly scan the guild/history

- **Severity:** P2
- **Files:** src/modules/Permissions.lua:114-164;
  src/modules/Sync.lua:136-146
- **Function/module:** rosterRole, manifest handling
- **Description:** Role checks walk the entire guild roster, while each manifest
  entry can walk all request history to find its matching request.
- **Why it matters:** UI pages and repeated addon traffic can turn normal
  roster/recovery activity into avoidable O(roster x checks) and
  O(manifest x history) work.
- **Recommended remediation:** Cache a normalized roster index with explicit
  invalidation on guild roster events, and index requests by requestId.
- **Estimated complexity:** Low

### PERF-003 — Startup retry watchers are broad and repeated

- **Severity:** P2
- **Files:** src/integrations/RCLootCouncil.lua:1163-1188,2374-2398;
  src/modules/Sync.lua:237-245
- **Function/module:** config/runtime hook watchers and roster retry
- **Description:** RCLootCouncil startup uses repeated timers for configuration
  and runtime hooks, while roster changes schedule another retry. Cancellation
  and coalescing are only partial.
- **Why it matters:** Load, profile and module lifecycle changes can create
  repeated probes and refresh work even when no state changed.
- **Recommended remediation:** Use one lifecycle state machine with cancellable
  timers, event-driven readiness and bounded backoff. Log only state changes.
- **Estimated complexity:** Medium

### PERF-004 — Recursive validation lacks explicit depth/cycle guards

- **Severity:** P2
- **Files:** src/modules/Sync.lua:354-364; src/Core.lua:74-88
- **Function/module:** ContainsForbiddenLiveLootData, DeepCopy
- **Description:** Both recursive walkers rely on acyclic tables and have no
  maximum depth or visited-table set.
- **Why it matters:** Malformed in-memory data or a hostile loaded addon can
  cause excessive recursion or failure before normal size limits apply.
- **Recommended remediation:** Add depth, node-count and visited-table bounds;
  reject unsupported structures before recursion.
- **Estimated complexity:** Low

## Reliability Findings

### REL-001 — Corrupted SavedVariables are not rejected or repaired safely

- **Severity:** P1
- **Files:** src/Core.lua:208-313
- **Function/module:** ensureDB, mergeDefaults
- **Description:** Defaults are merged when a key is nil, but wrong-type values
  are not consistently replaced or quarantined. For example, a non-table
  guilds, seasons or settings value can survive and later be indexed as a
  table. Future schema versions are not explicitly handled.
- **Why it matters:** Manual edits, truncation or another addon can prevent
  initialization or silently preserve invalid state.
- **Recommended remediation:** Validate root and subsystem types, quarantine
  invalid records, create a recovery backup before migration, and fail closed
  with a visible diagnostic for unsupported future schemas.
- **Estimated complexity:** Medium

### REL-002 — Initialization is not isolated by subsystem

- **Severity:** P1
- **Files:** src/Core.lua:1160-1203
- **Function/module:** Dibs.Initialize
- **Description:** Required and optional initializers are called directly. An
  unexpected error in a UI, Encounter Journal or RCLootCouncil initializer can
  abort the remaining startup path; there is no subsystem health registry with
  retry/fallback semantics.
- **Why it matters:** An optional integration failure can make core Dibs,
  SavedVariables or slash commands appear unavailable.
- **Recommended remediation:** Wrap optional initialization, record capability
  state, continue core startup, and retry only the failed subsystem on its
  relevant lifecycle event.
- **Estimated complexity:** Medium

### REL-003 — Guild roster changes do not invalidate authority

- **Severity:** P1
- **Files:** src/Core.lua:1252-1267; src/modules/Permissions.lua:114-164
- **Function/module:** runtime event registration and permission resolution
- **Description:** Core registers group/world/zone/combat events but not an
  explicit GUILD_ROSTER_UPDATE path. Rank or guild membership changes can
  remain stale until an unrelated event or roster API refresh.
- **Why it matters:** A demoted officer may retain a stale UI decision, or a
  newly authorized officer may not receive policy/recovery work promptly.
- **Recommended remediation:** Register guild roster lifecycle events, invalidate
  permission and sync caches, and revalidate immediately before every protected
  mutation.
- **Estimated complexity:** Low

### REL-004 — Short-name matching remains inconsistent

- **Severity:** P2
- **Files:** src/Core.lua:560-563; src/modules/Ledger.lua:37-69;
  src/modules/PreDibs.lua:732-740
- **Function/module:** identity helpers and request queries
- **Description:** Core stores the short local name, Ledger has roster-based
  normalization, and GetActiveRequests(playerName) compares exact strings
  instead of using the same identity function.
- **Why it matters:** Cross-realm candidates, same-name characters and roster
  timing can produce missing history, wrong balances or duplicate records.
- **Recommended remediation:** Centralize identity as GUID plus full Name-Realm,
  make all comparisons use it, and require an explicit ambiguity outcome.
- **Estimated complexity:** Medium

### REL-005 — Item metadata can be unavailable without a durable retry contract

- **Severity:** P2
- **Files:** src/modules/LootPipeline.lua:55-110;
  src/integrations/RCLootCouncil.lua:260-326
- **Function/module:** item parsing/classification and tooltip lookups
- **Description:** Several paths use synchronous item/tooltip lookups and
  tolerate nil results, but there is no shared item-data queue or item-data
  event invalidation path for all dependent UI and eligibility decisions.
- **Why it matters:** A cold item cache can display Unknown item, classify a
  token incorrectly or delay an eligibility decision without automatically
  refreshing the affected row.
- **Recommended remediation:** Centralize item resolution, mark results
  provisional, retry on the corresponding item-data event and never make an
  irreversible award decision from incomplete metadata.
- **Estimated complexity:** Medium

## WoW API / Combat Safety Findings

### WOW-001 — RCLootCouncil UI mutations are not combat-gated

- **Severity:** P1
- **Files:** src/integrations/RCLootCouncil.lua:1644-1717,1876-1925,2107-2122
- **Function/module:** injected buttons, tooltip/convert columns and
  applyDibsButtonState
- **Description:** The lootFrame.Update hook can create frames, change button
  state, reposition buttons and update columns without an explicit
  InCombatLockdown guard or deferred queue.
- **Why it matters:** RCLootCouncil updates can occur while the player is in
  combat. Protected templates and frames can trigger forbidden-action errors or
  taint, and a partial update can leave the vote UI inconsistent.
- **Recommended remediation:** Separate read-only status calculation from UI
  mutation, defer all frame creation/reparenting/enabling/repositioning while
  in combat, and apply one coalesced refresh after PLAYER_REGEN_ENABLED.
- **Estimated complexity:** High

### WOW-002 — Existing RCLootCouncil button scripts are replaced

- **Severity:** P1
- **Files:** src/integrations/RCLootCouncil.lua:1532-1570
- **Function/module:** installDibsClickGuard
- **Description:** The adapter reads the original OnClick and then calls
  SetScript("OnClick", ...) on buttons it discovers, including buttons that may
  be RCLootCouncil-owned rather than injected by Dibs.
- **Why it matters:** Replacing an addon-owned or secure handler is a taint and
  compatibility risk. Future RCLootCouncil changes can invalidate the saved
  callback or bypass expected click behavior.
- **Recommended remediation:** Never replace an existing handler. Use a
  supported callback/API, HookScript only where safe, or create a clearly
  owned Dibs button with an isolated handler.
- **Estimated complexity:** Medium

### WOW-003 — Legacy/global APIs lack a compatibility facade

- **Severity:** P2
- **Files:** src/Core.lua:106-123,560-563,1205-1267;
  src/modules/Permissions.lua:21-164; src/modules/Sync.lua:113-118
- **Function/module:** Guild, Unit, chat and event access
- **Description:** The code uses a mixture of modern C_* APIs and legacy globals
  such as GetNumGuildMembers, GetGuildRosterInfo, GetGuildInfo,
  SendChatMessage and UnitName. Static inspection did not prove each call is
  deprecated on the target Retail build.
- **Why it matters:** A future Retail API change can break authority, identity,
  announcements or transport in separate modules without one compatibility
  diagnostic.
- **Recommended remediation:** Add a small WoW API facade with feature probes,
  return normalization and target-interface tests. Treat unsupported APIs as
  explicit capability states.
- **Estimated complexity:** Medium

### WOW-004 — Direct fallback transport may skip prefix registration

- **Severity:** P2
- **Files:** src/modules/Sync.lua:106-119;
  src/libs/AceComm-3.0/AceComm-3.0.lua:60-67
- **Function/module:** non-Ace Sync.Send fallback
- **Description:** AceComm registers the prefix as part of its registration, but
  the direct C_ChatInfo.SendAddonMessage fallback does not call
  RegisterAddonMessagePrefix.
- **Why it matters:** The fallback can fail or behave differently on clients
  where the embedded AceComm registration is unavailable.
- **Recommended remediation:** Register DIBS explicitly in the fallback and
  verify the API result rather than treating a non-throwing call as success.
- **Estimated complexity:** Low

## RCLootCouncil Integration Findings

### RC-001 — Adapter depends on unstable internal RCLootCouncil structures

- **Severity:** P1
- **Files:** src/integrations/RCLootCouncil.lua:644-702,1720-1771,2613-2637;
  src/integrations/RCLootCouncilOptions.lua
- **Function/module:** module discovery, EvaluateAuthority, options projection
- **Description:** The adapter probes rc.modules, GetActiveModule, GetModule,
  Getdb/GetDB, masterLooter, internal frame fields, scrollCols,
  EntryManager, lootTable and lifecycle method names.
- **Why it matters:** These are implementation details rather than a stable
  public contract. A RCLootCouncil update can silently disable Dibs or change
  authority/loot interpretation.
- **Recommended remediation:** Define a narrow adapter contract and versioned
  capability matrix. Prefer upstream callbacks/public APIs, isolate each
  internal probe, and fail closed with the exact unsupported capability.
- **Estimated complexity:** High

### RC-002 — Award status interpretation is version-sensitive

- **Severity:** P1
- **Files:** src/modules/ProtectedActions.lua:207-218;
  src/integrations/RCLootCouncil.lua:2826-2884
- **Function/module:** isFinalAward, OnAwardSuccess
- **Description:** The allowlist treats statuses including normal, indirect and
  manually_added as final. This behavior is based on observed RCLootCouncil
  events, not a runtime contract version or a complete state machine for
  re-awards, trades and corrections.
- **Why it matters:** A future event-status change could consume a Dib for a
  non-final or non-DIB action, or fail to account for a valid award.
- **Recommended remediation:** Normalize event status through a versioned
  adapter, require explicit final-award evidence, and test every status against
  the installed RCLootCouncil version.
- **Estimated complexity:** Medium

### RC-003 — History cache signature can miss in-place edits

- **Severity:** P2
- **Files:** src/integrations/RCLootCouncil.lua:3268-3333
- **Function/module:** historyDBSignature, GetHistoryRows
- **Description:** The cache signature is based on counts and selected first/last
  markers. A metadata change to an interior history row can leave the signature
  unchanged.
- **Why it matters:** Reconciliation may show stale response, winner, item or
  timestamp data until another detectable boundary changes.
- **Recommended remediation:** Use an upstream history-change callback, a
  maintained revision, or a bounded content hash of all stable row markers.
- **Estimated complexity:** Medium

### RC-004 — Integration and Dibs histories have mixed provenance

- **Severity:** P2
- **Files:** src/integrations/RCLootCouncil.lua:1814-1873,2963-3617;
  src/modules/Ledger.lua:360-368
- **Function/module:** Pre-Dib logging and historical reconciliation
- **Description:** Synthetic Pre-Dib entries are inserted into RCLootCouncil
  history, while later reconciliation treats RCLootCouncil history as evidence
  for Dibs accounting.
- **Why it matters:** A reservation, an actual awarded item and a manually
  reconciled historical award can become visually similar without a strict
  provenance boundary.
- **Recommended remediation:** Keep source type, provenance and confidence
  explicit in separate records; never let a synthetic reservation qualify as
  an awarded loot row.
- **Estimated complexity:** Medium

## Code Quality Findings

### QUAL-001 — Duplicated UI utility logic

- **Severity:** P2
- **Files:** src/ui/PlayerUI.lua; src/ui/OfficerUI.lua; src/ui/LogsUI.lua;
  src/ui/DataUI.lua
- **Function/module:** trimming, date formatting, control access and row parsing
- **Description:** Similar helpers are implemented independently across UI
  controllers.
- **Why it matters:** Small behavior differences in normalization, formatting
  or nil handling can create inconsistent player/officer displays.
- **Recommended remediation:** Move pure formatting/identity/table projection
  helpers into a small UI-support module with unit tests.
- **Estimated complexity:** Low

### QUAL-002 — Naming and public namespace compatibility are mixed

- **Severity:** P3
- **Files:** src/Core.lua:17-72; src/modules/CharacterEligibility.lua;
  src/ui/*
- **Function/module:** global namespace and aliases
- **Description:** The addon intentionally exposes both RCLootCouncil_dibs and
  global Dibs, plus the legacy Dibs.Eligibility alias. This helps compatibility
  but increases the number of public mutation surfaces.
- **Why it matters:** Future modules can accidentally depend on an alias or
  expose new mutable state without a clear API policy.
- **Recommended remediation:** Document public versus private APIs, keep aliases
  read-only where possible and add namespace linting.
- **Estimated complexity:** Low

### QUAL-003 — Documentation claims exceed current implementation

- **Severity:** P1
- **Files:** README.md:29,71-72,162-176,228-241;
  docs/developer/sync-protocol.md; src/modules/Sync.lua; src/modules/PreDibs.lua
- **Function/module:** documented multi-raid/shared-settings behavior
- **Description:** README describes multi-raid synchronization and shared
  settings, while implementation still sends manifests through RAID, has no
  mode/config message and does not exchange live ledger transactions.
- **Why it matters:** Guild administrators may assume that two raids share one
  authoritative state when they do not.
- **Recommended remediation:** Mark these capabilities as planned until
  implemented, or update documentation to describe the actual RAID-scoped
  recovery behavior. Add a release gate requiring doc/code parity.
- **Estimated complexity:** Low

### QUAL-004 — Dead or incomplete protocol surface remains public

- **Severity:** P2
- **Files:** src/modules/Sync.lua:249-260,294-351; src/Types.lua:1-169;
  docs/developer/api-reference.md
- **Function/module:** transaction seen markers, snapshots and type aliases
- **Description:** MarkTransactionSeen/HasSeenTransaction are not integrated
  into live transaction or message processing, and snapshot APIs look
  authoritative despite not providing convergence.
- **Why it matters:** Callers may rely on a function that records no effective
  protocol state, or assume an API is safe for distributed writes.
- **Recommended remediation:** Mark experimental APIs clearly, remove or finish
  them, and make the public contract distinguish diagnostics, local import and
  network synchronization.
- **Estimated complexity:** Medium

## Missing Tests

The existing suite is broad, but it is primarily simulated and single-client.
The following tests are required before another implementation phase is
considered complete:

### TEST-001 — Shared configuration revisions

- **Severity:** P1
- **Files:** tests/integration/; missing coverage for src/modules/PreDibs.lua
  and src/modules/Sync.lua
- **Function/module:** guild policy sync
- **Description:** No two-client test proves a mode/settings change travels
  through GUILD/OFFICER transport, applies only at a higher revision, rejects
  same-revision hash conflicts and survives reconnect.
- **Recommended remediation:** Add an in-memory two-client transport harness and
  tests for all revision outcomes.
- **Estimated complexity:** High

### TEST-002 — Multi-raid concurrent writers

- **Severity:** P1
- **Files:** tests/integration/; src/modules/Ledger.lua; src/modules/Sync.lua
- **Function/module:** concurrent award/ledger commit
- **Description:** No test proves that two raids cannot spend the same last Dib
  or that a deterministic conflict/compensation result is produced.
- **Recommended remediation:** Model two writers, delayed delivery, duplicate
  delivery and out-of-order delivery with explicit expected balances.
- **Estimated complexity:** High

### TEST-003 — Transfer assembly and corruption

- **Severity:** P1
- **Files:** tests/integration/predibs_sync_recovery_spec.lua;
  src/modules/Sync.lua
- **Function/module:** fragmented transfer
- **Description:** Existing recovery tests do not prove that chunk content is
  assembled, checksummed and used at transfer end.
- **Recommended remediation:** Add missing chunk, duplicate chunk, reordered
  chunk, altered chunk, wrong sender and wrong final payload cases.
- **Estimated complexity:** Medium

### TEST-004 — Addon-message spoofing and replay

- **Severity:** P1
- **Files:** tests/contract/sync_privacy_spec.lua;
  tests/integration/predibs_sync_recovery_spec.lua
- **Function/module:** sender, guild, rank, nonce and revision validation
- **Description:** Coverage exists for some unauthorized senders, but not for
  same-ID/different-content transactions, replayed valid messages, per-sender
  flooding or stale guild-rank authority.
- **Recommended remediation:** Add a malicious transport fixture and assert that
  no persistent state changes on every rejected case.
- **Estimated complexity:** Medium

### TEST-005 — Ledger invariant and balance policy

- **Severity:** P1
- **Files:** tests/unit/ledger_award_spec.lua;
  tests/integration/finalized_award_flow_spec.lua
- **Function/module:** Use, AppendTransaction, award finalization
- **Description:** Add explicit insufficient-balance, negative-input,
  same-ID/different-content and concurrent-use tests.
- **Recommended remediation:** Assert whether debt is allowed; if not, require
  atomic rejection and unchanged balance.
- **Estimated complexity:** Medium

### TEST-006 — Corrupted, truncated and future SavedVariables

- **Severity:** P1
- **Files:** tests/integration/migration_spec.lua; src/Core.lua
- **Function/module:** ensureDB
- **Description:** Existing migration tests cover supported historical schemas,
  but not wrong-type roots, malformed nested tables, unsupported future schema
  versions or recovery backup behavior.
- **Recommended remediation:** Feed malformed fixtures and assert safe startup,
  quarantine/diagnostic behavior and no silent data loss.
- **Estimated complexity:** Medium

### TEST-007 — Identity edge cases

- **Severity:** P1
- **Files:** tests/unit/permissions_spec.lua; tests/integration/guild_isolation_spec.lua
- **Function/module:** identity and roster resolution
- **Description:** Add same short name on different realms, GUID/name mixtures,
  offline roster, realm names with spaces/hyphens and roster changes during an
  authorization check.
- **Recommended remediation:** Require deterministic identity selection or an
  explicit ambiguous result.
- **Estimated complexity:** Medium

### TEST-008 — Retail combat and protected-frame behavior

- **Severity:** P1
- **Files:** tests/integration/combat_safety_spec.lua;
  src/integrations/RCLootCouncil.lua
- **Function/module:** loot/voting hooks and injected controls
- **Description:** The simulator does not prove live combat behavior of
  CreateFrame, SetScript, button state changes, positioning or
  ScrollingTable refreshes.
- **Recommended remediation:** Run a real Retail matrix with combat during loot
  frame updates, voting updates and late module load.
- **Estimated complexity:** High

### TEST-009 — RCLootCouncil compatibility matrix

- **Severity:** P1
- **Files:** tests/integration/rclootcouncil_*.lua;
  specs/004-rclootcouncil-integration-robust/quickstart.md
- **Function/module:** callback, history, options and module probes
- **Description:** The documented one- and two-client Retail validation tasks
  remain open. No installed-version matrix proves callback signatures,
  statuses, internal module names and history schemas.
- **Recommended remediation:** Record the exact RCLootCouncil version, test
  absent/late/degraded/operational states and keep adapter fixtures per version.
- **Estimated complexity:** High

### TEST-010 — Ace3 unavailable/fallback behavior

- **Severity:** P2
- **Files:** tests/integration/ace3_options_spec.lua; src/integrations/Ace3.lua;
  src/modules/Sync.lua
- **Function/module:** serialization, prefix registration and compact transport
- **Description:** Tests should distinguish “send API did not throw” from
  “receiver got the complete request/manifest”.
- **Recommended remediation:** Add real embedded serializer round-trip and
  fallback transport tests with missing libraries and API failures.
- **Estimated complexity:** Medium

## Recommended Architecture Improvements

1. **Define the authority boundary first.** Keep local inventory and client
   version information advisory. Select either one in-game authoritative
   writer/relay or an optional companion server for guild policy and ledger
   commits.
2. **Create a GuildPolicy service.** Store a versioned, allowlisted snapshot
   containing Pre-Dib mode, rank rules, announcement settings, loot-family
   rules and eligibility policy. Keep presentation settings local.
3. **Create a canonical Identity service.** Prefer GUID, retain full
   Name-Realm, reject ambiguous short names and record identity snapshots at
   transaction time.
4. **Make the ledger event-sourced and convergent.** Use deterministic event
   identity/content hashes, explicit reservation/commit/compensation states,
   atomic balance checks and a documented conflict policy.
5. **Separate transport layers.** Use AceComm/AceSerializer for the in-game
   control plane, a bounded GUILD manifest, WHISPER detail transfer and
   raid-scoped reminder traffic. Do not mix live RCLootCouncil votes with guild
   accounting messages.
6. **Replace internal RCLootCouncil mutation with a narrow adapter.** Prefer
   supported callbacks, treat internal probes as capabilities, never rewrite
   RC history by default and keep Dibs provenance separate.
7. **Add a UI refresh scheduler.** All protected frame changes pass through one
   combat-aware queue; status calculations remain pure and cacheable.
8. **Make persistence defensive.** Validate types and schemas, back up before
   migration/import, rebuild derived indexes and expose a repair/diagnostic
   path.
9. **Use a real two-client harness.** It should model delayed, duplicated,
   reordered, missing and malicious messages without relying only on single
   client stubs.

## Remediation Roadmap

### Phase 0 — Release safety gate

- Decide whether negative balances are allowed; enforce that decision in one
  atomic ledger path.
- Fix identity normalization and guild-roster invalidation.
- Add combat guards around RCLootCouncil UI mutation.
- Stop same-ID/different-content transaction acceptance.
- Correct documentation claims about multi-raid and shared settings.

### Phase 1 — Trust and persistence foundation

- Introduce canonical identity and defensive SavedVariables migration.
- Restrict mutation APIs and return immutable projections.
- Define GuildPolicy schema, revision/hash rules and audit records.
- Define authoritative writer/relay and inventory trust labels.

### Phase 2 — Synchronization

- Implement guild control-plane messages and request-change notifications.
- Add cancellation/terminal tombstones and reconnect recovery.
- Complete transfer assembly/checksum validation.
- Add protocol capabilities, replay windows, throttling and two-client tests.

### Phase 3 — Ledger convergence

- Implement deterministic transaction/event IDs and content hashes.
- Add reservation/commit/conflict/compensation semantics for simultaneous raids.
- Make snapshot/import validation atomic and lossless, or remove ApplySnapshot
  from the authoritative API.

### Phase 4 — RCLootCouncil and Retail validation

- Reduce dependence on internal RC structures.
- Validate callback/status/history behavior against the installed Retail build.
- Run the open one-client and two-client tasks in
  specs/003-raid-predib-modes,
  specs/004-rclootcouncil-integration-robust and
  specs/005-character-loot-eligibility.
- Complete combat, reload, late-load, multi-raid and failure-injection checks.

## Final Priority List

### P0 issues that should be fixed immediately

No P0 issue was assigned from this static audit. No direct evidence of an
unconditional account-level compromise or guaranteed data wipe was found.

### P1 issues that should be fixed before release

- C-001/C-002: shared policy and multi-raid convergence.
- C-003/C-004: distributed ledger commit and incomplete transfer assembly.
- C-005, S-001/S-002/S-003: local authority/identity trust, balance enforcement
  and transaction conflict handling.
- S-004: snapshot provenance and actor handling.
- A-001/A-002: configuration ownership and RCLootCouncil history mutation.
- SYNC-001 through SYNC-004 and SYNC-006: delivery, tombstones, snapshot
  integrity and transport completeness.
- REL-001 through REL-003: persistence recovery, initialization isolation and
  authority freshness.
- WOW-001/WOW-002: combat safety and existing RCLootCouncil handler mutation.
- RC-001/RC-002: adapter internals and award-status compatibility.
- TEST-001 through TEST-009 before enabling the corresponding production paths.

### P2 improvements

- Add replay windows, rate limiting and payload-depth limits.
- Add protocol capability negotiation and a compatibility facade for Retail APIs.
- Cache balance/roster/manifest lookups.
- Replace broad retry watchers with a lifecycle scheduler.
- Improve item-data retry behavior and history cache invalidation.
- Split large modules and centralize repeated UI helpers.
- Add fallback transport tests and defensive diagnostics.

### P3 cleanup/refactoring

- Clarify public/private namespace contracts and legacy aliases.
- Remove or finish unused protocol helpers and clearly label experimental APIs.
- Continue documentation and naming cleanup after the authority/sync design is
  settled.

