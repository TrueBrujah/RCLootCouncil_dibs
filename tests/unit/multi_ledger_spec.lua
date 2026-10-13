local loader = require("helpers.load_addon")

local function loadGM()
  local _, dibs = loader.load({ wow = { guildLeader = true, playerName = "GM-Realm", guildMembers = { "GM-Realm" }, guildRankIndices = { [1] = 0 } } })
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

  it("rejects permanent deletion of the default ledger", function()
    local dibs = loadGM()
    local originalSend = dibs.SyncV2.Send
    dibs.SyncV2.Send = function() return true, "TEST_SENT" end
    local result = dibs.MultiLedger.DeleteLedger("GM-Realm", "guild-primary", { confirmed = true })
    dibs.SyncV2.Send = originalSend
    assert_false(result.ok)
    assert_equal("CANNOT_DELETE_DEFAULT", result.reasonCode)
  end)

  it("checks CanBroadcastRaidLedger correctly based on group and rank authority", function()
    local _, dibsSoloMember = loader.load({ wow = { inRaid = false, raidLeader = false, guildLeader = false, guildMembers = { "Member-Realm" }, guildRankIndices = { [1] = 4 }, playerName = "Member-Realm" } })
    assert_false(dibsSoloMember.MultiLedger.CanBroadcastRaidLedger())

    local _, dibsRaidLeader = loader.load({ wow = { inRaid = true, raidLeader = true, guildLeader = false, guildMembers = { "Member-Realm" }, guildRankIndices = { [1] = 4 }, playerName = "Member-Realm" } })
    assert_true(dibsRaidLeader.MultiLedger.CanBroadcastRaidLedger())

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
