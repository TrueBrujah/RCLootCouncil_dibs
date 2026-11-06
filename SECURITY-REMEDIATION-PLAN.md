# RCLootCouncil_dibs — Security Remediation Plan

**Audit Date:** 2025-10-26
**Target Commit:** cb3f12a
**Status:** **NOT READY FOR RELEASE** — 2 P0 blockers (SA-001 already fixed)

> **Historical plan; reassessed 2026-10-28.** The release verdict and proposed
> SA-002 mutator privatization below are stale and should not be followed as
> current instructions. Current evidence does not establish a ledger permission
> bypass. SA-010 import integrity remains actionable: malformed local/guild
> replacement packages can throw after clearing settings, and full import can
> replace the live ledger map. Current review and focused test results:
> [REVIEW-2026-10-28](docs/code-audit/REVIEW-2026-10-28.md). No production changes
> were made during that reassessment.

---

## 1. Remediation Priority Classification

| Priority | Definition | SLA |
|----------|------------|-----|
| **P0** | Release-blocking: data integrity violation, authorization bypass, atomicity failure | Must fix before RC |
| **P1** | High-priority security: protocol gaps, incomplete fallback, version negotiation | Next patch (v0.8.11) |
| **P2** | Defense in depth: non-crypto hash, config consistency, adapter contracts | Backlog (v0.9.0) |
| **P3** | Quality improvement: test coverage, documentation, false positive regression tests | Ongoing |

---

## 2. P0 — Release Blocking (2 Items, SA-001 Removed — Already Fixed)

### ~~P0-1: SA-001 — Ledger Negative Balance~~ **ALREADY FIXED**
**Validation Result:** The `INSUFFICIENT_BALANCE` check exists in `CommitLocalTransaction` (line ~450) and is enforced for ALL `DIB_USED` transaction paths. No action needed.

---

### P0-1: SA-002 — Public Mutators Bypass ProtectedActions
**Files:** `src/modules/Ledger.lua` (Grant, Use, Refund, AdminAdjust), `src/modules/PreDibs.lua` (UpdateStatus, Confirm, Cancel, Invalidate, Fulfill)

**Fix Option A (Minimal — Recommended):**
```lua
-- In Ledger.lua: make mutation functions local
local function grant(memberKey, amount, reason, ...) ... end
local function use(memberKey, amount, reason, ...) ... end
-- Export only read APIs; ProtectedActions handlers call local functions

-- In ProtectedActions handlers:
if actionId == "ledger.grant" then return executeLedgerGrant(actor, command, decision) end
-- executeLedgerGrant calls local grant()
```

**Fix Option B (Defense-in-Depth):**
```lua
-- Add authorization context parameter to all mutators
function Ledger.Grant(memberKey, amount, reason, authContext)
  if not authContext or not authContext.authorized then
    return nil, "UNAUTHORIZED_MUTATION"
  end
  -- ... existing logic
end
```

**Test:** Add `tests/unit/protected_actions_mutators_spec.lua` verifying direct calls fail.

**Regression Risks:**
- Sync recovery (`SyncV2.applySnapshot`) calls `Ledger.Grant` internally — provide `systemBootstrap=true` context
- Bootstrap/initialization paths — audit all internal callers

**Estimated Effort:** 4-8 hours (Option A), 8-16 hours (Option B)

---

### P0-2: SA-007 — Import Not Atomic (renumbered from SA-010)
**File:** `src/modules/ImportExport.lua` (`Apply` function)

**Fix:** Two-phase apply
```lua
-- Phase 1: Validate entire package to temporary structures
function ImportExport.ValidateFullPackage(package)
  local tempDB = {}  -- deep copy of current db
  local conflicts = {}
  -- Apply each entity to tempDB, collecting conflicts
  -- Return { ok = true/false, tempDB = tempDB, conflicts = conflicts, previewState = ... }
end

-- Phase 2: Single atomic commit
function ImportExport.CommitValidatedPackage(previewState, actor)
  -- Create safety snapshot first
  local safety = Backup.Create("pre-import-" .. date("%Y%m%d%H%M%S"), "guild", actor)
  -- Swap tempDB → db in single operation
  -- Audit log entry
  -- Trigger sync if needed
end

-- Apply becomes:
function ImportExport.Apply(previewId, confirmation, reason, actor)
  local preview = db.pendingRestores[previewId]
  if not preview or preview.decision ~= "confirmed" then return nil, "INVALID_PREVIEW" end
  local validation = ImportExport.ValidateFullPackage(preview.package)
  if not validation.ok then return nil, validation.conflicts end
  return ImportExport.CommitValidatedPackage(validation, actor)
end
```

**Test:** Add `tests/unit/import_atomicity_spec.lua` with mid-apply failure → zero changes.

**Regression Risks:**
- Large packages may hit Lua execution time limit — chunk validation
- Preview UI flow must remain compatible — `Preview` still returns previewId
- Safety snapshot already created in current `PreviewRestore` — reuse

**Estimated Effort:** 8-16 hours

---

## 3. P1 — High Priority (3 Items)

### P1-1: SA-003 — Compact AceComm Fallback Incomplete
**File:** `src/modules/Sync.lua:106-119`, `src/integrations/Ace3.lua:60-90`

**Fix:** Remove fallback; require AceComm/AceSerializer as embedded dependencies (already in `embeds.xml`)
```lua
-- In Sync.Send: remove early return for request/manifest/snapshot
-- In Ace3.lua: assert ace.RegisterComm succeeds, error if not
```

**Alternative:** Implement complete fallback with `C_ChatInfo.RegisterAddonMessagePrefix("DIBS")` and bounded serialization.

**Test:** Add `tests/unit/sync_compact_fallback_spec.lua`

**Estimated Effort:** 2-4 hours (remove fallback), 16-24 hours (complete fallback)

---

### P1-2: SA-004 — Protocol Exact Match Only
**File:** `src/modules/Sync.lua:66-75`, `src/modules/SyncV2.lua` (HELLO/DIGEST)

**Fix:** Negotiation in HELLO
```lua
-- HELLO payload adds:
minProtocol = 1, maxProtocol = 2, features = 0x0F

-- validGuildEnvelope:
if message.protocol < peer.minProtocol or message.protocol > peer.maxProtocol then
  return false, "PROTOCOL_MISMATCH: peer supports v" .. peer.minProtocol .. "-" .. peer.maxProtocol
end
```

**Test:** Add `tests/integration/security_protocol_negotiation_spec.lua`

**Estimated Effort:** 4-8 hours

---

### P1-3: SA-006 — Multiple db.settings Writers
**Files:** `src/modules/Profiles.lua`, `src/modules/PreDibs.lua`, `src/modules/RaidPrompts.lua`, `src/modules/OperationalPolicy.lua`

**Fix:** Unified `GuildPolicy` service (new module)
```lua
-- src/modules/GuildPolicy.lua
Dibs.GuildPolicy = Dibs.GuildPolicy or {}
function Dibs.GuildPolicy.Set(key, value, actor, reason)
  -- Validate key against allowlist
  -- Increment policyRevision
  -- Create audit record
  -- Update db.settings[key] = value
  -- Publish catalog via OperationalPolicy
end

-- All modules migrate:
-- Profiles.ApplyProfile → GuildPolicy.SetBatch(profile.settings, actor, "profile")
-- PreDibs.SetPublicMode → GuildPolicy.Set("predibsMode", mode, actor, "predibs")
-- etc.
```

**Test:** Add `tests/integration/security_concurrent_policy_spec.lua`

**Estimated Effort:** 16-32 hours (new module + migration)

---

## 4. P2 — Defense in Depth (2 Items)

### P2-1: SA-005 — Non-Cryptographic Hash (Documented)
**File:** `src/modules/SyncV2.lua:170-190`

**Action:** **No code change** — Document in threat model (already done in SECURITY-THREAT-MODEL.md).
- Hash provides integrity check against corruption, not authenticity
- Trust anchor: guild membership + sender authorization
- If threat model changes (companion service), add HMAC with shared secret

---

### P2-2: SA-007 — RC Adapter Internal Probes
**File:** `src/integrations/RCLootCouncil.lua`

**Fix:** Define adapter contract with RC team; version capability matrix
```lua
-- Add version detection:
local RC_VERSION = GetAddOnMetadata("RCLootCouncil", "Version")
local RC_CAPABILITIES = {
  ["2.8.0"] = { hasPublicAPI = true, supportsCallbacks = true },
  ["2.7.0"] = { hasPublicAPI = false, ... },
}

-- Fail closed with specific error:
if not RC_CAPABILITIES[RC_VERSION] then
  return false, "RCLC_VERSION_UNSUPPORTED: " .. RC_VERSION
end
```

**Test:** Add version matrix test to `b08_rclootcouncil_ui_safety_spec.lua`

**Estimated Effort:** 8-16 hours (depends on RC cooperation)

---

## 5. P3 — Quality Improvement (3 Items)

### P3-1: SA-008 Regression Test — Unknown Action Rejection
**Status:** ✅ **FALSE_POSITIVE** — No regression test needed (correct behavior)

### P3-2: SA-009 Regression Test — Sender Spoofing Rejection
**Status:** ✅ **FALSE_POSITIVE** — Existing test in `b04_transport_spec.lua` confirms sender validation

### P3-3: Security Test Coverage Expansion
**New Test Files Needed:**
| Test File | Findings Covered | Priority |
|-----------|------------------|----------|
| `tests/unit/ledger_balance_spec.lua` | — | — (already covered by b03_local_ledger_spec.lua) |
| `tests/unit/protected_actions_mutators_spec.lua` | SA-002 | P0 |
| `tests/unit/import_atomicity_spec.lua` | SA-007 | P0 |
| `tests/unit/sync_compact_fallback_spec.lua` | SA-003 | P1 |
| `tests/integration/security_negative_balance_spec.lua` | — | — (already covered) |
| `tests/integration/security_mutator_bypass_spec.lua` | SA-002 | P0 |
| `tests/integration/security_protocol_negotiation_spec.lua` | SA-004 | P1 |
| `tests/integration/security_concurrent_policy_spec.lua` | SA-006 | P1 |

**Estimated Effort:** 8-16 hours total

---

## 6. Remediation Timeline

| Week | Focus | Deliverables |
|------|-------|--------------|
| **Week 1** | P0 Fixes | SA-002 mutator privatization, SA-007 atomic import |
| **Week 2** | P0 Tests + P1 | All P0 test coverage, SA-003 fallback removal, SA-004 protocol negotiation |
| **Week 3** | P1 + P2 | SA-006 GuildPolicy module (start), SA-007 RC adapter contract |
| **Week 4** | P3 + Validation | Test coverage expansion, full security suite pass, regression testing |

---

## 7. Release Gate Criteria

**DO NOT RELEASE until ALL P0 criteria met:**

| Criterion | Verification |
|-----------|--------------|
| ✅ SA-002 Fixed | Direct `Ledger.Grant/Use/Refund/AdminAdjust` calls create no transactions |
| ✅ SA-007 Fixed | Failed import mid-apply leaves zero committed changes |
| ✅ P0 Tests Pass | All 2 new unit tests + 2 integration tests pass |
| ✅ Full Suite Pass | `DIBS_TEST_FILES=all` → 100% pass |
| ✅ No Regressions | Existing functionality: ledger, sync, governance, UI, RC integration |

---

## 8. Residual Risks (Post-Remediation)

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Local SavedVariables tampering | HIGH (user-controlled) | MEDIUM | Checksums, sync reconciliation, audit log |
| Network message forgery | MEDIUM | MEDIUM | Guild membership trust anchor, sequence/epoch |
| RC adapter breakage | MEDIUM | LOW | Version matrix, fail closed, no RC writes |
| Protocol downgrade | LOW | HIGH | Negotiation (P1 fix), actionable diagnostics |
| Config drift | MEDIUM | MEDIUM | GuildPolicy service (P1 fix) |

---

## 9. Sign-Off Requirements

| Role | Name | Approval |
|------|------|----------|
| Security Auditor | [This Audit] | ❌ **BLOCKED** — 3 P0 open |
| Lead Developer | | |
| Release Manager | | |

**Current Status:** **RELEASE BLOCKED**

---

## 10. Quick Reference: Files to Modify

### P0 Fixes
- `src/modules/Ledger.lua` — Add balance check in `Use`; privatize mutators
- `src/modules/PreDibs.lua` — Privatize mutators
- `src/modules/ProtectedActions.lua` — Update handlers to call local functions
- `src/modules/ImportExport.lua` — Two-phase validate/commit

### P1 Fixes
- `src/modules/Sync.lua` — Remove compact fallback or complete it
- `src/modules/SyncV2.lua` — Add protocol negotiation to HELLO/DIGEST
- `src/modules/GuildPolicy.lua` — **NEW FILE** — Unified policy service
- `src/modules/Profiles.lua` — Migrate to GuildPolicy
- `src/modules/PreDibs.lua` — Migrate settings writes to GuildPolicy
- `src/modules/RaidPrompts.lua` — Migrate settings writes to GuildPolicy
- `src/modules/OperationalPolicy.lua` — Integrate with GuildPolicy

### P2/P3
- `src/integrations/RCLootCouncil.lua` — Version capability matrix
- `tests/unit/*.lua` — 4 new test files
- `tests/integration/*.lua` — 4 new test files

---

**End of Remediation Plan**
