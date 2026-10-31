# Feature Registry Traceability

Every functional requirement FR-001 through FR-026 is mapped below to the
component that implements it, the test that demonstrates it, and the
acceptance condition. "Covered" means the behaviour has a discriminating test
that fails when the behaviour is removed.

| ID | Component(s) | Test / evidence | Acceptance condition |
|---|---|---|---|
| FR-001 | `OperationalPolicy` (`CORE_MODULE_DEFINITIONS`, `MODULE_DEFINITIONS`) | `feature_registry_spec.lua` — "exposes every core and optional feature from the canonical catalogue" | The registry contents equal the canonical catalogue size exactly; no second list exists. |
| FR-002 | `FeatureRegistry.ListFeatures`, `GetDefinition` | Same test as FR-001; `GetDefinition` returns `nil` for an unknown id | The registry reads the catalogue rather than duplicating it. |
| FR-003 | `FeatureRegistry.describe`, `ValidatePatch`, `CanDisable` | "keeps required features enabled and refuses to configure them" | A required service is always enabled; a patch naming it is refused with `FEATURE_CORE_IMMUTABLE`. |
| FR-004 | `FeatureRegistry.resolve` | "fails closed for an unknown feature identifier"; "reports a policy-disabled feature"; "reports a dependency-disabled feature" | Precedence is required → unknown → dependency → policy, each with its own reason code. |
| FR-005 | `Policy.RequireModuleEnabled` and the 12 gated modules | `module_management_spec.lua` (existing); the gate table in `feature-catalog.md` | Every documented entry point of every optional feature refuses with a specific reason code. |
| FR-006 | `FeatureRegistry.RequireEnabled`; `Policy.RequireModuleEnabled` delegates to it | "refuses to proceed when the feature is disabled by policy"; "allows the feature when it is enabled" | One gate resolves the effective state for every caller. |
| FR-007 | `OperationalPolicy.writerAuthorized`, `moduleManagementStatus` | `module_management_spec.lua` — "lets an explicitly authorized officer create module state"; "renders the exact blocking reason for an officer" | Only the GM or an authorized writer may change the configuration; refusals name the exact reason. |
| FR-008 | `OperationalPolicy.requireLocalActor` | `module_management_spec.lua` — GM/officer authority cases | A verified authority that is not the local player is refused with `LOCAL_ACTOR_REQUIRED`. |
| FR-009 | `OperationalPolicy.normalizedValues` (modules branch) | "stores only the explicit decisions and keeps the record hash stable" | The stored map contains only explicit decisions; a feature that was never decided is absent. |
| FR-010 | `OperationalPolicy.effectiveModules`, `GetModuleValues` | Same test as FR-009 | An absent key resolves to the catalogue default through the effective state. |
| FR-011 | Sparse overlay design in `normalizedValues` | "stores only the explicit decisions and keeps the record hash stable" plus the larger-catalogue acceptance test | Adding a catalogue entry does not change an existing record's content hash and needs no re-adoption. |
| FR-012 | `OperationalPolicy.validateLocalModulePatch` | `module_management_spec.lua` — "denies unknown module keys" | A local patch naming an unknown feature is refused with `INVALID_MODULE_POLICY`. |
| FR-013 | `OperationalPolicy.normalizedValues` (retention of unknown keys), `mergeValues` (key-by-key merge) | "keeps a record produced with a larger catalogue valid on an older catalogue" | The record is accepted, the unknown key is retained in storage, and the unknown feature is not effective. |
| FR-014 | `OperationalPolicy.validateModuleDependencies` | "rejects a patch that would enable a dependent while its dependency is off"; "reports a dependency-disabled feature with the dependency reason code" | Enabling a dependent while its dependency is off is refused with `MODULE_DEPENDENCY_RCLootCouncil`. |
| FR-015 | `OperationalPolicy.validateModuleDependencies`; `FeatureRegistry.CanDisable` | "refuses to disable a feature while an active dependent is enabled"; "allows disabling a feature once its dependents are disabled" | A dependent that is still enabled blocks the change; both may be changed together. |
| FR-016 | `normalizedValues` (no dependency check) versus `validateModuleDependencies` (local write path) | "keeps a record produced with a larger catalogue valid on an older catalogue" | A peer record with a different catalogue is accepted; the dependency rule applies only to local writes. |
| FR-017 | `OperationalPolicy` + `SyncV2` `OPERATIONAL_POLICY` entity | `operational_policy_spec.lua` (existing) — chain recovery, conflict, stale, two-raid convergence | The configuration travels in the existing canonical entity; there is no parallel mechanism. |
| FR-018 | `OperationalPolicy.ApplyRecord` → `writerAuthorized` | `operational_policy_spec.lua` — "accepts an authorized officer record but rejects a member and local settings as authority" | Sender authority is verified at acceptance and fails closed. |
| FR-019 | `OperationalPolicy` audit log; `CreateChangeRecord` `audit.moduleChanges`; `FeatureRegistry.GetChangeHistory` | "exposes the configuration change history from the policy audit log" | Every change is audited with the per-feature effective transition. |
| FR-020 | No deletion path in `Policy.ChangeModules`; data is untouched by a toggle | `module_management_spec.lua` — "denies unknown module keys and preserves disabled module data for re-enable" | Disabling a feature does not remove its data; re-enabling restores access to it. |
| FR-021 | `OfficerUI` Modules page | `module_management_spec.lua` — checkbox, draft, and reset cases | The page shows category, description, and consequences, and delegates every mutation to the policy service. |
| FR-022 | `OfficerUI` module draft handling | `module_management_spec.lua` — "preserves the draft when Save fails and disables only dependent modules" | A failed save keeps the draft intact and leaves the authoritative state unchanged. |
| FR-023 | Catalogue classification; `Ledger` independence | "keeps the production accounting path independent of the registry" | The registry is not referenced by the ledger; `rankRules` is a required service because the allocation path depends on it. |
| FR-024 | `Backup.Create` `options.internal` | `rf0041`, `rf0046`, `rf0047`, `rf0033`, `backup_import_profiles` suites | A mandatory safety snapshot is still taken when the backup feature is off, so import and restore keep their recovery point. |
| FR-025 | `FeatureRegistry.GetDiagnostics`, `GetChangeHistory` | "produces a diagnostic line for every feature"; "exposes the configuration change history" | The diagnostic report has one line per feature; the history reflects the recorded changes. |
| FR-026 | Unchanged canonical modules | The full existing Lua suite, including the RF-0012 and RF-0013 suites | The canonical accounting mechanisms and the RF-0012 locks are unchanged and their suites still pass. |

## Enforcement coverage matrix

| Feature | Enforced entry point | Enforcing code |
|---|---|---|
| `requests` | `Disputes.CreateReport` and the other dispute entry points | `src/modules/Disputes.lua` |
| `requests` | `/dibs requests`, `/dibs review` | `src/Core.lua` |
| `preDibs` | Pre-Dib creation | `src/modules/PreDibs.lua` |
| `preDibs` | `/dibs pre` | `src/Core.lua` |
| `announcements` | `PreDibs.SendTestAnnouncement`, Pre-Dib announcement sender | `src/modules/PreDibs.lua` |
| `historicalReconciliation` | `/dibs reconcile` | `src/Core.lua` |
| `historicalReconciliation` | RCLootCouncil historical reconciliation path | `src/integrations/RCLootCouncil.lua` |
| `lootEligibility` | Eligibility decision building | `src/modules/CharacterEligibility.lua` |
| `rclootcouncil` | Award adapter | `src/integrations/RCLootCouncil.lua` |
| `raidPrompts` | `RaidPrompts.IsEnabled` gates prompt creation | `src/modules/RaidPrompts.lua` |
| `notifications` | `Notifications.IsEnabled` gates delivery | `src/modules/Notifications.lua` |
| `greatVault` | `GreatVault.RecordClaim` gates evidence recording | `src/integrations/GreatVault.lua` |
| `encounterJournal` | `EncounterJournal.CanPreDib` gates the Adventure Guide route | `src/integrations/EncounterJournal.lua` |
| `readiness` | `Readiness.Run` gates the readiness report | `src/modules/Readiness.lua` |
| `dryRun` | `DryRun.Run` gates simulated award validation | `src/modules/DryRun.lua` |
| `lootRules` | `LootRules.Adopt`, `LootRules.PublishDraft` | `src/modules/LootRules.lua` |
| `auditExport` | `AuditExport.BuildReport` | `src/modules/AuditExport.lua` |
| `profiles` | `Profiles.Create`, `Profiles.Activate` | `src/modules/Profiles.lua` |
| `backup` | `Backup.Create` (user-requested only) | `src/modules/Backup.lua` |
| `importExport` | `ImportExport.Apply` | `src/modules/ImportExport.lua` |

## Related documents

- [spec.md](spec.md)
- [Feature catalogue](../../docs/developer/feature-catalog.md)
- [Feature dependencies](../../docs/developer/feature-dependencies.md)
- [Feature configuration](../../docs/developer/feature-configuration.md)
- [Feature synchronization](../../docs/developer/feature-sync-protocol.md)
