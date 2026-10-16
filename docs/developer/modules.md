# Module inventory

The following inventory covers first-party files in the TOC. Embedded libraries are documented as dependencies rather than re-described as Dibs modules.

| File | Namespace | Layer | Main responsibility |
| --- | --- | --- | --- |
| `Core.lua` | `Dibs` / `Dibs.CoreAPI` | Composition | Startup, SavedVariables migration, slash/API facade, WoW event routing |
| `locales/enUS.lua`, `locales/frFR.lua` | `Dibs.L` | Localization | English fallback and French labels/help |
| `Types.lua` | LuaLS global aliases/classes | Static documentation | Annotation-only domain models and callback signatures; not loaded at runtime |
| `modules/Identity.lua` | `Dibs.Identity` | Identity | Live guild-roster resolution and immutable identity snapshots |
| `modules/Governance.lua` | `Dibs.Governance` | Authority | GM-approved governance, coordinator epochs, and V2 cutover |
| `modules/OperationalPolicy.lua` | `Dibs.OperationalPolicy` | Policy | Versioned operational policy and optional-module controls |
| `modules/Seasons.lua` | `Dibs.Seasons` | Domain | Season lifecycle |
| `modules/RankRules.lua` | `Dibs.RankRules` | Domain | Rank-to-allocation policy |
| `modules/LootRules.lua` | `Dibs.LootRules` | Policy | GM adoption/publication of guild Loot Rules and effective projections |
| `modules/Ledger.lua` | `Dibs.Ledger` | Accounting | Append-only transactions and balances |
| `modules/MultiLedger.lua` | `Dibs.MultiLedger` | Accounting | Ledger catalog, independent balances, approval, archive/deletion governance |
| `modules/Permissions.lua` | `Dibs.Permissions` | Policy | Guild identity and authority |
| `modules/ProtectedActions.lua` | `Dibs.ProtectedActions` | Application | Permission/readiness/combat gate |
| `modules/ImportExport.lua` | `Dibs.ImportExport` | Persistence | Bounded package preview/apply |
| `modules/AuditExport.lua` | `Dibs.AuditExport` | Audit projection | Bounded anonymized, non-importable audit reports |
| `modules/Profiles.lua` | `Dibs.Profiles` | Persistence | Named configuration projections |
| `modules/Backup.lua` | `Dibs.Backup` | Persistence | Recovery snapshots and retention |
| `modules/Disputes.lua` | `Dibs.Disputes` | Audit | Reports, replies, corrections |
| `modules/PreDibs.lua` | `Dibs.PreDibs` | Domain | Request lifecycle and announcements |
| `modules/Notifications.lua` | `Dibs.Notifications` | Player presentation | Localized, private, idempotent personal notifications |
| `modules/CharacterEligibility.lua` | `Dibs.CharacterEligibility` (`Dibs.Eligibility` compatibility alias) | Domain | Main/alt, Curio, Tier Set eligibility |
| `modules/LootPipeline.lua` | `Dibs.LootPipeline` | Application | Item normalization and award context |
| `modules/Sync.lua` | `Dibs.Sync` | Distributed | Guild-scoped metadata synchronization |
| `modules/SyncV2.lua` | `Dibs.Sync` (extends it) | Distributed | V2 catalogs, ordered canonical commits, recovery, and bounded detail transport |
| `modules/RequestDelivery.lua` | `Dibs.RequestDelivery` | Distributed | Private dossier delivery, durable outbox, receipt states, and local follow-up reminders |
| `modules/HistoricalBaseline.lua` | `Dibs.HistoricalBaseline` | Recovery | Historical evidence classification and approved baseline/recovery |
| `modules/Installation.lua` | `Dibs.Installation` | Application | Guild Configuration status, proposals, and ledger initialization |
| `modules/Wizard.lua` | `Dibs.Wizard` | Application | Three-stage Guided Setup profiles, preview/apply, and verification |
| `modules/RaidRelay.lua` | `Dibs.RaidRelay` | Application | Active relay and reminders |
| `modules/RaidPrompts.lua` | `Dibs.RaidPrompts` | Player workflow | Encounter prompts |
| `modules/Readiness.lua` | `Dibs.Readiness` | Runtime guard | Live-context and combat readiness |
| `modules/DryRun.lua` | `Dibs.DryRun` | Test/dev | Non-mutating command evaluation |
| `modules/Capabilities.lua` | `Dibs.Capabilities` | Runtime | Capability lifecycle, probes, retries, and diagnostics |
| `modules/IndependentRaid.lua` | `Dibs.IndependentRaid` | Application | Isolated ephemeral raid points, separate from guild accounting |
| `integrations/Ace3.lua` | `Dibs.Ace3` | Framework adapter | Optional Ace3 capabilities |
| `integrations/GreatVault.lua` | `Dibs.GreatVault` | Blizzard adapter | Correlates claim, receipt, and reward-availability evidence |
| `integrations/DeveloperMode.lua` | `Dibs.DeveloperMode` | Test/dev | Diagnostic/test commands |
| `integrations/EncounterJournal.lua` | `Dibs.EncounterJournal` | Blizzard adapter | Encounter loot catalog and safe actions |
| `integrations/RCLootCouncil.lua` | `Dibs.RCLootCouncil` | External adapter | RC capability, responses, awards, history reconciliation |
| `integrations/RCLootCouncilOptions.lua` | `Dibs.RCOptions` | External UI adapter | Options projection and registration |
| `integrations/DeveloperSandboxStore.lua` | `Dibs.DeveloperSandboxStore` | Test/dev persistence | Bounded, separate sandbox payloads; never part of production `Dibs.GetDB()` |
| `integrations/DeveloperSandbox.lua` | `Dibs.DeveloperSandbox` | Test/dev | Isolated providers, simulated roles, and fault controls |
| `integrations/DeveloperSandboxScenarios.lua` | `Dibs.DeveloperSandboxScenarios` | Test/dev | Synthetic scenario execution |
| `ui/AceGUI.lua` | `Dibs.AceGUI` | UI toolkit | Containers, tables, callbacks |
| `ui/Midnight.lua` | `Dibs.Midnight` | UI shell | Shared window/status/layout lifecycle |
| `ui/EnvironmentAdapters.lua` | `Dibs.EnvironmentAdapters` | UI adapter | Bounded environment presentation hints without domain authority |
| `ui/WindowState.lua` | `Dibs.WindowState` | UI state | Bounded window position and size restoration |
| `ui/HealthUI.lua` | `Dibs.HealthUI` | UI projection | Read-only version, persistence, readiness, integration, sync, and backup health |
| `ui/SetupAssistant.lua` | `Dibs.SetupAssistant` | UI projection | Transient first-installation checks and protected guided actions |
| `ui/DeveloperUI.lua` | `Dibs.DeveloperUI` | Test/dev UI | Sandbox controls and scenario results |
| `ui/HistoryFilters.lua` | `Dibs.HistoryFilters` | UI projection | Shared read-only history search and date/metadata filters |
| `ui/PlayerUI.lua` | `Dibs.PlayerUI` | UI controller | Player balance, requests, history |
| `ui/OfficerUI.lua` | `Dibs.OfficerUI` | UI controller | Officer navigation and workflows |
| `ui/DataUI.lua` | `Dibs.DataUI` | UI controller | Backup/profile/import workflows |
| `ui/LogsUI.lua` | `Dibs.LogsUI` | UI projection | History and acquisition windows |
| `ui/DebugLogsUI.lua` | `Dibs.DebugLogs` | Diagnostics | Bounded runtime debug log |
| `ui/MinimapButton.lua` | `Dibs.MinimapButton` | UI shortcut | Permission-aware window toggle and per-character icon layout |

Public functions are attached to these namespace tables. Local helpers are implementation details and should not be called by other modules. `CoreAPI` is the stable facade for external callers; persisted names and compatibility aliases must remain stable. B12 UI modules project existing records and route mutations through existing protected services; they do not write ledger, permission, synchronization, or RCLootCouncil authority state directly.
