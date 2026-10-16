# Public API index

This is a curated entry-point index, not a complete export listing. The
[module inventory](modules.md) covers every first-party TOC module; consult
each source file for its full API. The [generated concept reference](../generated/ui-reference.md)
covers annotated concepts only. Their
implementation remains authoritative; parameters with evolving payload shapes
are represented as `table` and validated at runtime. `CoreAPI` is the preferred
cross-module facade.

## Core and domain

- `Dibs`: `GetGuildKey`, `GetDB`, `NewId`, `GetCurrentSeasonId`, `GetPlayerName`, `GetTimestamp`, `Message`, `DebugEnabled`, `SetDebugLevel`, `GetDebugLevels`, `BuildDebugReport`, `GetFrameworkStatus`, `ApplyDefaultRules`, `HandleSlashCommand`, `SetupSlashCommands`, `RegisterOptionsPanel`, `Initialize`, `SetupRuntimeEvents`.
- `Dibs.CoreAPI`: `createSeason`, `setActiveSeason`, `listSeasons`, `setRankAllocation`, `getRankAllocation`, `getEligibilityPolicy`, `setEligibilityPolicy`, `evaluateEligibility`, `declareCharacterRelationship`, `reviewCharacterRelationship`, `requestMainChange`, `approveMainChange`, `createProbationException`, `appendTransaction`, `getTransactions`, `getPlayerSeasonState`, `canExecuteAuthoritativeAction`.
- `Dibs.Seasons`: `Create`, `GetById`, `GetCurrent`, `GetOrCreateDefault`, `SetCurrent`, `List`, `CreateSeason`, `SetActiveSeason`, `ListSeasons`, `ArchiveSeason`, `RenameSeason`.
- `Dibs.RankRules`: `GetRulesForSeason`, `SetAllocation`, `GetAllocation`, `GetPlayerRankInfo`, `GetAllocationForPlayer`, `SetRankAllocation`, `GetRankAllocation`.
- `Dibs.Permissions`: `CanonicalPlayerId`, `GetGuildRole`, `IsOfficer`, `CanSendReminder`, `IsGM`, `IsStandaloneAdmin`, `GetInstallationMode`, `SetInstallationMode`, `EvaluateStandalone`, `Evaluate`, `Can`, `CanManageDibs`, `ChangeStandaloneAdmin`, `GetRole`.
- `Dibs.Ledger`: `GetPlayerState`, `GetBalance`, `AddTransaction`, `ValidateTransaction`, `AppendTransaction`, `Grant`, `Use`, `Refund`, `AdminAdjust`, `GetTransactionForAward`, `GetTransactionForEvidence`, `RecordHistoricalAward`, `RegisterSeasonAllocation`, `GetHistory`, `GetAllTransactions`, `GetTransactions`, `GetPlayerSeasonState`.
- `Dibs.CharacterEligibility` (legacy alias `Dibs.Eligibility`): `GetPolicy`, `SetPolicy`, `NormalizeFamily`, `GetPlayerGroup`, `DeclareRelationship`, `ReviewRelationship`, `ListRelationships`, `ListMainChanges`, `GetRelationshipStatus`, `RequestMainChange`, `ApproveMainChange`, `GetProbation`, `CreateProbationException`, `GetAcquisitions`, `Evaluate`, `RecordAcquisition`, `ConsumeException`, `GetSummary`.
- `Dibs.PreDibs`: `GetRaidDibsChannel`, `SetAnnouncementDebug`, `DebugRaidDibs`, `FormatAnnouncement`, `NormalizeDifficulty`, `SendTestAnnouncement`, `IsPublicEnabled`, `GetModePolicy`, `SetModePolicy`, `ValidatePublicRequest`, `GetAnnouncementSettings`, `SetAnnouncementChannels`, `GetAnnouncementTemplates`, `SetAnnouncementTemplates`, `Create`, `CreatePublic`, `CreateTest`, `GetTestHistory`, `UpdateStatus`, `UpsertFromSync`, `AcknowledgeDelivery`, `Confirm`, `Cancel`, `CancelForPlayer`, `Invalidate`, `Fulfill`, `GetActiveRequests`, `GetRequestsForItem`, `GetConfirmedRequestForPlayer`, `RecordVaultAcquisition`, `GetAcquisitionsForItem`, `GetAcquisitionsForPlayer`, `GetAcquisitions`, `GetConfirmedRequestsForItem`, `HasConfirmedRequestsForItem`, `GetHistory`.

## Persistence, application, and synchronization

- `Dibs.ProtectedActions`: `FinalizeAward`, `Execute`.
- `Dibs.ImportExport`: `Checksum`, `GetPayload`, `Export`, `Decode`, `Preview`, `Apply`, `RecordAudit`, `Encode`, plus compatibility aliases `Validate`, `PreviewImport`, `ApplyImport`.
- `Dibs.Backup`: `Create`, `List`, `Get`, `PreviewRestore`, `Restore`, `SetRetention`, plus aliases `CreateSnapshot`, `ListSnapshots`, `Preview`, `RestoreSnapshot`.
- `Dibs.Profiles`: `List`, `Get`, `Create`, `Copy`, `Rename`, `PreviewActivation`, `Activate`, `Reset`, `Delete`, `GetActive`, and alias `SetActive`.
- `Dibs.Disputes`: `NormalizeEvidence`, `GetCategories`, `GetStatuses`, `GetActionLabels`, `CreateReport`, `GetRequest`, `ListForPlayer`, `ListForOfficer`, `ListRequests`, `AddReply`, `Resolve`, `BeginReview`, `AskForInformation`, `NoCorrection`, `CorrectBalance`, `CorrectTarget`, `Reopen`, `BuildSafeView`, `BuildOfficerView`, `GetTimeline`, `BuildReport`, `GetCounts`, `IsOfficer`.
- `Dibs.LootPipeline`: `ResolveItem`, `ProcessLootItem`, `RequestDibFromContext`, `GetPendingDevContext`.
- `Dibs.Sync`: `BuildManifest`, `Send`, `Receive`, `OnAddonMessage`, `RegisterTransport`, `OnRosterChanged`, `MarkTransactionSeen`, `HasSeenTransaction`, `RegisterPeer`, `GetPeerState`, `GetDigest`, `SyncSnapshot`, `ContainsForbiddenLiveLootData`, `ApplySnapshot`.
- `Dibs.RaidRelay`: `SetActiveRelay`, `IsActiveRelay`, `GetLocalState`, `Broadcast`, `SendReminder`.
- `Dibs.RaidPrompts`: `IsEnabled`, `SetEnabled`, `GetRaidContext`, `Request`, `Accept`, `Decline`, `OnEvent`.
- `Dibs.Readiness`: `ComputeFingerprint`, `Evaluate`, `Run`, `GetLast`, `Invalidate`, `IsFresh`, `CanProcessLiveAward`, `FormatSummary`, `BuildReport`, `OpenReport`, `CopyReport`, `GetStatusText`.
- `Dibs.DryRun`: `Run`, `RunFromSlash`, `Format`.

## Governance, setup, and follow-up entry points

- `Dibs.Identity`: `RefreshRoster`, `ResolveRosterMember`, `CreateSnapshot`,
  `IsCurrentGuildMaster`. Authority must be resolved from the current roster.
- `Dibs.MultiLedger`: `GetActiveLedgerId`, `GetLedgers`, `GetLedgerById`,
  `SetActiveLedger`, `ProposeLedger(actor, name, options)`,
  `ApproveLedger(actor, ledgerId)`, `ArchiveLedger`, `DeleteLedger`.
  User workflows should use the existing protected UI, not unguarded console calls.
- `Dibs.LootRules`: `GetStatus`, `GetDraftSnapshot`, `GetAuthoritySnapshot`,
  `Adopt`, `PublishDraft`, `GetEffectiveValue`. A draft is not published authority.
- `Dibs.Wizard`: `GetProfiles`, `PreviewProfile`, `ApplyProfile`, `GetTurnkeyStatus`.
- `Dibs.Installation`: `GetStatus`, `Initialize`. Guild Configuration and
  Guided Setup are distinct services.
- `Dibs.Disputes`: also `UpdateFollowUp` and `ReceiveReply`; `Resolve` handles
  reasoned `close` and `archive` actions in addition to existing resolutions.
- `Dibs.RequestDelivery`: `CanQueue`, `CanMutate`, `GetStatus`,
  `QueueSubmission`, `QueueReply`, `OnChanged`, `Receive`, `Snooze`, `Retry`,
  `CheckReminders`, `Pump`. Receipt does not mean resolution.
- `Dibs.AuditExport`: `BuildReport`, `EncodeReport`; output cannot be imported
  as guild transactions or configuration.
- `SyncV2.lua` extends `Dibs.Sync`; it does not define a separate `Dibs.SyncV2`
  facade. See [sync-protocol.md](sync-protocol.md) for transport/acceptance contracts.

## Integrations and UI

- `Dibs.Ace3`: `Has`, `Serialize`, `Deserialize`, `SendComm`, `RegisterComm`, `RegisterEvent`, `ScheduleTimer`, `RegisterOptionsTable`, `AddToBlizOptions`.
- `Dibs.DeveloperMode`: `IsEnabled`, `SetEnabled`, `GetStatusText`, `HandleDevSlash`, `HandleTestItemSlash`.
- `Dibs.EncounterJournal`: `InvalidateLootCatalog`, `GetLootCatalog`, `DumpVisibleLootDebug`, `HandleSubCategorySlash`, `GetSubCategoryMatrixValues`, `IsSubCategoryAllowed`, `SetSubCategoryAllowed`, `ApplyRecommendedSubCategoryMatrix`, `AddActionIfAvailable`, `BuildActionLabel`, `OpenForRaidContext`, `OpenLootItem`, `CanPreDib`, `SubmitPreDib`.
- `Dibs.RCLootCouncil`: `IsDibEnabledForType`, `SetDibEnabledForType`, `GetTypePolicyRevision`, `GetItemSemanticFamilies`, `GetItemSemanticFamily`, `IsItemDibTypeAllowed`, `NormalizeDibResponse`, `IsDibResponse`, `GetConfigProjectionStatus`, `RefreshConfigProjection`, `ValidateAwardInput`, `LogPreDibRequest`, `GetDibsColumnValue`, `GetVotingIntegrationStatus`, `GetCapabilities`, `GetAvailability`, `IsAvailable`, `EvaluateAuthority`, `CanUseDibResponse`, `GetStatusForCandidate`, `ValidateResponse`, `OnAwardSuccess`, `Initialize`, `TryUseRCModule`, `GetLocalStatus`, `GetAwardEvidence`, `BuildAwardEvidence`, `NormalizeResponseAlias`, `NormalizeResponseAliases`, `GetReconciliationAliases`, `SetReconciliationAliases`, `GetHistoryRows`, `CreateReconciliationSession`, `GetReconciliationSession`, `ListReconciliationSessions`, `ConfirmReconciliationCandidate`, `RejectReconciliationCandidate`, plus compatibility aliases `StartHistoryReconciliation`, `GetHistoryReconciliationPreview`, `ConfirmHistoryCandidate`.
- `Dibs.RCOptions`: `IsOfficerPreview`, `IsOfficerPreviewOnly`, `GetLootTypeOptions`, `GetOptionsTable`, `Open`, `EnsureRegistered`.
- `Dibs.PlayerUI`: `GetSummary`, `RecordVaultAcquisition`, `GetHistory`, `CreateWindow`, `SetDevContext`, `Show`, `Toggle`, and compatibility alias `SubmitPreDib`.
- `Dibs.OfficerUI`: `GetLedgerOverview`, `BuildLedgerDetails`, `BuildPreDibDetails`, `GetPagedView`, `BuildSeasonStatistics`, `BuildDashboardDetails`, `SetPreDibMode`, `GetRankChangeDiagnostics`, `BuildStatusText`, `CreateWindow`, `ManageStandaloneAdmin`, `GetCandidateFallback`, `Show`, `Toggle`, `CreateSeason`.
- `Dibs.LogsUI`: `Open`, `OpenPlayerHistory`, `OpenPlayerAcquisitions`, `OpenOfficer`.
- `Dibs.DebugLogs`: `Add`, `Clear`, `Open`.
- `Dibs.MinimapButton`: `GetVisible`, `SetVisible`, `GetScale`, `SetScale`,
  `GetAngle`, `SetAngle`, `ResetLayout`, `Initialize`. Move/resize was added
  in 0.8.9; preferences are per character and never grant authority.
- `Dibs.AceGUI`: `IsAvailable`, `CreateWindow`, `Create`, `Clear`, `SetText`, `SetDisabled`, `SetValue`, `AddTooltip`, `AddHeader`, `AddSection`, `AddInlineGroup`, `AddLabel`, `AddTable`, `AddPropertyTable`, `AddButton`, `AddEditBox`, `AddSelectableText`, `SelectText`, `AddMSADropdown`, `AddDropdown`, `AddCheckBox`, `AddRange`, `AddTabs`, `AddHeading`, `AddTree`, `SelectTree`, `RenderOptionsGroup`, `AddScrollableList`, `AddSearch`, and `AddPagination`; `AddTable` is the shared DIBS Data Grid with sorting, row selection/clicks, tooltips, context menus, responsive columns, and pooled-widget cleanup. Call UI infrastructure through the adapter rather than native duplicate controls.

For model fields and callback signatures see `src/Types.lua`. For authorization,
side effects, and error conditions see the owning module header and the guides
linked from [architecture.md](architecture.md).
