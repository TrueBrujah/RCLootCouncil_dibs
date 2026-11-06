# Feature and Module Catalogue

Canonical reference for every feature that Dibs exposes, how it is classified,
how it can be turned on or off, and what it depends on.

The catalogue is implemented in exactly one place:
[`src/modules/OperationalPolicy.lua`](../../src/modules/OperationalPolicy.lua)
(`CORE_MODULE_DEFINITIONS` and `MODULE_DEFINITIONS`).
[`src/modules/FeatureRegistry.lua`](../../src/modules/FeatureRegistry.lua)
reads that table and exposes the public registry API. It never keeps a second
list, so the two cannot drift apart.

## Classification

| Class | Meaning | Toggle |
| --- | --- | --- |
| **Required core** | The addon cannot operate correctly without it. | Never. Always enabled. |
| **Optional** | A guild-configurable capability. | Guild Master or authorized policy writer. |
| **Conditional dependency** | An optional feature that requires another feature to be enabled. | Same as optional, but it cannot be enabled while its dependency is off. |

### Required core services

These are always enabled. A guild decision cannot change them, and the officer
interface renders them as read-only.

| Key | Label | Why it is required |
| --- | --- | --- |
| `ledger` | Ledger | Append-only Dib ledger, balances, and award accounting. |
| `identity` | Canonical Identity / Name-Realm | Name-Realm identity resolution and roster membership. |
| `governance` | Governance | Guild Master governance, officer authority rules, and audit lineage. |
| `protectedActions` | ProtectedActions | Combat and readiness guards for protected award actions. |
| `syncV2` | SyncV2 | Authoritative guild synchronization and coordinator recovery. |
| `coordinatorRecovery` | Coordinator / Recovery | Coordinator handoff, fencing, and epoch recovery. |
| `persistenceValidation` | Persistence validation | SavedVariables validation, migration, and recovery. |
| `rankRules` | Rank Rules | The canonical allocation path resolves the expected allocation from RankRules before an award is validated. Disabling it would make every allocation unverifiable. |

### Optional features

All optional features are **enabled by default**. A guild turns one off
explicitly; the decision is recorded in the canonical operational policy and
synchronized to the guild.

| Key | Label | Category | Depends on |
| --- | --- | --- | --- |
| `preDibs` | Pre-Dibs | workflow | — |
| `requests` | Requests | workflow | — |
| `rclootcouncil` | RCLootCouncil | integration | — |
| `announcements` | Announcements | workflow | — |
| `lootEligibility` | Loot Eligibility | rules | — |
| `historicalReconciliation` | Historical Reconciliation | workflow | `rclootcouncil` |
| `greatVault` | Great Vault | integration | — |
| `encounterJournal` | Encounter Journal | integration | — |
| `raidPrompts` | Raid Prompts | workflow | — |
| `notifications` | Notifications | workflow | — |
| `independentRaid` | Independent Raid | workflow | — |
| `lootRules` | Loot Rules | rules | — |
| `readiness` | Readiness | workflow | — |
| `dryRun` | Dry Run | workflow | — |
| `auditExport` | Audit Export | data | — |
| `historyFilters` | History Filters | data | — |
| `profiles` | Profiles | data | — |
| `backup` | Backup | data | — |
| `importExport` | Import / Export | data | — |

## Effective state

`Dibs.FeatureRegistry.GetEffectiveState(featureId)` resolves a feature to its
current effective state. The precedence is fixed and deterministic:

1. **Required features are always enabled.** They are locked and expose no
   toggle path.
2. **An unknown feature fails closed.** The result is `FEATURE_UNKNOWN` and
   the feature is treated as disabled.
3. **A feature whose dependency is disabled is disabled**, with the reason
   code `FEATURE_DISABLED_BY_DEPENDENCY` and the blocking dependency named.
4. **Otherwise the canonical guild policy value decides**, with the reason
   code `FEATURE_DISABLED_BY_POLICY` when the guild turned it off.

### Reason codes

| Code | Meaning |
| --- | --- |
| `FEATURE_UNKNOWN` | The identifier is not part of the catalogue. Fails closed. |
| `FEATURE_REQUIRED_ALWAYS_ON` | A required service was targeted for change. |
| `FEATURE_DISABLED_BY_POLICY` | The guild turned the feature off. |
| `FEATURE_DISABLED_BY_DEPENDENCY` | A feature this one depends on is disabled. |
| `FEATURE_INCOMPATIBLE_VERSION` | The record was produced by a newer registry version. |
| `FEATURE_SANDBOX_ACTIVE` | The developer sandbox is active. |
| `FEATURE_BLOCKED_IN_FLIGHT` | An operation is in flight and cannot be interrupted. |
| `FEATURE_CORE_IMMUTABLE` | A required service cannot be configured. |
| `FEATURE_DEPENDENTS_ACTIVE` | Disabling the feature would break an active dependent. |

## The enforcement gate

`Dibs.FeatureRegistry.RequireEnabled(featureId)` is the single gate. Every
optional feature entry point must pass through it, so a disabled feature
cannot be reached by an alternate path.

`Dibs.OperationalPolicy.RequireModuleEnabled(featureId)` remains the public
entry point used by the rest of the addon. It delegates to the registry and
maps the result onto the established `MODULE_DISABLED_*` reason codes so that
existing callers and their tests keep their contract.

### Enforced entry points

| Feature | Entry point |
| --- | --- |
| `requests` | `Disputes.CreateReport` and the other dispute entry points; the `/dibs requests` and `/dibs review` slash routes. |
| `preDibs` | `PreDibs` request creation; the `/dibs pre` slash route. |
| `announcements` | `PreDibs.SendTestAnnouncement` and the Pre-Dib announcement sender. |
| `historicalReconciliation` | The `/dibs reconcile` slash route; the RCLootCouncil historical reconciliation path. |
| `lootEligibility` | `CharacterEligibility` decision building. |
| `rclootcouncil` | The RCLootCouncil award adapter. |
| `raidPrompts` | `RaidPrompts.IsEnabled`, which gates prompt creation. |
| `notifications` | `Notifications.IsEnabled`, which gates notification delivery. The per-character preference remains the inner gate. |
| `greatVault` | `GreatVault.RecordClaim`, which gates evidence recording. |
| `encounterJournal` | `EncounterJournal.CanPreDib`, which gates the Adventure Guide Pre-Dib route. |
| `readiness` | `Readiness.Run`, which gates the readiness report. |
| `dryRun` | `DryRun.Run`, which gates simulated award validation. |
| `lootRules` | `LootRules.Adopt` and `LootRules.PublishDraft`, which gate guild loot rule publication. |
| `auditExport` | `AuditExport.BuildReport`, which gates audit report production. |
| `profiles` | `Profiles.Create` and `Profiles.Activate`, which gate profile management. |
| `backup` | `Backup.Create`, which gates user-requested backups. |
| `importExport` | `ImportExport.Apply`, which gates package import. |

### Safety snapshots are exempt

`Backup.Create` refuses to run when the `backup` feature is disabled, with one
deliberate exception. A **mandatory safety snapshot** taken on behalf of
another operation — an import, a restore, a profile reset, or a profile
deletion — is always permitted. Refusing it would leave the calling operation
without its recovery point and would make the data path less safe, not more.

Those calls pass `{ internal = true }` to `Backup.Create`.

## Local preferences versus guild policy

Three capabilities have both a guild-level policy and a local preference. The
guild policy is always the outer gate and the local preference is always the
inner one.

| Feature | Guild policy | Local preference |
| --- | --- | --- |
| `notifications` | Guild-wide enablement. | Per-character enablement in `RCLootCouncil_dibsLocalDB`. |
| `raidPrompts` | Guild-wide enablement. | `db.settings.raidEntryDibPromptsEnabled`. |
| Developer mode | Never part of the guild catalogue. | Local only, and it is isolated from production accounting. |

A guild that turns a feature off disables it for everyone, including the
officer who turned it off. A player who never opted in locally still receives
nothing.

## Registry API

| Function | Purpose |
| --- | --- |
| `ListFeatures()` | Every feature with its class, category, description, and dependency. |
| `GetDefinition(id)` | The descriptor of one feature, or `nil`. |
| `IsRequired(id)` | Whether the feature is a required service. |
| `GetEffectiveState(id)` | The resolved effective state with its reason code. |
| `IsEnabled(id)` | Boolean effective state. Fails closed on an unknown feature. |
| `RequireEnabled(id)` | The enforcement gate. |
| `GetDependencies(id)` | Direct and transitive dependencies. |
| `GetDependents(id)` | The features that would break if this one were disabled. |
| `CanDisable(id, actor)` | Whether the feature may be disabled right now. |
| `ValidatePatch(patch)` | Validates a proposed change before it is applied. |
| `PreviewState(id, patch)` | The state a feature would have, without mutating anything. |
| `GetCompatibility()` | Registry version, policy schema, and policy revision. |
| `CanApplyRecord(record)` | Whether this client can interpret a policy record. |
| `GetDiagnostics()` | A human-readable diagnostic line per feature. |
| `GetChangeHistory(limit)` | The configuration change trail from the policy audit log. |

## Related documents

- [Feature dependencies](feature-dependencies.md)
- [Feature configuration](feature-configuration.md)
- [Feature synchronization](feature-sync-protocol.md)
- [Operational policy and saved variables](saved-variables.md)
- [Synchronization protocol](sync-protocol.md)
