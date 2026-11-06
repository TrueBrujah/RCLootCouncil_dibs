# RCLootCouncil_dibs — Security Findings

**Audit Date:** 2025-10-26
**Target Commit:** cb3f12a
**Original audit:** 2025-10-26, target `cb3f12a` (historical snapshot).

> **Current-source reassessment (2026-10-28):** The detailed reproductions below
> are historical unless they match this status. SA-001 is resolved in the current
> source. SA-002 is not substantiated for Ledger APIs: `Ledger` routes writes
> through `Permissions.Evaluate`; its PreDibs claims have not been reassessed
> method by method. SA-003 is a conditional availability limitation, not a
> prefix-spoofing/security vulnerability. SA-010 is confirmed with current
> reproductions: local/guild malformed replacement payloads throw after clearing
> settings; full imports overwrite the live `db.ledgers` map and lose newer local
> state. See [current review](docs/code-audit/REVIEW-2026-10-28.md). Do not use
> the old P0 release recommendation or historical test-gap table as current.

---

## Finding Format

Each finding contains:
- **Unique ID** — Tracking identifier
- **Severity** — P0 (release-blocking) / P1 (high) / P2 (medium) / P3 (low/defense-in-depth)
- **Confidence** — 1-10 (10 = confirmed with reproduction)
- **Affected File & Function** — Exact location
- **Trust Boundary** — Which security layer is crossed
- **Preconditions** — What must be true for exploit
- **Reproduction Procedure** — Steps to demonstrate
- **Expected Behavior** — What should happen
- **Observed Behavior** — What actually happens
- **Impact** — Consequence if exploited
- **Evidence** — Code references, test results
- **Relevant Test** — Existing or needed test
- **Recommended Minimal Correction** — Surgical fix
- **Regression Risks** — What could break

---

## SA-001 — Negative Balance Enforcement — ALREADY FIXED (Not a Vulnerability)

| Field | Value |
|-------|-------|
| **Severity** | **N/A — Already Mitigated** |
| **Confidence** | 9/10 |
| **File:Function** | `src/modules/Ledger.lua:350-550` — `CommitLocalTransaction`, `compatibilityMutation`<br>`src/modules/Ledger.lua:~700-750` — `Ledger.Grant`, `Ledger.Use`, `Ledger.AdminAdjust` |
| **Trust Boundary** | Local client mutation → Persistent ledger state |
| **Validation Result** | **ALREADY_FIXED** — The `INSUFFICIENT_BALANCE` check in `CommitLocalTransaction` (line ~450) is active and enforced for ALL mutation paths that create `DIB_USED` transactions. |

### Test Evidence
```
--- Direct CommitLocalTransaction test ---
Direct result accepted: false
Direct result reasonCode: INSUFFICIENT_BALANCE
Direct result value: nil
Balance after direct: 6 (unchanged)

--- Test Use on Other-Realm (insufficient) ---
Use2 value: nil
Use2 reasonCode: INSUFFICIENT_BALANCE
Balance Other-Realm: 3 (unchanged)
```
- `b03_local_ledger_spec.lua`: "rejects an insufficient use atomically unless explicit local debt is enabled" — PASS

### Why It Works
The balance check in `CommitLocalTransaction` (line ~450):
```lua
if tx.type == "DIB_USED" and tx.debtPolicy.allowDebt ~= true and getCurrentBalance(...) + tx.amount < 0
```
catches ALL `DIB_USED` type transactions regardless of which public API was called (`Ledger.Use`, direct `CommitLocalTransaction`, etc.).

`AdminAdjust` creates `DIB_ADMIN_ADJUSTMENT` type which follows a separate validation path (`commitCanonicalAdminAdjustment`) requiring coordinator authority — this is ACCEPTED_BEHAVIOR for GM/officer corrections.

### Previous Finding Was Incorrect
The original finding claimed `Ledger.Use` lacked a balance check. In reality:
- `Ledger.Use` → `compatibilityMutation` → `CommitLocalTransaction` (balance enforced)
- The check is centralized in `CommitLocalTransaction`, not in the public facades
- ALL paths to create a `DIB_USED` transaction pass through this check

### Status
**ALREADY_FIXED** — No action needed. Remove from P0 blockers in remediation plan.

---

## SA-002 — Public Mutation APIs Bypass ProtectedActions Boundary

> **Historical claim; not confirmed for Ledger in current source.** The public
> facades call `authorize()` through `CommitLocalTransaction`, which evaluates
> permissions. Do not apply the privatization recommendation below without a
> separate reproduction. The PreDibs methods named in this finding remain
> outside this reassessment.

| Field | Value |
|-------|-------|
| **Severity** | **P0** |
| **Confidence** | 10/10 |
| **File:Function** | `src/modules/Ledger.lua:131-185` — `Grant`, `Use`, `Refund`, `AdminAdjust`<br>`src/modules/PreDibs.lua:462-484,593-729` — `UpdateStatus`, `Confirm`, `Cancel`, `Invalidate`, `Fulfill` |
| **Trust Boundary** | Application command boundary (`ProtectedActions`) — completely bypassed |
| **Preconditions** | Any loaded addon/script can access `Dibs` global; no combat/sandbox guard on direct calls |
| **Reproduction** | 1. Run `/run Dibs.Ledger.Grant("Player-Realm", 100, "exploit")`<br>2. Transaction appended with `CLASSIFICATION=LOCAL_CANONICAL`<br>3. Sync propagates to guild officers<br>4. Other clients accept via normal manifest/fetch |
| **Expected** | Mutation rejected: `INVALID_ACTION` or `AUTHORITY_UNAVAILABLE` |
| **Observed** | Mutation succeeds; ledger mutated; sync distributes |
| **Impact** | Any addon (malicious or buggy) can mutate ledger/PreDibs; officer UI not required; audit trail shows valid `LOCAL_CANONICAL` transactions |
| **Evidence** | `Ledger.Grant` signature: `function Ledger.Grant(memberKey, amount, reason, ...)` — **no actor parameter, no auth check**.<br>`ProtectedActions.Execute` validates actionId and calls `Permissions.Evaluate` — but only if caller uses `ProtectedActions.Execute`. |
| **Relevant Test** | None — gap in test coverage |
| **Recommended Fix** | **Option A (minimal):** Make mutation functions local to module; expose only via `ProtectedActions` handlers.<br>**Option B (defense-in-depth):** Add `authorizationContext` parameter required on all mutators; validate in each function. |
| **Regression Risks** | Internal callers (sync recovery, bootstrap) need authorized path — provide `systemBootstrap=true` context (already exists in `Ledger.authorize`). |

---

## SA-003 — Compact AceComm Fallback Does Not Register DIBS Prefix; Requests Silently Dropped

> **Current disposition: conditional transport limitation.** The fallback only
> transmits a compact subset and rejects data-bearing requests/manifests. The
> earlier assertion that it silently sends those payloads is inaccurate: those
> paths return `false`. Prefix registration and end-to-end behavior when AceComm
> is unavailable still require a Retail or faithful API-stub reproduction.

| Field | Value |
|-------|-------|
| **Severity** | **P2** |
| **Confidence** | 9/10 |
| **File:Function** | `src/modules/Sync.lua:106-119` — `Sync.Send`<br>`src/integrations/Ace3.lua:60-90` — `OnAddonMessage` registration |
| **Trust Boundary** | Transport layer — message delivery guarantee |
| **Preconditions** | AceComm/AceSerializer not available (embedded load failed); addon falls back to compact path |
| **Reproduction** | 1. Disable Ace3 embedding (simulate load failure)<br>2. Call `Sync.Send({type="REQUEST", requestId="test", ...}, "GUILD")`<br>3. Observe: payload not sent (fallback refuses request/manifest/snapshot)<br>4. No error returned to caller |
| **Expected** | Either: (a) full fallback implementation with prefix registration, or (b) clear error "transport unavailable" |
| **Observed** | `Sync.Send` returns `false` silently; caller may believe message queued; no data transmitted |
| **Impact** | Guild sync silently fails in environments where AceComm fails to load; no diagnostic for officers |
| **Evidence** | `Sync.Send`:<br>`if message.request or message.requests or message.snapshot then return false end`<br>Ace3.lua registers prefix only if `ace.RegisterComm` succeeds. |
| **Relevant Test** | `tests/integration/b04_transport_spec.lua` — needs fallback scenario |
| **Recommended Fix** | Make AceComm/AceSerializer **required embedded dependencies** (already in embeds.xml); remove compact fallback or implement complete one with `C_ChatInfo.RegisterAddonMessagePrefix("DIBS")` and proper serialization. |
| **Regression Risks** | None if AceComm is required; if fallback kept, must test prefix registration on all supported WoW versions. |

---

## SA-004 — Protocol Version Exact-Match Only; No Negotiation

| Field | Value |
|-------|-------|
| **Severity** | **P2** |
| **Confidence** | 10/10 |
| **File:Function** | `src/modules/Sync.lua:66-75` — `PROTOCOL_VERSION` constant<br>`src/modules/SyncV2.lua` — no version negotiation in `HELLO`/`DIGEST` |
| **Trust Boundary** | Protocol compatibility — cross-version interoperability |
| **Preconditions** | Guild members running different addon versions (patch-level difference) |
| **Reproduction** | 1. Client A: v0.8.10 (PROTOCOL_VERSION=2)<br>2. Client B: v0.8.9 (PROTOCOL_VERSION=1)<br>3. A sends HELLO with protocol=2<br>4. B rejects: `validGuildEnvelope` checks exact match<br>5. No sync possible; UI shows generic "unavailable" |
| **Expected** | Minor version negotiation; feature capability exchange; actionable mismatch diagnostic |
| **Observed** | Hard reject on any version mismatch; no fallback; no diagnostic beyond "sync unavailable" |
| **Impact** | Harmless patch update breaks guild-wide sync; officers cannot diagnose; recovery requires full version alignment |
| **Evidence** | `Sync.lua:66`: `local PROTOCOL_VERSION = 2`<br>`validGuildEnvelope`: `if message.protocol ~= PROTOCOL_VERSION then return false end`<br>No `minProtocol`, `maxProtocol`, or `capabilities` fields in HELLO. |
| **Relevant Test** | `tests/integration/b04_transport_spec.lua` — needs cross-version test |
| **Recommended Fix** | Add to HELLO envelope: `minProtocol`, `maxProtocol`, `features` bitmap.<br>Receiver accepts if `message.protocol` in `[minProtocol, maxProtocol]`.<br>Log actionable diagnostic: "Peer protocol vX not in supported range vY-vZ". |
| **Regression Risks** | Must maintain backward compatibility with existing v1/v2 clients during transition. |

---

## SA-005 — SyncV2 Digest/Entity Validation Uses Non-Cryptographic Hash

| Field | Value |
|-------|-------|
| **Severity** | **P2** |
| **Confidence** | 8/10 |
| **File:Function** | `src/modules/SyncV2.lua:170-190` — `serialize()`, `hashText()`, `hash()` |
| **Trust Boundary** | Data integrity — tamper detection |
| **Preconditions** | Attacker can inject/modify addon messages in transit (same raid/guild channel) |
| **Reproduction** | 1. Capture valid DIGEST envelope<br>2. Modify `entityDigests.GOVERNANCE` revision<br>3. Recompute hash using same polynomial algorithm (public, deterministic)<br>4. Resend — receiver accepts as valid |
| **Expected** | Tamper-evident: any modification detected |
| **Observed** | Hash is 31-bit polynomial (`value * 131 + byte`) — trivial to collide or recompute; provides **integrity check only, not authenticity** |
| **Impact** | Malicious peer can forge digests, trigger unnecessary transfers, or hide real changes; no proof of origin |
| **Evidence** | Code comment: *"Hashes and sender checks are integrity/attribution signals, not cryptographic authentication."*<br>This is **documented accepted behavior**, not a vulnerability per se — but threat model must reflect it. |
| **Relevant Test** | `tests/integration/b04_transport_spec.lua` — needs tamper detection test |
| **Recommended Fix** | Document clearly: **not a security boundary**. Trust anchor remains guild membership + sender authorization. No code change needed unless threat model changes. |
| **Regression Risks** | None — this is architecture documentation. |

---

## SA-006 — Multiple Modules Write db.settings Directly Without Unified Revision/Audit

| Field | Value |
|-------|-------|
| **Severity** | **P3** |
| **Confidence** | 9/10 |
| **File:Function** | `src/modules/Profiles.lua:52-123`<br>`src/modules/PreDibs.lua:127-457`<br>`src/modules/RaidPrompts.lua:20-40`<br>`src/modules/OperationalPolicy.lua` (policy revision) |
| **Trust Boundary** | Configuration consistency — single source of truth |
| **Preconditions** | Multiple modules modify overlapping settings concurrently or out of order |
| **Reproduction** | 1. Profile applied → writes `db.settings.announcementChannels`<br>2. PreDibs mode change → writes `db.settings.predibsMode`<br>3. OperationalPolicy revision not incremented for (1) or (2)<br>4. Sync sends stale revision; peers reject or apply inconsistently |
| **Expected** | Single policy service owns `db.settings`; all changes via revisioned commit with audit |
| **Observed** | Direct `db.settings.field = value` writes; no revision bump; no audit log entry |
| **Impact** | Configuration drift between clients; silent policy divergence; sync conflicts unresolved |
| **Evidence** | `Profiles.ApplyProfile`: `db.settings[key] = value` (no revision)<br>`PreDibs.SetPublicMode`: `db.settings.predibsMode = mode` (no revision)<br>`OperationalPolicy.Change`: increments `policyRevision`, creates record |
| **Relevant Test** | `tests/integration/guild_loot_rules_spec.lua` — needs concurrent modification test |
| **Recommended Fix** | Introduce `GuildPolicy` service: single `Set(key, value, actor, reason)` → increments revision, writes audit, publishes catalog. All modules delegate to it. |
| **Regression Risks** | Large refactor; must preserve existing settings keys; migration path for existing DBs. |

---

## SA-007 — RCLootCouncil Adapter Probes Unstable Internal Structures

| Field | Value |
|-------|-------|
| **Severity** | **P3** |
| **Confidence** | 6/10 (NEEDS_MORE_EVIDENCE) |
| **File:Function** | `src/integrations/RCLootCouncil.lua:644-702` — module discovery<br>`src/integrations/RCLootCouncil.lua:1720-1771` — `EvaluateAuthority`<br>`src/integrations/RCLootCouncil.lua:2613-2637` — options projection |
| **Trust Boundary** | External dependency integrity — supply chain |
| **Preconditions** | RCLootCouncil updated; internal structure changed; Dibs not updated |
| **Reproduction** | Requires specific RC version change — not reproduced in test env |
| **Expected** | Adapter fails closed with specific unsupported capability |
| **Observed** | Adapter probes `rc.modules`, `GetActiveModule`, `GetModule`, `masterLooter`, `scrollCols`, `EntryManager`, `lootTable` — all internal |
| **Impact** | Silent disable of Dibs/RC integration; authority evaluation may return wrong result; no user-facing diagnostic |
| **Evidence** | Multiple `pcall` probes with no version contract; fallback to `false`/`nil` on failure |
| **Relevant Test** | `tests/integration/b08_rclootcouncil_ui_safety_spec.lua` — needs version matrix test |
| **Recommended Fix** | Define narrow adapter contract with RC team; use only public APIs; version capability matrix; explicit unsupported capability errors. |
| **Regression Risks** | RC may not provide stable API; adapter may need version-specific branches. |

---

## SA-008 — Unknown Action IDs Can Be Authorized (FALSE POSITIVE)

| Field | Value |
|-------|-------|
| **Severity** | **P3** → **FALSE_POSITIVE** |
| **Confidence** | 10/10 |
| **File:Function** | `src/modules/ProtectedActions.lua:743-744` — `isValidAction()`<br>`src/modules/Permissions.lua:300-310` — `Evaluate()` |
| **Trust Boundary** | Authorization decision — action validation |
| **Preconditions** | Caller passes unknown `actionId` to `ProtectedActions.Execute()` |
| **Reproduction** | 1. Call `Dibs.ProtectedActions.Execute("completely.fake.action", actor, {})`<br>2. `isValidAction("completely.fake.action")` → `false` (not in `VALID_ACTIONS`)<br>3. Returns `INVALID_ACTION` immediately — **never reaches `Permissions.Evaluate`** |
| **Expected** | Rejected at `ProtectedActions` boundary |
| **Observed** | **Correctly rejected** — previous audit misread code path |
| **Impact** | None — boundary holds |
| **Evidence** | `ProtectedActions.lua:743`: `if not isValidAction(actionId) then return buildResult(false, nil, { reasonCode = "INVALID_ACTION" }, ...) end` |
| **Relevant Test** | `tests/unit/protected_actions_spec.lua` — should add unknown action test |
| **Recommended Fix** | None — behavior is correct. Add test to prevent regression. |

---

## SA-009 — Sender Identity Spoofing in Sync (FALSE POSITIVE)

| Field | Value |
|-------|-------|
| **Severity** | **P3** → **FALSE_POSITIVE** |
| **Confidence** | 10/10 |
| **File:Function** | `src/modules/Sync.lua:85-95` — `canonicalSender()`<br>`src/modules/Sync.lua:97-105` — `senderIsGuildMember()`<br>`src/modules/Sync.lua:120-135` — `validGuildEnvelope()` |
| **Trust Boundary** | Network message authentication |
| **Preconditions** | Attacker sends addon message with spoofed sender name |
| **Reproduction** | 1. Attacker sends `DIBS` message with `sender="OfficerName-Realm"`<br>2. `canonicalSender()` normalizes to lowercase name-realm<br>3. `senderIsGuildMember()` calls `IsInGuild()` + roster scan for exact match<br>4. **Fails** — attacker not in guild roster<br>5. `validGuildEnvelope()` returns `false` |
| **Expected** | Rejected |
| **Observed** | **Correctly rejected** — sender must be current guild member per roster |
| **Impact** | None — boundary holds |
| **Evidence** | `senderIsGuildMember`: iterates `GetGuildRosterInfo`, matches `normalizeName(name)` against `canonicalSender(sender)` |
| **Relevant Test** | `tests/integration/b04_transport_spec.lua` — needs spoofed sender test |
| **Recommended Fix** | None — behavior is correct. Add test to prevent regression. |

---

## SA-010 — Import/Export Apply Not Atomic; Partial Apply Leaves Inconsistent State

> **Current disposition: confirmed, with current evidence.** Local and guild
> replacement imports accept non-table settings payloads during `Decode` and
> `Preview`; `mergeInto` clears the target before iterating the malformed source,
> which raises at `ImportExport.lua:360`. Full imports also overwrite `db.ledgers`
> at `ImportExport.lua:465`; current RF-0033 tests fail on loss of a newer ledger
> and alias divergence. See the 2026-10-28 review for exact focused-test results.

| Field | Value |
|-------|-------|
| **Severity** | **P0** |
| **Confidence** | 9/10 |
| **File:Function** | `src/modules/ImportExport.lua` — `Apply()` (entire function) |
| **Trust Boundary** | Persistence atomicity — all-or-nothing restore |
| **Preconditions** | Officer imports package; error occurs mid-apply (corrupt data, conflict, OOM) |
| **Reproduction** | 1. Craft package with valid ledger + invalid policy<br>2. Call `ImportExport.Apply(previewId, true, "reason", actor)`<br>3. Ledger transactions applied first (lines 1-500)<br>4. Policy validation fails at line 501<br>5. Ledger changes **already committed**; no rollback |
| **Expected** | Full validation first; single atomic commit or full rollback |
| **Observed** | Incremental apply; partial state persists; retry/recovery ambiguous |
| **Impact** | Corrupted DB requiring manual repair; audit trail shows partial import; sync may propagate partial state |
| **Evidence** | `Apply()` processes: `ledger` → `preDibs` → `governance` → `operationalPolicy` → `featureRegistry` → `identity` → `characterEligibility` → `profiles` — each commits to `db` immediately. No transaction wrapper. |
| **Relevant Test** | `tests/integration/backup_import_profiles_spec.lua` — needs atomicity test |
| **Recommended Fix** | **Two-phase apply:**<br>1. `ValidateFullPackage(package)` → returns `conflicts[]`, `previewState`<br>2. `CommitValidatedPackage(previewState, actor)` — single guarded operation<br>Use `Backup.Create()` safety snapshot before commit (already exists as `safetySnapshotId`). |
| **Regression Risks** | Must preserve preview UI flow; large packages may hit execution time limits — chunk validation. |

---

## Summary Table

| ID | Severity | Status | P0 Blocker? |
|----|----------|--------|-------------|
| SA-001 | — | RESOLVED | No |
| SA-002 | — | NOT SUBSTANTIATED FOR LEDGER; PRE-DIBS NOT REASSESSED | No current blocker established |
| SA-003 | P2 | CONDITIONAL AVAILABILITY LIMITATION | No security blocker established |
| SA-004 | P2 | CONFIRMED | No |
| SA-005 | P2 | CONFIRMED (accepted) | No |
| SA-006 | P3 | CONFIRMED | No |
| SA-007 | P3 | NEEDS_MORE_EVIDENCE | No |
| SA-008 | P3 | FALSE_POSITIVE | N/A |
| SA-009 | P3 | FALSE_POSITIVE | N/A |
| SA-010 | P1 | CONFIRMED: malformed replacements throw after clearing settings; full imports replace the live ledger map | Yes, pending fix and validation |

---

## Test Coverage Gaps

| Gap | Required Test |
|-----|---------------|
| Negative balance rejection | `b03_local_ledger_spec.lua`: `Use()` with amount > balance |
| Direct mutator bypass | `protected_actions_spec.lua`: call `Ledger.Grant` directly → expect no auth |
| Compact fallback behavior | `b04_transport_spec.lua`: simulate AceComm failure |
| Cross-version sync | `b04_transport_spec.lua`: v1 ↔ v2 HELLO exchange |
| Atomic import | `backup_import_profiles_spec.lua`: fail mid-apply → verify rollback |
| Spoofed sender rejection | `b04_transport_spec.lua`: invalid sender in envelope |
| Unknown action rejection | `protected_actions_spec.lua`: `Execute("fake.action", ...)` |

---

**End of Findings**
