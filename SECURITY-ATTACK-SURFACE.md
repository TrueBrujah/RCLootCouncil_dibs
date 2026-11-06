# RCLootCouncil_dibs — Security Attack Surface

**Version:** 1.0
**Date:** 2025-10-26
**Commit:** cb3f12a

---

## 1. External Attack Surface (Network)

### 1.1 Addon Message Channels
| Channel | Prefix | Direction | Validation |
|---------|--------|-----------|------------|
| GUILD | `DIBS` | Bidirectional | `validGuildEnvelope()`, `senderIsGuildMember()`, `senderIsGuildAdmin()` |
| OFFICER | `DIBS` | Bidirectional | Same as GUILD + officer rank check |
| RAID | `DIBS` | Bidirectional | Same as GUILD |
| PARTY | `DIBS` | Bidirectional | Same as GUILD |
| WHISPER | `DIBS` | Inbound only | Rejected unless `senderIsGuildAdmin()` |

**Total message types:** 23 (see `Sync.MESSAGE_TYPES`)

### 1.2 Message Type Attack Surface
| Type | Payload Complexity | Trust Level | Validation |
|------|-------------------|-------------|------------|
| HELLO | Low (version, capabilities) | MEDIUM | Exact protocol match; no negotiation |
| DIGEST | Medium (entity hashes) | MEDIUM | Polynomial hash; no authenticity |
| REQUEST | High (entity, revision, filters) | HIGH | Sender auth; revision bounds |
| MANIFEST | High (transaction headers) | HIGH | Sender auth; sequence continuity |
| SNAPSHOT | Critical (full entity data) | CRITICAL | Sender auth; checksum; scope validation |
| TRANSACTION | Critical (single entry) | CRITICAL | Canonical classification; duplicate check |
| EVIDENCE | High (award references) | HIGH | RC event validation; stable ID required |

### 1.3 Network Attack Vectors
| Vector | Feasibility | Impact | Mitigation |
|--------|-------------|--------|------------|
| Message replay | MEDIUM | Duplicate transactions | Sequence numbers, `seenTransactions` set, epoch validation |
| Sender spoofing | LOW | Unauthorized mutations | Roster membership check; canonical name-realm |
| Malformed envelope | HIGH | Client crash/DoS | `validGuildEnvelope` whitelist; pcall on decode |
| Protocol downgrade | MEDIUM | Sync denial | Exact version match (no negotiation — SA-004) |
| Oversized payload | LOW | Memory pressure | `MAX_PACKAGE_SIZE` (250KB); depth/node limits in ImportExport |
| Channel confusion | LOW | Policy bypass | Channel validated per message type |

---

## 2. Internal Attack Surface (API)

### 2.1 Public Mutation APIs (SA-002)
| Module | Functions | Auth Required | Risk |
|--------|-----------|---------------|------|
| `Dibs.Ledger` | `Grant`, `Use`, `Refund`, `AdminAdjust`, `RegisterSeasonAllocation` | **NONE** | **CRITICAL** — direct ledger mutation |
| `Dibs.PreDibs` | `UpdateStatus`, `Confirm`, `Cancel`, `Invalidate`, `Fulfill`, `CancelForPlayer` | `CancelForPlayer` only | **HIGH** — reservation state mutation |
| `Dibs.MultiLedger` | `CreateLedger`, `SetGuildActiveLedger`, `ApproveLedger` | Via `ProtectedActions` | MEDIUM — gateway guarded |

### 2.2 Read APIs Returning Mutable References
| Module | Function | Returns | Risk |
|--------|----------|---------|------|
| `Dibs.Ledger` | `GetTransaction`, `GetLedger` | Direct table ref | Caller can mutate SavedVariables |
| `Dibs.PreDibs` | `GetRequest`, `GetRequests` | Direct table ref | Same |
| `Dibs.Governance` | `GetCurrentRecord`, `GetProposal` | Direct table ref | Same |
| `Dibs.OperationalPolicy` | `GetState`, `GetModuleStatus` | Copy (mostly) | LOW |

### 2.3 ProtectedActions Gate (Primary Mutation Boundary)
| Entry Point | Validation Chain |
|-------------|------------------|
| `Dibs.ProtectedActions.Execute(actionId, actor, payload)` | 1. `isValidAction(actionId)` — whitelist<br>2. `Permissions.Evaluate(actionId, actor)` — auth decision<br>3. Handler dispatch — domain logic |

**Action whitelist:** 28 actions (see `ProtectedActions.VALID_ACTIONS`)

### 2.4 Permissions Evaluation Surface
| Function | Input | Output | Trust Level |
|----------|-------|--------|-------------|
| `Permissions.Evaluate(actionId, actor)` | actionId, actor name | `{allowed, authority, reasonCode}` | **AUTHORITATIVE** |
| `Permissions.EvaluateStandalone(actionId, actor)` | actionId, actor name | `{allowed, authority, reasonCode}` | GM/officer only |
| `Permissions.CanonicalPlayerId(actor)` | actor name | memberKey or nil | IDENTITY BOUNDARY |
| `Permissions.CanManageDibs(actor)` | actor name | boolean | OFFICER/GM |
| `Permissions.GetGuildRole(actor)` | actor name | "gm" / "officer" / "member" / nil | ROSTER-BOUND |

---

## 3. Persistence Attack Surface (SavedVariables)

### 3.1 Database Structure
```
RCLootCouncil_dibsDB (guild-scoped)
├── ledgers[ledgerId]           -- CRITICAL: append-only, canonical
├── activeLedgerId              -- HIGH: determines active partition
├── governance                  -- CRITICAL: bootstrap authority
├── operationalPolicy           -- HIGH: feature/policy gates
├── featureRegistry             -- MEDIUM: module enablement
├── characterEligibility        -- HIGH: main/alt, probation
├── identity                    -- MEDIUM: roster cache
├── backups[]                   -- HIGH: recovery snapshots
├── pendingRestores[]           -- HIGH: import preview state
├── disputes                    -- MEDIUM: audit workflow
├── profiles                    -- LOW: UI preferences
├── settings                    -- MEDIUM: legacy config (SA-006)
├── auditLog                    -- AUDIT: tamper-evident
└── schema                      -- MIGRATION: version tracking
```

### 3.2 Persistence Attack Vectors
| Vector | Entry Point | Detection |
|--------|-------------|-----------|
| Direct file edit | User edits `SavedVariables.lua` | Checksums on backup; sync reconciliation |
| Crafted import package | `ImportExport.Apply()` | Preview mandatory; checksum; scope check |
| Cross-guild restore | `Backup.Restore()` with foreign snapshot | Scope validation (`currentGuildKey` match) |
| Partial write | Crash during `Apply()` | **NOT DETECTED** — SA-010 |
| Rollback to old snapshot | `Backup.Restore()` with older `snapshotId` | Newer transactions preserved; sync fills gap |

### 3.3 Backup/Import Constraints
| Limit | Value | Enforcement |
|-------|-------|-------------|
| Max retention | 25 snapshots | `Backup.MAX_RETENTION` |
| Max package size | 250 KB | `ImportExport.MAX_PACKAGE_SIZE` |
| Max decode depth | 24 | `ImportExport.MAX_DEPTH` |
| Max decode nodes | 50,000 | `ImportExport.MAX_NODES` |
| Checksum algorithm | CRC32 (polynomial) | `Backup.checksum()`, `ImportExport.hash()` |

---

## 4. UI Attack Surface

### 4.1 Officer UI (Protected)
| Surface | Protection |
|---------|------------|
| Ledger adjustments | `ProtectedActions.Execute("ledger.adjust", ...)` |
| Pre-Dibs management | `ProtectedActions.Execute("predibs.update", ...)` |
| Governance adoption | `ProtectedActions.Execute("governance.adopt", ...)` |
| Policy changes | `ProtectedActions.Execute("policy.change", ...)` |
| Module enablement | `ProtectedActions.Execute("module.set", ...)` |
| Backup restore | `ProtectedActions.Execute("backup.restore", ...)` |
| Import apply | `ProtectedActions.Execute("import.apply", ...)` |
| Dispute resolution | `ProtectedActions.Execute("dispute.resolve", ...)` |

### 4.2 Player UI (Unprotected Reads)
| Surface | Data Access |
|---------|-------------|
| Dibs balance display | `Ledger.GetPlayerDibsProjection()` |
| Pre-Dibs requests | `PreDibs.GetRequests()` (own only) |
| Eligibility status | `CharacterEligibility.Evaluate()` |
| History/logs | Read-only projections |

### 4.3 UI Security Controls
| Control | Implementation |
|---------|----------------|
| Combat lockdown | `InCombatLockdown()` check in `ProtectedActions` handlers |
| Developer sandbox | `DeveloperSandbox.IsActive()` → rejects all production actions |
| Ready check | `Readiness.CanInteract()` for protected frames |
| Input validation | Payload schema validation in each handler |

---

## 5. Integration Attack Surface

### 5.1 RCLootCouncil Adapter
| Surface | Direction | Trust |
|---------|-----------|-------|
| `OnAwardSuccess` | Inbound (RC event) | ADVISORY — Dibs consumes, never writes |
| `LogPreDibRequest` | Outbound (RC history) | **WRITES TO RC DATA** — documented boundary violation |
| `EvaluateAuthority` | Inbound (RC query) | Dibs responds with its policy |
| Options panel | Outbound (UI) | Read-only projection |

### 5.2 Encounter Journal
| Surface | Direction | Trust |
|---------|-----------|-------|
| Catalog sync | Outbound (EJ data) | Read-only from Blizzard API |
| Pre-Dibs from EJ | User action → Inbound | Validated via `ProtectedActions` |

### 5.3 Ace3/AceComm/AceSerializer
| Surface | Direction | Trust |
|---------|-----------|-------|
| Addon comms | Bidirectional | **REQUIRED** — embedded; fallback incomplete (SA-003) |
| Options panel | Outbound | Standard AceConfig |
| DB defaults | Inbound | `AceDB` defaults |

---

## 6. Attack Surface by STRIDE

| STRIDE | Vectors | Key Findings |
|--------|---------|--------------|
| **Spoofing** | Sender spoofing (network), actor spoofing (API) | SA-009 (false positive — roster check works) |
| **Tampering** | SavedVariables edit, message modification, partial import | SA-010 (atomic import), SA-005 (non-crypto hash) |
| **Repudiation** | No cryptographic signatures | Accepted — guild membership is trust anchor |
| **Information Disclosure** | Sync broadcasts ledger to guild | By design — guild transparency |
| **Denial of Service** | Malformed messages, protocol mismatch, oversized packages | SA-003 (fallback), SA-004 (version), size limits |
| **Elevation of Privilege** | Direct mutator calls, unknown action, GM impersonation | SA-001 (balance), SA-002 (mutators), SA-008 (false positive) |

---

## 7. Attack Surface Reduction Recommendations

### Immediate (P0)
1. **Remove public mutators** — Make `Ledger.*` and `PreDibs.*` mutation functions local; only `ProtectedActions` handlers call them
2. **Atomic import** — Two-phase validate/commit with safety snapshot
3. **Balance enforcement** — Atomic check in `Ledger.Use` / `executeLedgerUse`

### Short-term (P1)
4. **Protocol negotiation** — Add min/max protocol, capabilities to HELLO
5. **Complete fallback** — Require AceComm or implement full bounded fallback
6. **Unified policy service** — Single owner for `db.settings` with revision/audit

### Long-term (P2/P3)
7. **Cryptographic message auth** — If threat model escalates (companion service)
8. **Adapter contract** — Stable RC API with version matrix
9. **Immutable read APIs** — Return deep copies from all getters

---

## 8. Attack Surface Metrics

| Metric | Value |
|--------|-------|
| Network message types | 23 |
| Protected actions | 28 |
| Public mutation functions (unprotected) | 9 (`Ledger`: 4, `PreDibs`: 5) |
| SavedVariables top-level keys | 14 |
| Integration points | 3 (RC, EJ, Ace3) |
| Trust boundaries | 5 (Network, AuthZ, Domain, Persistence, External) |
| **P0 attack paths** | **3** (SA-001, SA-002, SA-010) |

---

**End of Attack Surface Analysis**