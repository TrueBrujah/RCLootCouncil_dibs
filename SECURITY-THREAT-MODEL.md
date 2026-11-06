# RCLootCouncil_dibs — Security Threat Model

**Version:** 1.0
**Date:** 2025-10-26
**Based on commit:** cb3f12a (dev branch)

---

## 1. Assets Requiring Protection

| Asset | Description | Sensitivity | Impact if Compromised |
|-------|-------------|-------------|----------------------|
| **Guild Identity** | Guild name, realm, roster membership | HIGH | Cross-guild data leakage, impersonation |
| **Player Identity** | Canonical Name-Realm, GUID witness, main/alt relationships | HIGH | Identity theft, unauthorized ledger access |
| **Main/Alt Relationships** | Approved character links, probation status | HIGH | Eligibility bypass, unfair loot distribution |
| **Ledger Balances** | Per-player dib counts, seasonal allocations | CRITICAL | Theft of earned dibs, guild trust destruction |
| **Transaction History** | Append-only log of grants, uses, refunds, adjustments | CRITICAL | Audit trail destruction, dispute resolution impossible |
| **DIBS Reservations (Pre-Dibs)** | Player requests for specific items, statuses | HIGH | Reservation hijacking, unfair priority |
| **Governance Records** | GM adoption, policy writer rules, authority epochs | CRITICAL | Governance takeover, policy forgery |
| **Operational Policies** | Module enablement, announcement channels, active ledger | HIGH | Feature bypass, silent policy change |
| **Coordinator Authority** | Active coordinator memberKey, epoch, authority signal | HIGH | Unauthorized ledger commits, sync hijacking |
| **Backup/Recovery Data** | Snapshots, import packages, checksums | HIGH | Data loss, malicious restore, cross-guild contamination |

---

## 2. Attackers (Threat Actors)

| Actor | Capabilities | Motivation | Access Level |
|-------|--------------|------------|--------------|
| **Unauthorized Guild Member** | Addon chat, guild chat, roster visibility | Steal dibs, manipulate eligibility | Guild member, no officer/GM perms |
| **Malicious Officer** | Officer chat, addon comms, ProtectedActions (officer-scoped) | Favor allies, hide corruption | Officer rank per guild config |
| **Compromised GM Client** | Full GM permissions, governance adoption, policy writing | Total control, cover tracks | Guild Master |
| **Client with Modified SavedVariables** | Local DB manipulation, crafted snapshots | Bypass local checks, inject history | Local machine only |
| **Client Using Outdated Addon** | Old protocol, missing validation, stale policy | Exploit fixed vulns, desync | Any guild member |
| **Client Transmitting Malformed Messages** | Arbitrary addon message payloads | Crash clients, bypass validation | Any addon chat participant |
| **Client Replaying Old Messages** | Captured valid envelopes | Replay grants, duplicate reservations | Network observer (same raid) |

---

## 3. Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            WOW CLIENT PROCESS                                │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        ADDON ENVIRONMENT                             │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │    │
│  │  │  Dibs Core   │  │  Dibs UI     │  │  RCLootCouncil Adapter   │  │    │
│  │  │  (trusted)   │  │  (untrusted) │  │  (external dependency)   │  │    │
│  │  └──────┬───────┘  └──────┬───────┘  └────────────┬─────────────┘  │    │
│  │         │                │                         │               │    │
│  │         ▼                ▼                         ▼               │    │
│  │  ┌──────────────────────────────────────────────────────────────┐  │    │
│  │  │                    PROTECTED ACTIONS                          │  │    │
│  │  │  Permissions.Evaluate()  →  ProtectedActions.Execute()       │  │    │
│  │  │  (AUTHORIZATION BOUNDARY — ALL MUTATIONS MUST PASS HERE)     │  │    │
│  │  └──────────────────────────────────────────────────────────────┘  │    │
│  │         │                │                         │               │    │
│  │         ▼                ▼                         ▼               │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │    │
│  │  │  Ledger      │  │  PreDibs     │  │  Sync / SyncV2           │  │    │
│  │  │  (domain)    │  │  (domain)    │  │  (transport)             │  │    │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘  │    │
│  │         │                │                         │               │    │
│  │         └────────────────┼─────────────────────────┘               │    │
│  │                          ▼                                        │    │
│  │  ┌──────────────────────────────────────────────────────────────┐  │    │
│  │  │                    SAVEDVARIABLES                             │  │    │
│  │  │  (UNTRUSTED — USER CAN EDIT; CHECKSUMS DETECT ACCIDENTAL)    │  │    │
│  │  └──────────────────────────────────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         NETWORK (ADDON CHAT CHANNELS)                       │
│  GUILD / OFFICER / RAID / PARTY / WHISPER — NO CRYPTO, NO AUTHENTICATION    │
│  Trust anchor: Guild membership (C_ChatInfo.SendAddonMessage)              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. What the Addon CAN Enforce

| Control | Mechanism | Coverage |
|---------|-----------|----------|
| **Actor identity binding** | `Permissions.CanonicalPlayerId()` + roster freshness | All ProtectedActions |
| **Sender identity binding** | `Sync.canonicalSender()` + `senderIsGuildMember()` | All incoming sync messages |
| **GM authority** | `IsGuildLeader()` + governance adoption record | Policy changes, module management |
| **Officer permissions** | Configurable rank indices + `Permissions.GetGuildRole()` | Ledger adjustments, sync, disputes |
| **Main/alt ownership** | `CharacterEligibility` review workflow + `Identity.ResolveRosterMember()` | Eligibility evaluation |
| **Relationship approval** | Explicit GM/officer review, audit log | No auto-inference |
| **Unauthorized ledger changes** | `ProtectedActions` gate → `Permissions.Evaluate()` | All ledger mutations |
| **Unknown action IDs** | `ProtectedActions.isValidAction()` whitelist → reject | All `Execute()` calls |
| **Privilege escalation** | `Permissions.EvaluateStandalone()` only allows GM/officer | Standalone mode |
| **Cross-guild isolation** | `Dibs.currentGuildKey` scope on all DB operations | All modules |

---

## 5. What the Addon CANNOT Guarantee (Fully Compromised Client)

| Guarantee | Why Not Possible | Mitigation |
|-----------|------------------|------------|
| **Client-side code integrity** | User controls Lua environment, can hook/override any function | Server-side validation not available in WoW addon model |
| **SavedVariables authenticity** | Local file editable by user; checksums only detect accidental corruption | Preview-before-apply, audit logs, sync reconciliation |
| **Message authenticity** | No PKI; addon messages can be forged by any client in channel | Guild membership check, sequence/epoch validation, duplicate detection |
| **RCLootCouncil data integrity** | RC is external addon; Dibs only reads public APIs | Fail closed on version mismatch, no writes to RC data |
| **Time/sequence integrity** | `time()` and sequence numbers are client-local | Epoch/authority validation, coordinator election |
| **UI enforcement** | User can disable UI, call APIs directly | `ProtectedActions` is the *only* mutation path in production code |

---

## 6. Attack Surface by Module

### Identity.lua (Roster Boundary)
- **Entry points:** `RefreshRoster()`, `ResolveRosterMember()`, `CreateSnapshot()`
- **Attack:** Stale roster → wrong memberKey → wrong identity
- **Defense:** Generation counter, `fresh` flag, invalidation on GUILD_ROSTER_UPDATE

### Permissions.lua (Authorization Core)
- **Entry points:** `Evaluate()`, `EvaluateStandalone()`, `CanonicalPlayerId()`, `CanManageDibs()`
- **Attack:** Unknown actionId bypass, actor spoofing, standalone mode abuse
- **Defense:** Whitelist in `ProtectedActions.VALID_ACTIONS`, `isCurrentActor()` check, GM/officer only in standalone

### Sync.lua / SyncV2.lua (Transport)
- **Entry points:** `Receive()`, `Send()`, `OnAddonMessage()`
- **Attack:** Malformed envelopes, replay, sender spoofing, protocol downgrade
- **Defense:** `MESSAGE_TYPES` whitelist, `validGuildEnvelope()`, `senderIsGuildAdmin()`, sequence/epoch, `seenTransactions`

### Ledger.lua (Append-Only Store)
- **Entry points:** `Grant()`, `Use()`, `Refund()`, `AdminAdjust()`, `RegisterSeasonAllocation()`
- **Attack:** Negative balance, duplicate transaction, forged evidence, replay
- **Defense:** Canonical classification, content hash, `reconciliation` snapshot, duplicate detection via `evidenceId`/`awardRef`

### Governance.lua (Bootstrap)
- **Entry points:** `Propose()`, `Adopt()`, `GetState()`, `GetCurrentRecord()`
- **Attack:** Forged governance record, parent hash collision, orphan proposal
- **Defense:** `GENESIS_HASH`, parent hash chaining, GM-only adoption, content hash verification

### OperationalPolicy.lua (Policy Gate)
- **Entry points:** `Change()`, `AdoptInitial()`, `SetModuleEnabled()`, `CanWrite()`
- **Attack:** Policy forgery, bypass module requirements, unauthorized ledger switch
- **Defense:** Governance adoption prerequisite, `CanWrite()` check, `RequireModuleEnabled()` gate

### FeatureRegistry.lua (Feature Flag)
- **Entry points:** `IsEnabled()`, `RequireEnabled()`, `GetEffectiveState()`
- **Attack:** Disable core features, bypass disabled feature, unknown feature pass
- **Defense:** Core modules `alwaysEnabled=true`, `UNKNOWN_FEATURE` fails closed, dependency resolution

### ProtectedActions.lua (Mutation Gate)
- **Entry points:** `Execute(actionId, actor, payload)`
- **Attack:** Invalid actionId, combat lockdown bypass, sandbox escape
- **Defense:** `isValidAction()` whitelist, `InCombatLockdown()` check, `DeveloperSandbox` rejection

### Backup.lua / ImportExport.lua (Persistence)
- **Entry points:** `Create()`, `PreviewRestore()`, `Restore()`, `Encode()`, `Decode()`, `Apply()`
- **Attack:** Cross-guild restore, partial apply, checksum bypass, oversized package
- **Defense:** Scope validation, preview mandatory, `MAX_PACKAGE_SIZE`, depth/node limits, checksums

---

## 7. Data Flow Security Classification

| Flow | Direction | Classification | Validation |
|------|-----------|----------------|------------|
| Guild Roster → Identity | Inbound (WoW API) | TRUSTED SOURCE | Freshness generation |
| Addon Message → Sync | Inbound (Network) | UNTRUSTED | Envelope validation, sender auth, guild membership |
| ProtectedActions → Ledger | Internal | AUTHORIZED | `Permissions.Evaluate()` decision |
| Governance → OperationalPolicy | Internal | AUTHORIZED | GM signature, parent hash |
| OperationalPolicy → FeatureRegistry | Internal | AUTHORIZED | Policy revision, `CanWrite()` |
| Backup/Import → SavedVariables | Inbound (File) | UNTRUSTED | Preview, checksum, scope validation |
| RCLootCouncil Events → Adapter | Inbound (External) | ADVISORY | Version check, fail closed |

---

## 8. Critical Attack Paths

### Path 1: Negative Balance Creation (SA-001)
```
Officer calls Dibs.Ledger.Use(player, 100) directly
    → Bypasses ProtectedActions.Execute()
    → Bypasses Permissions.Evaluate()
    → Ledger.Use() only checks amount > 0
    → Player balance goes negative
    → Eligibility calculations break
```

### Path 2: Unauthorized Ledger Mutation (SA-002)
```
Any addon/script calls Dibs.Ledger.Grant(player, 50, "fake reason")
    → No authorization check in Ledger.Grant()
    → Transaction appended with CLASSIFICATION=LOCAL_CANONICAL
    → Sync propagates to guild (officer sends manifest)
    → Other clients accept via normal sync path
```

### Path 3: Sync Protocol Downgrade (SA-004)
```
Attacker runs old addon version (protocol v1)
    → Sends HELLO with protocol=1
    → Current clients (protocol v2) reject exact-match
    → Guild sync completely disabled
    → No negotiation, no graceful degradation
```

### Path 4: Partial Import Corruption (SA-010)
```
Officer imports crafted package
    → ImportExport.Apply() processes incrementally
    → Ledger transactions applied first
    → Policy/identity applied later
    → Failure halfway leaves inconsistent state
    → No rollback, no atomic commit
```

---

## 9. Security Invariants (Must Hold)

| Invariant | Module | Test |
|-----------|--------|------|
| **I-001** No mutation without `Permissions.Evaluate().allowed == true` | ProtectedActions | Unit: call `Execute()` with invalid action/actor |
| **I-002** Unknown actionId always rejected | ProtectedActions | Unit: `Execute("invalid.action", ...)` → `INVALID_ACTION` |
| **I-003** Ledger balance never negative (unless policy allows) | Ledger | Integration: `Use()` exceeding balance → reject |
| **I-004** Sync message from non-guild-member rejected | Sync/SyncV2 | Integration: `Receive()` with outsider sender → false |
| **I-005** Governance record requires GM adoption | Governance | Unit: `Adopt()` by non-GM → reject |
| **I-006** Core modules cannot be disabled | FeatureRegistry | Unit: `RequireEnabled("ledger")` → always true |
| **I-007** Import never applies without explicit confirmation | ImportExport | Integration: `Apply(previewId, false)` → no changes |
| **I-008** Developer sandbox rejects all production actions | ProtectedActions | Unit: `Execute()` in sandbox → `MIXED_PROVIDER_REJECTED` |
| **I-009** Cross-guild data never mixed | All (via `currentGuildKey`) | Integration: two guild DBs, operations scoped |

---

## 10. Recommended Architecture Improvements

1. **Unified Policy Service** — Single owner for `db.settings` with revision, audit, sync (addresses SA-006)
2. **Private Mutators** — `Ledger.*` and `PreDibs.*` mutation functions made local; only `ProtectedActions` calls them (addresses SA-002)
3. **Atomic Import** — Validate entire snapshot to temp tables, detect conflicts, single commit (addresses SA-010)
4. **Protocol Negotiation** — HELLO includes min/max supported versions, feature caps (addresses SA-004)
5. **Balance Enforcement** — `Ledger.Use()` checks `GetPlayerDibsProjection().available >= amount` (addresses SA-001)
6. **Complete Compact Fallback** — Either require AceComm or implement full bounded fallback with prefix registration (addresses SA-003)

---

**Document Owner:** Security Audit Team
**Review Cycle:** Per release candidate
**Classification:** Internal — Developer Reference