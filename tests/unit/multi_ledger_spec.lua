local loader = require("helpers.load_addon")

local function loadGM()
  local _, dibs = loader.load({ wow = { guildLeader = true, playerName = "GM-Realm", guildMembers = { "GM-Realm" }, guildRankIndices = { [1] = 0 } } })
  dibs.SyncV2.BroadcastCatalogDigest = function() return true, "TEST_SENT" end
  return dibs
end

local function loadOfficer()
  local _, dibs = loader.load({ wow = { guildLeader = false, guildMembers = { "Officer-Realm" }, guildRankIndices = { [1] = 1 }, playerName = "Officer-Realm" } })
  return dibs
end

local function loadMember()
  local _, dibs = loader.load({ wow = { guildLeader = false, guildMembers = { "Member-Realm" }, guildRankIndices = { [1] = 4 }, playerName = "Member-Realm" } })
  return dibs
end

describe("MultiLedger lifecycle", function()
  it("initializes with guild-primary as default active ledger", function()
    local dibs = loadGM()
    assert_not_nil(dibs.MultiLedger)
    assert_equal("guild-primary", dibs.MultiLedger.GetActiveLedgerId())
    local ledgers = dibs.MultiLedger.GetLedgers()
    assert_equal(1, #ledgers)
    assert_equal("guild-primary", ledgers[1].id)
    assert_equal("APPROVED", ledgers[1].status)
    assert_true(ledgers[1].isDefault)
  end)

  it("allows verified officer to propose a new ledger", function()
    local dibs = loadOfficer()
    local result = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Roster Alts")
    assert_true(result.ok)
    assert_not_nil(result.ledgerId)

    local ledgers = dibs.MultiLedger.GetLedgers()
    assert_equal(2, #ledgers)
    local altLedger = nil
    for _, l in ipairs(ledgers) do
      if l.id == result.ledgerId then altLedger = l end
    end
    assert_not_nil(altLedger)
    assert_equal("Roster Alts", altLedger.name)
    assert_equal("PROPOSED", altLedger.status)
    assert_equal("Officer-Realm", altLedger.createdBy)
  end)

  it("rejects proposal from non-officer member", function()
    local dibs = loadMember()
    local result = dibs.MultiLedger.ProposeLedger("Member-Realm", "Unauthorized Ledger")
    assert_false(result.ok)
    assert_equal("GUILD_ADMIN_REQUIRED", result.reasonCode)
  end)

  it("rejects invalid or empty ledger names", function()
    local dibs = loadOfficer()
    local result = dibs.MultiLedger.ProposeLedger("Officer-Realm", "")
    assert_false(result.ok)
    assert_equal("INVALID_LEDGER_NAME", result.reasonCode)
  end)

  it("prevents activating a PROPOSED unapproved ledger", function()
    local dibs = loadOfficer()
    local prop = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Trial Roster")
    assert_true(prop.ok)
    local ok, reason = dibs.MultiLedger.SetActiveLedger(prop.ledgerId)
    assert_false(ok)
    assert_equal("LEDGER_UNAPPROVED", reason)
    assert_equal("guild-primary", dibs.MultiLedger.GetActiveLedgerId())
  end)

  it("only allows Guild Master to approve a proposed ledger", function()
    local dibs = loadOfficer()
    local prop = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Mythic Team")
    assert_true(prop.ok)

    -- Officer attempts approval -> rejected
    local officerApprove = dibs.MultiLedger.ApproveLedger("Officer-Realm", prop.ledgerId)
    assert_false(officerApprove.ok)
    assert_equal("GUILD_MASTER_REQUIRED", officerApprove.reasonCode)

    -- Now load GM with the saved DB containing the proposed ledger
    local saved = dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
    local _, gmDibs = loader.load({
      savedVariables = saved,
      wow = { guildLeader = true, playerName = "GM-Realm", guildMembers = { "GM-Realm", "Officer-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 } }
    })
    gmDibs.SyncV2.BroadcastCatalogDigest = function() return true, "TEST_SENT" end

    local gmApprove = gmDibs.MultiLedger.ApproveLedger("GM-Realm", prop.ledgerId)
    assert_true(gmApprove.ok)

    local ledgers = gmDibs.MultiLedger.GetLedgers()
    local approved = nil
    for _, l in ipairs(ledgers) do
      if l.id == prop.ledgerId then approved = l end
    end
    assert_not_nil(approved)
    assert_equal("APPROVED", approved.status)
    assert_equal("GM-Realm", approved.approvedBy)

    -- Now GM can switch to it
    local switchOk = gmDibs.MultiLedger.SetActiveLedger(prop.ledgerId)
    assert_true(switchOk)
    assert_equal(prop.ledgerId, gmDibs.MultiLedger.GetActiveLedgerId())

    local primaryBefore = gmDibs.Ledger.GetBalance("GM-Realm", nil, "guild-primary")
    -- Verify transactions committed while this ledger is active go to this partition
    local grantResult = gmDibs.Ledger.CommitLocalTransaction({ action = "ledger.grant" }, {
      type = "DIB_GRANTED",
      playerName = "GM-Realm",
      amount = 5,
      seasonId = gmDibs.GetCurrentSeasonId(),
    })
    assert_true(grantResult.accepted)
    assert_equal(5, gmDibs.Ledger.GetBalance("GM-Realm"))
    -- Primary ledger balance must be unchanged
    assert_equal(primaryBefore, gmDibs.Ledger.GetBalance("GM-Realm", nil, "guild-primary"))
  end)

  it("keeps approval proposed on audit failure and exposes retryable sync failure", function()
    local dibs = loadGM()
    local prop = dibs.MultiLedger.ProposeLedger("GM-Realm", "Approval Recovery")
    assert_true(prop.ok)
    local ledger = dibs.GetDB().ledgers[prop.ledgerId]
    local originalRecord = dibs.Governance.RecordLedgerApproval
    local originalBroadcast = dibs.SyncV2.BroadcastCatalogDigest
    local broadcastCount = 0

    dibs.Governance.RecordLedgerApproval = function() return false, "AUDIT_WRITE_FAILED" end
    dibs.SyncV2.BroadcastCatalogDigest = function()
      broadcastCount = broadcastCount + 1
      return true
    end
    local auditFailure = dibs.MultiLedger.ApproveLedger("GM-Realm", prop.ledgerId)
    assert_false(auditFailure.ok)
    assert_equal("AUDIT_WRITE_FAILED", auditFailure.reasonCode)
    assert_equal("PROPOSED", ledger.status)
    assert_equal(0, broadcastCount)

    dibs.Governance.RecordLedgerApproval = originalRecord
    dibs.SyncV2.BroadcastCatalogDigest = function()
      broadcastCount = broadcastCount + 1
      return false, "TRANSPORT_OFFLINE"
    end
    local syncFailure = dibs.MultiLedger.ApproveLedger("GM-Realm", prop.ledgerId)
    assert_false(syncFailure.ok)
    assert_equal("SYNC_PENDING", syncFailure.reasonCode)
    assert_equal("TRANSPORT_OFFLINE", syncFailure.syncReasonCode)
    assert_true(syncFailure.localApproved)
    assert_true(syncFailure.retryable)
    assert_equal("APPROVED", ledger.status)

    dibs.SyncV2.BroadcastCatalogDigest = function()
      broadcastCount = broadcastCount + 1
      return true
    end
    local retry = dibs.MultiLedger.ApproveLedger("GM-Realm", prop.ledgerId)
    dibs.Governance.RecordLedgerApproval = originalRecord
    dibs.SyncV2.BroadcastCatalogDigest = originalBroadcast
    assert_true(retry.ok)
    assert_true(retry.replayed)
    assert_equal(2, broadcastCount)
    local approvalEvents = 0
    for _, event in ipairs(dibs.Governance.GetState().auditLog) do
      if event.action == "LEDGER_APPROVED" and event.ledgerId == prop.ledgerId then
        approvalEvents = approvalEvents + 1
      end
    end
    assert_equal(1, approvalEvents)
  end)

  it("allows GM to archive an approved ledger and prevents archiving guild-primary", function()
    local dibs = loadGM()
    -- Try archiving default ledger
    local archDef = dibs.MultiLedger.ArchiveLedger("GM-Realm", "guild-primary")
    assert_false(archDef.ok)
    assert_equal("CANNOT_ARCHIVE_DEFAULT", archDef.reasonCode)

    -- Propose and approve a second ledger
    local prop = dibs.MultiLedger.ProposeLedger("GM-Realm", "Old Raid")
    assert_true(prop.ok)
    local app = dibs.MultiLedger.ApproveLedger("GM-Realm", prop.ledgerId)
    assert_true(app.ok)

    -- Archive it
    local arch = dibs.MultiLedger.ArchiveLedger("GM-Realm", prop.ledgerId)
    assert_true(arch.ok)

    local l = dibs.GetDB().ledgers[prop.ledgerId]
    assert_equal("ARCHIVED", l.status)
  end)

  it("requires confirmation and deletes only archived non-default ledgers", function()
    local dibs = loadGM()
    local prop = dibs.MultiLedger.ProposeLedger("GM-Realm", "Disposable Raid")
    assert_true(prop.ok)
    assert_true(dibs.MultiLedger.ApproveLedger("GM-Realm", prop.ledgerId).ok)
    assert_true(dibs.MultiLedger.ArchiveLedger("GM-Realm", prop.ledgerId).ok)

    local originalSend = dibs.SyncV2.Send
    dibs.SyncV2.Send = function() return true, "TEST_SENT" end
    local missingConfirmation = dibs.MultiLedger.DeleteLedger("GM-Realm", prop.ledgerId, {})
    assert_false(missingConfirmation.ok)
    assert_equal("CONFIRMATION_REQUIRED", missingConfirmation.reasonCode)

    local deleted = dibs.MultiLedger.DeleteLedger("GM-Realm", prop.ledgerId, { confirmed = true })
    dibs.SyncV2.Send = originalSend
    assert_true(deleted.ok)
    assert_nil(dibs.GetDB().ledgers[prop.ledgerId])
    assert_not_nil(dibs.GetDB().ledgerDeletionTombstones[prop.ledgerId])
  end)

  it("records deletion before applying it and retries an unsent tombstone idempotently", function()
    local dibs = loadGM()
    local prop = dibs.MultiLedger.ProposeLedger("GM-Realm", "Deletion Recovery")
    assert_true(prop.ok)
    assert_true(dibs.MultiLedger.ApproveLedger("GM-Realm", prop.ledgerId).ok)
    assert_true(dibs.MultiLedger.ArchiveLedger("GM-Realm", prop.ledgerId).ok)
    local originalPrepare = dibs.Governance.PrepareLedgerDeletion
    local originalSend = dibs.SyncV2.Send

    dibs.Governance.PrepareLedgerDeletion = function() return false, "AUDIT_WRITE_FAILED" end
    dibs.SyncV2.Send = function() error("must not broadcast before audit succeeds") end
    local auditFailure = dibs.MultiLedger.DeleteLedger(
      "GM-Realm", prop.ledgerId, { confirmed = true })
    assert_false(auditFailure.ok)
    assert_equal("AUDIT_WRITE_FAILED", auditFailure.reasonCode)
    assert_not_nil(dibs.GetDB().ledgers[prop.ledgerId])

    dibs.Governance.PrepareLedgerDeletion = originalPrepare
    dibs.SyncV2.Send = function() return false, "TRANSPORT_OFFLINE" end
    local syncFailure = dibs.MultiLedger.DeleteLedger(
      "GM-Realm", prop.ledgerId, { confirmed = true })
    assert_false(syncFailure.ok)
    assert_equal("SYNC_PENDING", syncFailure.reasonCode)
    assert_equal("TRANSPORT_OFFLINE", syncFailure.syncReasonCode)
    assert_false(syncFailure.localDeleted)
    assert_true(syncFailure.retryable)
    assert_not_nil(dibs.GetDB().ledgers[prop.ledgerId])
    assert_nil(dibs.GetDB().ledgerDeletionTombstones[prop.ledgerId])
    assert_not_nil(dibs.GetDB().governance.ledgerDeletionRequests[prop.ledgerId])

    local retryAttempts = 0
    dibs.SyncV2.Send = function()
      retryAttempts = retryAttempts + 1
      return true, "TEST_SENT"
    end
    local retry = dibs.MultiLedger.DeleteLedger(
      "GM-Realm", prop.ledgerId, { confirmed = true })
    assert_true(retry.ok)
    assert_true(retry.replayed)
    assert_equal(1, retryAttempts)
    assert_nil(dibs.GetDB().ledgers[prop.ledgerId])
    local tombstone = dibs.GetDB().ledgerDeletionTombstones[prop.ledgerId]
    assert_true(tombstone.lastBroadcastAt > 0)
    tombstone.lastBroadcastAt = nil
    assert_true(dibs.SyncV2.BroadcastPendingLedgerDeletions())
    assert_equal(2, retryAttempts)
    assert_not_nil(dibs.GetDB().governance.ledgerDeletionRequests[prop.ledgerId])
    dibs.SyncV2.Send = originalSend
    local deletionEvents = 0
    for _, event in ipairs(dibs.Governance.GetState().auditLog) do
      if event.action == "LEDGER_DELETED" and event.ledgerId == prop.ledgerId then
        deletionEvents = deletionEvents + 1
      end
    end
    assert_equal(1, deletionEvents)
  end)

  it("rejects deletion of an archived active ledger without changing it", function()
    local dibs = loadGM()
    local prop = dibs.MultiLedger.ProposeLedger("GM-Realm", "Active Archived")
    assert_true(prop.ok)
    assert_true(dibs.MultiLedger.ApproveLedger("GM-Realm", prop.ledgerId).ok)
    assert_true(dibs.MultiLedger.SetActiveLedger(prop.ledgerId))
    local ledger = dibs.GetDB().ledgers[prop.ledgerId]
    ledger.status = "ARCHIVED"
    local originalSend = dibs.SyncV2.Send
    dibs.SyncV2.Send = function() return true end
    local result = dibs.MultiLedger.DeleteLedger("GM-Realm", prop.ledgerId, { confirmed = true })
    dibs.SyncV2.Send = originalSend
    assert_false(result.ok)
    assert_equal("ACTIVE_LEDGER_CANNOT_DELETE", result.reasonCode)
    assert_equal(prop.ledgerId, dibs.GetDB().activeLedgerId)
    assert_not_nil(dibs.GetDB().ledgers[prop.ledgerId])
    assert_nil(dibs.GetDB().ledgerDeletionTombstones[prop.ledgerId])
  end)

  it("rejects permanent deletion of the default ledger", function()
    local dibs = loadGM()
    local originalSend = dibs.SyncV2.Send
    dibs.SyncV2.Send = function() return true, "TEST_SENT" end
    local result = dibs.MultiLedger.DeleteLedger("GM-Realm", "guild-primary", { confirmed = true })
    dibs.SyncV2.Send = originalSend
    assert_false(result.ok)
    assert_equal("CANNOT_DELETE_DEFAULT", result.reasonCode)
  end)

  it("checks CanBroadcastRaidLedger correctly based on group and guild officer authority", function()
    local _, dibsSoloMember = loader.load({ wow = { inRaid = false, raidLeader = false, guildLeader = false, guildMembers = { "Member-Realm" }, guildRankIndices = { [1] = 4 }, playerName = "Member-Realm" } })
    assert_false(dibsSoloMember.MultiLedger.CanBroadcastRaidLedger())

    -- Raid leadership alone no longer chooses the ledger: GM/Officers only.
    local _, dibsRaidLeader = loader.load({ wow = { inRaid = true, raidLeader = true, guildLeader = false, guildMembers = { "Member-Realm" }, guildRankIndices = { [1] = 4 }, playerName = "Member-Realm" } })
    local allowed, reason = dibsRaidLeader.MultiLedger.CanBroadcastRaidLedger()
    assert_false(allowed)
    assert_equal("GUILD_OFFICER_REQUIRED", reason)

    local _, dibsOfficerInRaid = loader.load({ wow = { inRaid = true, raidLeader = false, guildLeader = false, guildMembers = { "Officer-Realm" }, guildRankIndices = { [1] = 1 }, playerName = "Officer-Realm" } })
    assert_true(dibsOfficerInRaid.MultiLedger.CanBroadcastRaidLedger())
  end)

  it("broadcasts active ledger to raid and applies it on member client", function()
    local _, dibsMember = loader.load({ withAce3 = true, wow = { inRaid = true, raidLeader = false, guildLeader = false, guildMembers = { "Member-Realm", "RL-Realm" }, guildRankIndices = { [1] = 4, [2] = 0 }, playerName = "Member-Realm" } })
    -- Setup an approved second ledger on member client
    local raidLedgerId = "LDR-raid-team-2"
    dibsMember.GetDB().ledgers[raidLedgerId] = {
      id = raidLedgerId,
      name = "Raid Team 2",
      status = "APPROVED",
      createdAt = 1700000000,
      createdBy = "RL-Realm",
    }
    assert_true(dibsMember.Governance.ApplyLedgerApproval("RL-Realm", {
      id = raidLedgerId,
      name = "Raid Team 2",
      status = "APPROVED",
      approvedAt = 1700000000,
      approvedBy = "RL-Realm",
    }))
    assert_equal("guild-primary", dibsMember.MultiLedger.GetActiveLedgerId())

    -- Receive raid sync message from RL
    local payload = {
      action = "SET_ACTIVE_LEDGER",
      ledgerId = raidLedgerId,
      sender = "RL-Realm",
    }
    local serialized = dibsMember.Ace3.Serialize(payload)
    assert_not_nil(serialized)

    -- Simulated receive via OnRaidCommReceived
    local rxOk, rxReason = dibsMember.MultiLedger.OnRaidCommReceived("DIBS_RAID", serialized, "RAID", "RL-Realm")
    assert_true(rxOk)
    assert_equal("LEDGER_SYNCHRONIZED", rxReason)
    assert_equal(raidLedgerId, dibsMember.MultiLedger.GetActiveLedgerId())

    -- Self-messages should be ignored
    dibsMember.MultiLedger.SetActiveLedger(nil, "guild-primary")
    dibsMember.MultiLedger.OnRaidCommReceived("DIBS_RAID", serialized, "RAID", "Member-Realm")
    assert_equal("guild-primary", dibsMember.MultiLedger.GetActiveLedgerId())

    -- Unapproved ledger broadcast should be ignored
    local unapprovedPayload = {
      action = "SET_ACTIVE_LEDGER",
      ledgerId = "non-existent-ledger",
      sender = "RL-Realm",
    }
    local unapprovedSerialized = dibsMember.Ace3.Serialize(unapprovedPayload)
    dibsMember.MultiLedger.OnRaidCommReceived("DIBS_RAID", unapprovedSerialized, "RAID", "RL-Realm")
    assert_equal("guild-primary", dibsMember.MultiLedger.GetActiveLedgerId())
  end)
end)
