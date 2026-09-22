# Module inventory

The following inventory covers first-party files in the TOC. Embedded libraries are documented as dependencies rather than re-described as Dibs modules.

| File | Namespace | Layer | Main responsibility |
| --- | --- | --- | --- |
| `Core.lua` | `Dibs` / `Dibs.CoreAPI` | Composition | Startup, SavedVariables migration, slash/API facade, WoW event routing |
| `Types.lua` | LuaLS global aliases/classes | Static documentation | Annotation-only domain models and callback signatures; not loaded at runtime |
| `modules/Seasons.lua` | `Dibs.Seasons` | Domain | Season lifecycle |
| `modules/RankRules.lua` | `Dibs.RankRules` | Domain | Rank-to-allocation policy |
| `modules/Ledger.lua` | `Dibs.Ledger` | Accounting | Append-only transactions and balances |
| `modules/Permissions.lua` | `Dibs.Permissions` | Policy | Guild identity and authority |
| `modules/ProtectedActions.lua` | `Dibs.ProtectedActions` | Application | Permission/readiness/combat gate |
| `modules/ImportExport.lua` | `Dibs.ImportExport` | Persistence | Bounded package preview/apply |
| `modules/Profiles.lua` | `Dibs.Profiles` | Persistence | Named configuration projections |
| `modules/Backup.lua` | `Dibs.Backup` | Persistence | Recovery snapshots and retention |
| `modules/Disputes.lua` | `Dibs.Disputes` | Audit | Reports, replies, corrections |
| `modules/PreDibs.lua` | `Dibs.PreDibs` | Domain | Request lifecycle and announcements |
| `modules/Notifications.lua` | `Dibs.Notifications` | Player presentation | Localized, private, idempotent personal notifications |
| `modules/CharacterEligibility.lua` | `Dibs.CharacterEligibility` (`Dibs.Eligibility` compatibility alias) | Domain | Main/alt, Curio, Tier Set eligibility |
| `modules/LootPipeline.lua` | `Dibs.LootPipeline` | Application | Item normalization and award context |
| `modules/Sync.lua` | `Dibs.Sync` | Distributed | Guild-scoped metadata synchronization |
| `modules/RaidRelay.lua` | `Dibs.RaidRelay` | Application | Active relay and reminders |
| `modules/RaidPrompts.lua` | `Dibs.RaidPrompts` | Player workflow | Encounter prompts |
| `modules/Readiness.lua` | `Dibs.Readiness` | Runtime guard | Live-context and combat readiness |
| `modules/DryRun.lua` | `Dibs.DryRun` | Test/dev | Non-mutating command evaluation |
| `integrations/Ace3.lua` | `Dibs.Ace3` | Framework adapter | Optional Ace3 capabilities |
| `integrations/DeveloperMode.lua` | `Dibs.DeveloperMode` | Test/dev | Diagnostic/test commands |
| `integrations/EncounterJournal.lua` | `Dibs.EncounterJournal` | Blizzard adapter | Encounter loot catalog and safe actions |
| `integrations/RCLootCouncil.lua` | `Dibs.RCLootCouncil` | External adapter | RC capability, responses, awards, history reconciliation |
| `integrations/RCLootCouncilOptions.lua` | `Dibs.RCOptions` | External UI adapter | Options projection and registration |
| `integrations/DeveloperSandboxStore.lua` | `Dibs.DeveloperSandboxStore` | Test/dev persistence | Bounded, separate sandbox payloads; never part of production `Dibs.GetDB()` |
| `ui/AceGUI.lua` | `Dibs.AceGUI` | UI toolkit | Containers, tables, callbacks |
| `ui/Midnight.lua` | `Dibs.Midnight` | UI shell | Shared window/status/layout lifecycle |
| `ui/WindowState.lua` | `Dibs.WindowState` | UI state | Bounded window position and size restoration |
| `ui/HealthUI.lua` | `Dibs.HealthUI` | UI projection | Read-only version, persistence, readiness, integration, sync, and backup health |
| `ui/SetupAssistant.lua` | `Dibs.SetupAssistant` | UI projection | Transient first-installation checks and protected guided actions |
| `ui/PlayerUI.lua` | `Dibs.PlayerUI` | UI controller | Player balance, requests, history |
| `ui/OfficerUI.lua` | `Dibs.OfficerUI` | UI controller | Officer navigation and workflows |
| `ui/DataUI.lua` | `Dibs.DataUI` | UI controller | Backup/profile/import workflows |
| `ui/LogsUI.lua` | `Dibs.LogsUI` | UI projection | History and acquisition windows |
| `ui/DebugLogsUI.lua` | `Dibs.DebugLogs` | Diagnostics | Bounded runtime debug log |

Public functions are attached to these namespace tables. Local helpers are implementation details and should not be called by other modules. `CoreAPI` is the stable facade for external callers; persisted names and compatibility aliases must remain stable. B12 UI modules project existing records and route mutations through existing protected services; they do not write ledger, permission, synchronization, or RCLootCouncil authority state directly.
