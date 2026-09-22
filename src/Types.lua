--[[@diagnostic disable: duplicate-set-field
Type declarations for LuaLS/LuaCATS.

This file is intentionally annotation-only.  It is not in the runtime TOC:
the declarations are consumed by editors and static analysis without adding
runtime state or changing addon load order.
]]

---@alias DibsInstallationMode "AUTO"|"STANDALONE"|"RCLootCouncil"
---@alias DibsCapabilityState "absent"|"operational"|"degraded"|"unsupported"
---@alias DibsDifficulty "N"|"H"|"M"|"R"|"ALL"
---@alias DibsLootFamily "TOKEN"|"TOKEN_SET"|"EQUIPMENT"|"COSMETIC"|"CATALYST"|"UNKNOWN"
---@alias DibsRequestStatus "pending"|"confirmed"|"invalidated"|"fulfilled"|"cancelled"
---@alias DibsEligibilityOutcome "ELIGIBLE"|"INELIGIBLE"|"UNKNOWN"|"REVIEW"
---@alias DibsSyncMessageType "HELLO"|"MANIFEST"|"FETCH"|"TRANSFER_BEGIN"|"TRANSFER_CHUNK"|"TRANSFER_END"|"REQUEST_ACK"|"REQUEST"|"VAULT_DIGEST"|"VAULT_FETCH"|"VAULT_DETAIL"|"VAULT_ACK"
---@alias DibsVaultVerificationState "AUTOMATIC_CONFIRMED"|"MANUAL_RECORDED"|"LEGACY_RECORDED"|"UNVERIFIED"|"OFFICER_CONFIRMED"|"REJECTED"|"REFERENCE_ONLY"
---@alias DibsVaultEvidenceState "COMPLETE"|"PARTIAL"|"AMBIGUOUS"|"MISSING"
---@alias DibsActionId "FINALIZE_AWARD"|"MANAGE_DIBS"|"MANAGE_SEASON"|"MANAGE_RANK_RULES"|"MANAGE_SYNC"

---@class DibsSeason
---@field id string Stable season identifier.
---@field name string Display name.
---@field status "active"|"archived"|"draft"
---@field createdAt integer Unix timestamp.
---@field archivedAt integer|nil Unix timestamp.

---@class DibsRankRule
---@field rankIndex integer Guild rank index.
---@field rankName string Guild rank name at configuration time.
---@field allocation integer Number of Dibs granted for the season.

---@class DibsTransaction
---@field transactionId string Immutable transaction identifier.
---@field playerName string Canonical player identity.
---@field seasonId string Season owning the transaction.
---@field amount integer Positive grant or negative use/refund adjustment.
---@field reason string Accounting reason.
---@field source string Source subsystem or audit reference.
---@field createdAt integer Unix timestamp.
---@field rankIndex integer|nil Rank at transaction time.
---@field rankName string|nil Rank name at transaction time.
---@field awardRef string|nil RCLootCouncil award reference.
---@field evidenceId string|nil Evidence reference.

---@class DibsPlayerSeasonState
---@field playerName string Canonical player identity.
---@field seasonId string Season identifier.
---@field balance integer Derived balance from append-only transactions.
---@field transactionIds string[]
---@field updatedAt integer Unix timestamp.

---@class DibsPreDibRequest
---@field requestId string Stable request identifier.
---@field playerName string Request owner.
---@field itemID integer Item identifier.
---@field itemName string|nil Display name captured at request time.
---@field seasonId string Season identifier.
---@field difficulty DibsDifficulty|nil
---@field mode "WILD_OPEN"|"ENCOUNTER"|nil
---@field status DibsRequestStatus
---@field createdAt integer Unix timestamp.
---@field updatedAt integer Unix timestamp.
---@field revision integer Monotonic sync revision.
---@field source string|nil User or test source.

---@class DibsVaultAcquisition
---@field acquisitionId string Stable acquisition identifier.
---@field playerName string Character who acquired the item.
---@field itemID integer
---@field difficulty DibsDifficulty|nil
---@field createdAt integer Unix timestamp.
---@field claimedAt integer Unix timestamp.
---@field guildKey string Guild or character isolation scope.
---@field characterId string|nil Stable character identity.
---@field resetId string|nil Weekly reset identity.
---@field source string Acquisition source; never a ledger use.
---@field verificationState DibsVaultVerificationState
---@field evidenceState DibsVaultEvidenceState
---@field evidenceId string|nil
---@field evidence table|nil Original bounded evidence when available.
---@field originalEvidence table|nil Immutable evidence snapshot retained for review.
---@field review table|nil Latest Officer review decision and audit context.
---@field reviewHistory table[]|nil Prior Officer review decisions.
---@field acquisitionKey string Stable deduplication identity.
---@field revision integer
---@field contentHash string|nil
---@field syncState string
---@field outcome string|nil Acquisition outcome for local/manual recording.
---@field idempotentReplay boolean|nil Whether the returned record was an idempotent replay.

---@class DibsEligibilityPolicy
---@field seasonId string
---@field family DibsLootFamily
---@field tokenCompletionSlots integer
---@field duplicateOutcome "BLOCK"|"REVIEW"|"ALLOW"
---@field difficultyScope DibsDifficulty
---@field matchingScope "FAMILY"|"ITEM"
---@field enforcement "BLOCK"|"REVIEW"|"UNKNOWN"

---@class DibsCharacterEligibilityPolicy
---@field seasonId string
---@field family "TOKEN"|"TOKEN_SET"
---@field enabled boolean
---@field matchingScope "EXACT"|"FAMILY"|"SLOT"|"GROUP"
---@field difficultyScope DibsDifficulty
---@field enforcementOutcome "BLOCK"|"REVIEW"|"ALLOW"
---@field unknownDataBehavior "BLOCK"|"REVIEW"
---@field completionThreshold integer|nil
---@field higherTrackOutcome "BLOCK"|"REVIEW"|"ALLOW"|nil
---@field baselineTrack integer|nil
---@field roundRule "LOWEST_PROGRESS"|nil
---@field tierSetGroupMode "CLASS_TOKEN"|nil
---@field groups table|nil

---@class DibsDisputeRequest
---@field requestId string
---@field category string
---@field status "open"|"in_review"|"waiting"|"resolved"|"reopened"
---@field playerName string
---@field createdAt integer
---@field updatedAt integer
---@field replies table[]
---@field evidence table[]

---@class DibsReconciliationCandidate
---@field candidateId string
---@field historyReference string
---@field winner string
---@field originalOwner string
---@field itemLink string
---@field originalAwardTime integer
---@field originalResponse string
---@field finalStatus string
---@field reason string

---@class DibsReconciliationSession
---@field sessionId string
---@field createdAt integer
---@field status "open"|"completed"|"cancelled"
---@field candidates DibsReconciliationCandidate[]
---@field decisions table<string, string>

---@class DibsBackupSnapshot
---@field snapshotId string
---@field createdAt integer
---@field scope string
---@field size integer
---@field checksum string
---@field payload table

---@class DibsProfile
---@field profileId string
---@field name string
---@field scope string
---@field createdAt integer
---@field updatedAt integer
---@field settings table

---@class DibsIdentitySnapshot
---@field memberKey string Normalized Name-Realm comparison/wire key.
---@field displayName string Name-Realm display value observed at snapshot time.
---@field guidWitness string|nil Optional corroborating GUID; never a wire key.
---@field rosterGeneration integer Current roster generation when observed.

---@class DibsGovernanceRecord
---@field schema integer
---@field recordClass "GOVERNANCE"
---@field guildKey string
---@field governanceRevision integer
---@field parentRevision integer
---@field parentHash string
---@field authorNameRealm string
---@field authorMemberKey string
---@field authorSnapshot DibsIdentitySnapshot
---@field timestamp integer
---@field audit table
---@field content table
---@field contentHash string

---@class DibsSyncEnvelope
---@field type DibsSyncMessageType
---@field version integer
---@field guildKey string
---@field senderId string
---@field requestId string|nil
---@field revision integer|nil
---@field request DibsPreDibRequest|nil
---@field requests table[]|nil
---@field transferId string|nil
---@field chunkCount integer|nil
---@field chunkIndex integer|nil
---@field chunk string|nil

---@class DibsSyncManifest
---@field version integer
---@field guildKey string
---@field type "MANIFEST"
---@field senderId string
---@field requests table[]

---@class DibsGuildDB
---@field version integer Current guild schema version.
---@field currentSeasonId string|nil
---@field seasons table<string, DibsSeason>
---@field rankRules table
---@field ledger table
---@field permissions table
---@field preDibs table
---@field disputes table
---@field reconciliation table
---@field characterEligibility table
---@field governance table
---@field backups DibsBackupSnapshot[]
---@field backupRetention integer
---@field auditLog table[]
---@field pendingRestores table<string, table>
---@field pendingImports table<string, table>
---@field sync table
---@field settings table

---@class Dibs
---@field currentGuildKey string|nil Active guild scope cache.
---@field Midnight table|nil Optional UI compatibility surface.
---@field Debug table|nil Optional developer diagnostics surface.
---@field SetupAssistant table|nil Transient first-installation assistant surface.
---@field HealthUI table|nil Transient Officer health projection surface.
---@field Notifications table|nil Local idempotent notification surface.

---@class DibsSavedVariables
---@field schemaVersion integer Root SavedVariables schema.
---@field guilds table<string, DibsGuildDB>

---@alias DibsEventCallback fun(event:string, ...:any):any
---@alias DibsCommCallback fun(prefix:string, payload:string, channel:string, sender:string):any
---@alias DibsActionCallback fun(actionId:DibsActionId, actor?:string, ...:any):boolean, string?
