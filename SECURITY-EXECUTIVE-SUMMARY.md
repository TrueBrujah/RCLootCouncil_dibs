# RCLootCouncil_dibs — Security Audit Executive Summary

**Audit Date:** 2025-10-26
**Target Commit:** cb3f12a (dev branch)
**Scope:** Full codebase — identity, permissions, sync, ledger, governance, persistence, and UI

> **Current-source reassessment (2026-10-28):** This file's original findings
> below are historical and must not be used as the current release verdict. The
> ledger balance check is present, and ledger mutation facades pass through
> `Permissions.Evaluate`; SA-001 is resolved and the blanket SA-002 claim is not
> substantiated for the ledger. SA-003 is an incomplete compact transport path,
> whose behavior depends on AceComm availability and is not a confirmed security
> bypass. SA-010 is confirmed for malformed local/guild replacement payloads,
> which can throw after clearing settings, and full-scope imports currently
> overwrite the live `db.ledgers` map. See
> [current review](docs/code-audit/REVIEW-2026-10-28.md). Focused test results
> and reproduction details are recorded there. No production fix has been applied.

---

## Overall Risk Posture

| Dimension | Rating | Summary |
|-----------|--------|---------|
| **Identity & Permissions** | **MEDIUM** | Canonical identity relies on roster freshness; unknown action IDs fail closed; no privilege escalation from unknown actions |
| **Network/Sync** | **MEDIUM** | Sender validation present; guild-scoped; no cryptographic auth; replay resistance via sequence/epoch; compact fallback incomplete |
| **Ledger Integrity** | **MEDIUM** | Append-only with canonical classification; balance check missing on `Use`; duplicate detection on replay; admin adjustment bypasses balance |
| **Governance/Policy** | **LOW** | GM-only policy changes; operational policy requires adopted governance; feature registry fails closed on unknown features |
| **Persistence/Recovery** | **LOW** | Snapshots checksummed; preview-before-apply; no silent imports; backup retention bounded |
| **UI/ProtectedActions** | **LOW** | All mutations gated by `ProtectedActions.Execute` → `Permissions.Evaluate`; invalid actions rejected; sandbox isolation |

---

## Key Findings Summary

| ID | Severity | Status | Title |
|----|----------|--------|-------|
| **SA-001** | — | **RESOLVED** | Central balance check rejects insufficient `DIB_USED` transactions |
| **SA-002** | — | **NOT SUBSTANTIATED FOR LEDGER** | Ledger facades call `Permissions.Evaluate`; the PreDibs portion needs a separate method-by-method review |
| **SA-003** | P2 | **LIMITATION; IMPACT CONDITIONAL** | Compact fallback cannot carry the request/manifest/transfer data needed for full synchronization |
| **SA-004** | P2 | **CONFIRMED** | Protocol version exact-match only; no negotiation; minor patch blocks entire guild sync |
| **SA-005** | P2 | **CONFIRMED** | SyncV2 digest/entity validation relies on non-cryptographic hash; no authenticity proof |
| **SA-006** | P3 | **CONFIRMED** | Multiple modules write `db.settings` directly without unified revision/audit pipeline |
| **SA-007** | P3 | **NEEDS_MORE_EVIDENCE** | RCLootCouncil adapter probes internal unstable structures (no direct security impact) |
| **SA-008** | P3 | **FALSE_POSITIVE** | "Unknown action IDs can be authorized" — tested: unknown actions fail closed in `Permissions.Evaluate` |
| **SA-009** | P3 | **FALSE_POSITIVE** | "Sender identity spoofing in Sync" — tested: `canonicalSender` + `senderIsGuildMember` + `localIsGuildAdmin` enforced |
| **SA-010** | P1 | **CONFIRMED** | Malformed local/guild replacement shapes throw after settings are cleared; full import can replace the live ledger map |

---

## Phase 1: FeatureRegistry.lua Discrepancy — RESOLVED

| Check | Result |
|-------|--------|
| File exists in workspace | ✅ `src/modules/FeatureRegistry.lua` present (267 lines) |
| File tracked by Git | ✅ Tracked since commit `d1de5a1` (2026-10-15) |
| Referenced in TOC | ✅ Listed after `OperationalPolicy.lua`, before `Seasons.lua` |
| Load order correct | ✅ Loaded before modules that depend on it (`OfficerUI.lua`, `FeatureRegistry` used at line 5860) |
| **Conclusion** | **No discrepancy** — FeatureRegistry.lua is tracked, present, and correctly loaded. The previous report's claim was incorrect. |

---

## Phase 2: Previous Audit Findings — Reassessed

| Original ID | Reassessment | Verdict | Notes |
|-------------|--------------|---------|-------|
| S-001 | Public mutators bypass ProtectedActions | **NOT SUBSTANTIATED FOR LEDGER** → SA-002 | Direct ledger calls still pass the centralized `Permissions.Evaluate` gate; PreDibs requires separate review |
| S-002 | Ledger Use no balance check | **RESOLVED** → SA-001 | `CommitLocalTransaction` enforces `INSUFFICIENT_BALANCE` |
| S-003 | Sync compact fallback incomplete | **CONDITIONAL LIMITATION** → SA-003 | Full data-bearing messages are refused; regular transport registration and AceComm behavior determine impact |
| S-004 | Protocol exact-match only | **CONFIRMED** → SA-004 | `Sync.lua:66-75`, `SyncV2.lua` no minor negotiation |
| S-005 | Import not atomic | **CONFIRMED, NARROWED** → SA-010 | Local/guild malformed replacement can throw after clearing settings; full scope also replaces `db.ledgers` |
| A-001 | No single policy owner | **CONFIRMED** → SA-006 | `db.settings` mutated by Profiles, PreDibs, RaidPrompts, Announcements |
| RC-001 | RC adapter probes internals | **NEEDS_MORE_EVIDENCE** → SA-007 | No exploit path; operational risk only |

---

## Historical Release Blockers — Superseded by Current Reassessment

| Blocker | Priority | Required Fix |
|---------|----------|--------------|
| Historical SA-002 | Closed for ledger facades; PreDibs not reassessed here | Do not privatize without evidence |
| Current SA-010 import integrity | P1 candidate | Validate shape and stage replacement before mutating; fix full-scope ledger-map overwrite |

---

## Residual Risks (Accepted)

| Risk | Why Accepted |
|------|--------------|
| Local SavedVariables can be edited by user | Cannot be prevented in WoW addon threat model; checksums detect accidental corruption |
| No cryptographic message authentication | WoW addon chat channels provide no PKI; guild membership is the trust anchor |
| RCLootCouncil adapter uses internal APIs | No security boundary crossed; adapter fails closed on version mismatch |
| Compact fallback incomplete | AceComm/AceSerializer are embedded; standalone mode not a supported deployment |

---

## Test Evidence Summary

| Test File | Coverage |
|-----------|----------|
| `tests/integration/b03_local_ledger_spec.lua` | Ledger canonical transactions, duplicate detection |
| `tests/integration/b04_transport_spec.lua` | Sync envelope validation, sequence/epoch |
| `tests/integration/b05b_authority_recovery_spec.lua` | Governance adoption, coordinator recovery |
| `tests/integration/b07_capability_isolation_spec.lua` | Feature registry, module enablement |
| `tests/integration/canonical_dispute_sync_spec.lua` | Dispute sync, evidence integrity |
| `tests/integration/feature_registry_spec.lua` | Feature enable/disable, dependency resolution |

**Current test evidence (2026-10-28):** targeted selection: 40 passed / 3 failed
across `sync_privacy_spec.lua`, `backup_import_profiles_spec.lua`, and
`rf0040_import_export_hardening_spec.lua`; the failures concern preservation of
newer full-import state and post-preview revalidation. `rf0033` had 2 passed / 2
failed, reproducing newer-ledger loss and alias divergence. New local/guild
atomicity regressions both fail because `Apply` throws while replacing settings.
The old coverage-gap statement above is historical and superseded by this evidence.

---

## Remediation Priority

| Priority | Items | Target |
|----------|-------|--------|
| **P0** | SA-001, SA-002, SA-010 | Release-blocking — must fix before RC |
| **P1** | SA-003, SA-004, SA-005 | High — fix in next patch |
| **P2** | SA-006, SA-007 | Defense in depth — backlog |
| **P3** | Documentation, test coverage | Quality — ongoing |

---

**Current recommendation:** Do not use the historical P0 table above as the
release gate. Resolve the confirmed import integrity findings and rerun the
current targeted regression suites before setting a release status. This review
did not perform Retail or multiclient validation.
