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
---@alias DibsSyncMessageType "HELLO"|"MANIFEST"|"FETCH"|"TRANSFER_BEGIN"|"TRANSFER_CHUNK"|"TRANSFER_END"|"REQUEST_ACK"|"REQUEST"
---@alias DibsActionId "FINALIZE_AWARD"|"MANAGE_DIBS"|"MANAGE_SEASON"|"MANAGE_RANK_RULES"|"MANAGE_SYNC"

---@class DibsSeason
---@field id string Stable season identifier.
---@field name string Display name.
---@field status "active"|"archived"|"draft"
---@field createdAt integer Unix timestamp.
---@field archivedAt? integer Unix timestamp.

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
---@field rankIndex? integer Rank at transaction time.
---@field rankName? string Rank name at transaction time.
---@field awardRef? string RCLootCouncil award reference.
---@field evidenceId? string Evidence reference.

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
---@field itemName? string Display name captured at request time.
---@field seasonId string Season identifier.
---@field difficulty? DibsDifficulty
---@field mode? "WILD_OPEN"|"ENCOUNTER"
---@field status DibsRequestStatus
---@field createdAt integer Unix timestamp.
---@field updatedAt integer Unix timestamp.
---@field revision integer Monotonic sync revision.
---@field source? string User or test source.

---@class DibsVaultAcquisition
---@field acquisitionId string Stable acquisition identifier.
---@field playerName string Character who acquired the item.
---@field itemID integer
---@field difficulty? DibsDifficulty
---@field createdAt integer Unix timestamp.
---@field source string Acquisition source; display-only and never a ledger use.

---@class DibsEligibilityPolicy
---@field seasonId string
---@field family DibsLootFamily
---@field tokenCompletionSlots integer
---@field duplicateOutcome "BLOCK"|"REVIEW"|"ALLOW"
---@field difficultyScope DibsDifficulty
---@field matchingScope "FAMILY"|"ITEM"
---@field enforcement "BLOCK"|"REVIEW"|"UNKNOWN"

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

---@class DibsSyncEnvelope
---@field type DibsSyncMessageType
---@field version integer
---@field guildKey string
---@field senderId string
---@field requestId? string
---@field revision? integer
---@field request? DibsPreDibRequest
---@field requests? table[]
---@field transferId? string
---@field chunkCount? integer
---@field chunkIndex? integer
---@field chunk? string

---@class DibsSyncManifest
---@field version integer
---@field guildKey string
---@field type "MANIFEST"
---@field senderId string
---@field requests table[]

---@class DibsGuildDB
---@field version integer Current guild schema version.
---@field currentSeasonId? string
---@field seasons table<string, DibsSeason>
---@field rankRules table
---@field ledger table
---@field permissions table
---@field preDibs table
---@field disputes table
---@field reconciliation table
---@field characterEligibility table
---@field backups DibsBackupSnapshot[]
---@field backupRetention integer
---@field auditLog table[]
---@field sync table
---@field settings table

---@class DibsSavedVariables
---@field schemaVersion integer Root SavedVariables schema.
---@field guilds table<string, DibsGuildDB>

---@alias DibsEventCallback fun(event:string, ...:any):any
---@alias DibsCommCallback fun(prefix:string, payload:string, channel:string, sender:string):any
---@alias DibsActionCallback fun(actionId:DibsActionId, actor?:string, ...:any):boolean, string?
