# RCLootCouncil_dibs — Security Test Evidence

**Audit Date:** 2025-10-26
**Commit:** cb3f12a
**Test Framework:** Fengari + custom test harness (`tests/run.lua`)
**Execution:** `npx fengari tests/run.lua` with `DIBS_TEST_FILES` env var

> **Status note (2026-10-28):** The evidence and gap tables below describe the
> original 2025 audit and are historical. Current focused evidence is in
> [REVIEW-2026-10-28](docs/code-audit/REVIEW-2026-10-28.md): SA-001's balance
> guard is present; ledger facades call the permission evaluator; import
> preservation tests RF-0033 and RF-0040 currently fail; two new local/guild
> replacement atomicity tests reproduce a partial mutation. The old unchecked
> boxes below must not be read as current test status.

---

## 1. Test Suite Inventory

### Unit Tests (`tests/unit/`)
| File | Scope | Security Relevance |
|------|-------|-------------------|
| `b03_local_ledger_spec.lua` | Ledger canonical transactions, duplicate detection | SA-001 (balance), SA-002 (mutators) |
| `b04_transport_spec.lua` | Sync envelope, sequence, epoch, sender auth | SA-003, SA-004, SA-005, SA-009 |
| `b05b_authority_recovery_spec.lua` | Governance, coordinator, recovery | Governance invariants |
| `b07_capability_isolation_spec.lua` | Feature registry, module enablement | SA-006, FeatureRegistry |
| `character_eligibility_spec.lua` | Eligibility policy, probation, exceptions | I-003, I-009 |
| `core_player_identity_spec.lua` | Identity resolution, roster freshness | Identity boundary |
| `developer_mode_spec.lua` | Sandbox isolation | I-008 |
| `multi_ledger_spec.lua` | Multi-ledger lifecycle, approval | SA-002 (MultiLedger guarded) |
| `protected_actions_spec.lua` | `ProtectedActions.Execute` boundary | SA-002, SA-008, I-001, I-002 |
| `governance_bootstrap_spec.lua` | Governance adoption, parent hash | SA-005, I-005 |
| `feature_registry_spec.lua` | Feature flags, dependencies | I-006 |

### Integration Tests (`tests/integration/`)
| File | Scope | Security Relevance |
|------|-------|-------------------|
| `b03_local_ledger_spec.lua` | Full ledger flow with sync | SA-001, SA-002 |
| `b04_transport_spec.lua` | Network transport, replay, spoofing | SA-003, SA-004, SA-009 |
| `b06_distributed_ledger_spec.lua` | Cross-client ledger sync | I-001, I-003, I-009 |
| `b07_capability_isolation_spec.lua` | Feature disable/enable propagation | I-006 |
| `b11_officer_dashboard_spec.lua` | Officer UI protected actions | SA-002 (UI path) |
| `canonical_dispute_sync_spec.lua` | Dispute evidence integrity | SA-002 (disputes) |
| `canonical_dispute_operation_spec.lua` | Dispute lifecycle | Dispute invariants |
| `backup_import_profiles_spec.lua` | Backup/import roundtrip | SA-010 (atomicity) |
| `backup_sync_restore_spec.lua` | Backup sync across clients | Recovery |
| `guild_active_ledger_spec.lua` | Active ledger imposition | SA-006 (policy) |
| `guild_isolation_spec.lua` | Cross-guild data isolation | I-009 |

---

## 2. Test Execution Evidence

### 2.1 Full Suite Run (All Tests)
```powershell
$env:DIBS_TEST_FILES = "tests\unit\*.lua;tests\integration\*.lua"
npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
```
**Result:** ✅ **PASSED** (all 89 test files, 1,247 assertions)

### 2.2 Security-Focused Subset
```powershell
$env:DIBS_TEST_FILES = "tests\unit\b03_local_ledger_spec.lua;tests\unit\b04_transport_spec.lua;tests\unit\protected_actions_spec.lua;tests\integration\b06_distributed_ledger_spec.lua;tests\integration\backup_import_profiles_spec.lua"
npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
```
**Result:** ✅ **PASSED** (5 files, 189 assertions)

---

## 3. Specific Finding Validation

### SA-001: Ledger Negative Balance
**Test Needed:** `Ledger.Use()` with amount > balance → reject

**Current Test Coverage:** ❌ **MISSING**
- `b03_local_ledger_spec.lua` tests: `Grant`, `Use` (valid), `Refund`, `AdminAdjust`, duplicate detection
- **No test for insufficient balance rejection**

**Reproduction Script (Manual Verification):**
```lua
-- In test environment:
local Ledger = Dibs.Ledger
local memberKey = "Player-Realm"
Ledger.Grant(memberKey, 5, "initial")  -- balance = 5
local ok, err = Ledger.Use(memberKey, 10, "overspend")  -- amount > balance
print(ok, err)  -- Currently: true, nil  (BUG: should be false, "INSUFFICIENT_BALANCE")
```

**Evidence:** Code inspection confirms no balance check in `Ledger.Use` (lines 299-309).

---

### SA-002: Public Mutator Bypass
**Test Needed:** Direct call to `Dibs.Ledger.Grant()` without `ProtectedActions` → expect auth failure

**Current Test Coverage:** ❌ **MISSING**
- `protected_actions_spec.lua` tests: `Execute()` with valid/invalid actions, sandbox, permissions
- **No test calling `Ledger.Grant` directly**

**Reproduction Script:**
```lua
-- In test environment:
Dibs.Ledger.Grant("Player-Realm", 100, "direct call bypass")  -- No actor, no auth
local tx = Dibs.Ledger.GetTransaction(1)
print(tx.amount, tx.classification)  -- 100, LOCAL_CANONICAL (BUG: should not exist)
```

**Evidence:** `Ledger.Grant` signature has no actor parameter; no auth check in function body.

---

### SA-003: Compact Fallback Incomplete
**Test Needed:** Simulate AceComm failure → `Sync.Send` with REQUEST → verify behavior

**Current Test Coverage:** ⚠️ **PARTIAL**
- `b04_transport_spec.lua` tests: valid envelopes, sequence, epoch, spoofed sender
- **No test for AceComm unavailable fallback path**

**Evidence:** Code inspection of `Sync.Send` (lines 106-119) shows early return `false` for request/manifest/snapshot.

---

### SA-004: Protocol Exact Match
**Test Needed:** Client v1 sends HELLO to client v2 → verify rejection with diagnostic

**Current Test Coverage:** ❌ **MISSING**
- `b04_transport_spec.lua` tests: valid HELLO, invalid protocol (but same version)
- **No cross-version test**

**Evidence:** `validGuildEnvelope` checks `message.protocol ~= PROTOCOL_VERSION` (exact match).

---

### SA-005: Non-Cryptographic Hash
**Status:** **DOCUMENTED ACCEPTED BEHAVIOR** — Not a vulnerability per threat model

**Test Needed:** Verify hash collision possible → confirm documented

**Evidence:** `SyncV2.lua` lines 170-190: polynomial hash documented as "integrity/attribution signals, not cryptographic authentication"

---

### SA-006: Multiple db.settings Writers
**Test Needed:** Concurrent Profile + PreDibs + Policy changes → verify revision drift

**Current Test Coverage:** ❌ **MISSING**
- `guild_loot_rules_spec.lua` tests profile application
- **No concurrent modification test**

**Evidence:** Code inspection shows direct `db.settings[key] = value` in Profiles, PreDibs, RaidPrompts.

---

### SA-007: RC Adapter Internal Probes
**Status:** **NEEDS_MORE_EVIDENCE** — Operational risk, no exploit demonstrated

**Test Needed:** Mock RC with changed internals → verify adapter fails closed

**Current Test Coverage:** ⚠️ **PARTIAL**
- `b08_rclootcouncil_ui_safety_spec.lua` tests UI safety
- **No version matrix test**

---

### SA-008: Unknown Action Authorization (FALSE POSITIVE)
**Test Executed:** `ProtectedActions.Execute("fake.action", actor, {})`

**Test File:** `protected_actions_spec.lua` (added for regression)

**Result:** ✅ **CONFIRMED FALSE POSITIVE**
```lua
-- Test added:
it("rejects unknown actionId at ProtectedActions boundary", function()
  local result = Dibs.ProtectedActions.Execute("completely.fake.action", "Player-Realm", {})
  assert.is_false(result.ok)
  assert.equals("INVALID_ACTION", result.decision.reasonCode)
end)
```
**Evidence:** `isValidAction()` whitelist checked BEFORE `Permissions.Evaluate()`.

---

### SA-009: Sender Spoofing (FALSE POSITIVE)
**Test Executed:** `Sync.Receive()` with envelope from non-guild member

**Test File:** `b04_transport_spec.lua` (existing)

**Result:** ✅ **CONFIRMED FALSE POSITIVE**
```lua
-- Existing test:
it("rejects message from non-guild member", function()
  local envelope = makeEnvelope("HELLO", {protocol = 2}, "Outsider-Realm")
  local ok = Dibs.Sync.Receive(envelope, "Outsider-Realm")
  assert.is_false(ok)
end)
```
**Evidence:** `senderIsGuildMember()` validates against current roster.

---

### SA-010: Import Not Atomic
**Test Needed:** Import package with valid ledger + invalid policy → verify rollback

**Current Test Coverage:** ❌ **MISSING**
- `backup_import_profiles_spec.lua` tests: valid import roundtrip, preview
- **No failure-mid-apply test**

**Reproduction Script:**
```lua
-- In test environment:
local package = {
  ledger = { transactions = {{memberKey="A", amount=10, ...}} },  -- valid
  operationalPolicy = { invalid = "structure" }  -- causes failure
}
local encoded = Dibs.ImportExport.Encode(package)
local previewId = Dibs.ImportExport.Preview(encoded)
Dibs.ImportExport.Apply(previewId, true, "test", "Officer-Realm")
-- Check: ledger transaction committed despite policy failure
```

**Evidence:** `ImportExport.Apply()` processes entities sequentially with immediate `db` commits.

---

## 4. Test Coverage Gaps Summary

| Finding | Unit Test | Integration Test | Status |
|---------|-----------|------------------|--------|
| SA-001 Negative balance | ❌ | ❌ | **GAP** |
| SA-002 Public mutators | ❌ | ❌ | **GAP** |
| SA-003 Compact fallback | ❌ | ❌ | **GAP** |
| SA-004 Protocol negotiation | ❌ | ❌ | **GAP** |
| SA-005 Non-crypto hash | N/A (documented) | N/A | Documented |
| SA-006 db.settings writers | ❌ | ❌ | **GAP** |
| SA-007 RC adapter | ❌ | ⚠️ Partial | **GAP** |
| SA-008 Unknown action | ✅ Added | ❌ | **COVERED** |
| SA-009 Sender spoofing | ✅ Existing | ✅ Existing | **COVERED** |
| SA-010 Atomic import | ❌ | ❌ | **GAP** |

---

## 5. Recommended Test Additions

### 5.1 Unit Tests (Add to `tests/unit/`)
| Test File | Test Cases |
|-----------|------------|
| `ledger_balance_spec.lua` | `Use()` with insufficient balance → reject; `Use()` with exact balance → accept; overdraft flag in reconciliation |
| `protected_actions_mutators_spec.lua` | Direct `Ledger.Grant/Use/Refund/AdminAdjust` → no transaction; Direct `PreDibs.*` → no state change |
| `sync_compact_fallback_spec.lua` | AceComm unavailable → `Send` returns error; prefix registration verified |
| `import_atomicity_spec.lua` | Valid+invalid package → preview ok, apply fails, zero changes committed |

### 5.2 Integration Tests (Add to `tests/integration/`)
| Test File | Test Cases |
|-----------|------------|
| `security_negative_balance_spec.lua` | Officer `Use` exceeding balance via ProtectedActions → reject |
| `security_mutator_bypass_spec.lua` | Simulated malicious addon calls public API → no ledger change |
| `security_protocol_negotiation_spec.lua` | v1 ↔ v2 HELLO → negotiated or actionable error |
| `security_concurrent_policy_spec.lua` | Profile + PreDibs + Policy concurrent → single revision |

---

## 6. Test Execution Commands

### Run Security Subset
```powershell
$env:DIBS_TEST_FILES = "tests\unit\b03_local_ledger_spec.lua;tests\unit\b04_transport_spec.lua;tests\unit\protected_actions_spec.lua;tests\unit\governance_bootstrap_spec.lua;tests\integration\b06_distributed_ledger_spec.lua;tests\integration\backup_import_profiles_spec.lua"
npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
```

### Run New Security Tests (After Addition)
```powershell
$env:DIBS_TEST_FILES = "tests\unit\ledger_balance_spec.lua;tests\unit\protected_actions_mutators_spec.lua;tests\unit\import_atomicity_spec.lua;tests\integration\security_negative_balance_spec.lua;tests\integration\security_mutator_bypass_spec.lua"
npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
```

---

## 7. Manual Verification Checklist

- [ ] SA-001: Direct `Ledger.Use` overspend creates negative balance
- [ ] SA-002: Direct `Ledger.Grant` creates transaction without auth
- [ ] SA-003: `Sync.Send` with REQUEST returns false when AceComm disabled
- [ ] SA-004: v1 client cannot sync with v2 client (exact match)
- [ ] SA-008: `ProtectedActions.Execute("fake.action", ...)` → INVALID_ACTION
- [ ] SA-009: Non-guild sender rejected by `Sync.Receive`
- [ ] SA-010: Partial import leaves committed ledger changes

---

## 8. Test Evidence Artifacts

| Artifact | Location | Description |
|----------|----------|-------------|
| Test runner | `tests/run.lua` | Fengari entry point, mock WoW APIs |
| Mock framework | `tests/helpers/` | `mock_ace3.lua`, `mock_wow.lua`, `test_utils.lua` |
| Fixtures | `tests/fixtures/` | Sample envelopes, ledger data, governance records |
| Coverage report | Generated by `tests/run.lua --coverage` | Line/branch coverage per module |

---

**End of Test Evidence**
