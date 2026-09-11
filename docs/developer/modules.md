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
| `ui/AceGUI.lua` | `Dibs.AceGUI` | UI toolkit | Containers, tables, callbacks |
| `ui/PlayerUI.lua` | `Dibs.PlayerUI` | UI controller | Player balance, requests, history |
| `ui/OfficerUI.lua` | `Dibs.OfficerUI` | UI controller | Officer navigation and workflows |
| `ui/DataUI.lua` | `Dibs.DataUI` | UI controller | Backup/profile/import workflows |
| `ui/LogsUI.lua` | `Dibs.LogsUI` | UI projection | History and acquisition windows |
| `ui/DebugLogsUI.lua` | `Dibs.DebugLogs` | Diagnostics | Bounded runtime debug log |

Public functions are attached to these namespace tables. Local helpers are implementation details and should not be called by other modules. `CoreAPI` is the stable facade for external callers; persisted names and compatibility aliases must remain stable.
