local loader = require("helpers.load_addon")

local ROSTER = { "Tester-Realm", "Officer-Realm", "Player-Realm" }
local RANKS = { [1] = 0, [2] = 1, [3] = 3 }

local function load()
  local wow = { guildLeader = true, guildMembers = ROSTER, guildRankIndices = RANKS }
  local dibs = select(2, loader.load({ withAce3 = true, wow = wow }))
  dibs.SyncV2.BroadcastCatalogDigest = function() return true, "TEST_SENT" end
  return dibs
end

local function adoptGovernance(dibs)
  local ok, reason = dibs.Governance.AdoptInitial(nil, {
    reason = "guild active ledger test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  })
  assert_true(ok, tostring(reason))
end

local function approvedLedger(dibs, name)
  local proposal = dibs.MultiLedger.ProposeLedger(nil, name)
  assert_true(proposal.ok)
  assert_true(dibs.MultiLedger.ApproveLedger(nil, proposal.ledgerId).ok)
  return proposal.ledgerId
end

local function mirrorLedger(target, ledgerId, name)
  target.GetDB().ledgers[ledgerId] = { id = ledgerId, name = name, status = "APPROVED", createdAt = 1700000000, createdBy = "Tester-Realm" }
  assert_true(target.Governance.ApplyLedgerApproval("Tester-Realm", {
    id = ledgerId, name = name, status = "APPROVED", approvedAt = 1700000000, approvedBy = "Tester-Realm",
  }))
end

describe("Guild active ledger imposed through operational policy", function()
  it("rejects malformed ledger identifiers in the policy", function()
    local dibs = load(); adoptGovernance(dibs)
    local ok, reason = dibs.OperationalPolicy.SetActiveLedger("bad id with spaces", nil)
    assert_false(ok); assert_equal("INVALID_ACTIVE_LEDGER", reason)
    ok, reason = dibs.OperationalPolicy.SetActiveLedger(string.rep("a", 65), nil)
    assert_false(ok); assert_equal("INVALID_ACTIVE_LEDGER", reason)
  end)

  it("lets the GM impose a ledger, seeding the initial policy with local settings", function()
    local dibs = load(); adoptGovernance(dibs)
    dibs.GetDB().settings.allowPublicPreDibs = false
    local ledgerId = approvedLedger(dibs, "Raid Team 2")
    assert_true(dibs.MultiLedger.CanSetGuildActiveLedger())
    local ok, reason = dibs.MultiLedger.SetGuildActiveLedger(ledgerId)
    assert_true(ok, tostring(reason))
    assert_equal(ledgerId, dibs.OperationalPolicy.GetActiveLedgerId())
    assert_equal(ledgerId, dibs.MultiLedger.GetActiveLedgerId())
    assert_false(dibs.PreDibs.IsPublicEnabled())
    local status = dibs.MultiLedger.GetGuildLedgerStatus()
    assert_equal("IMPOSED", status.state)
    assert_equal("Raid Team 2", status.activeLedgerName)

    local switched, switchReason = dibs.MultiLedger.SetActiveLedger("guild-primary")
    assert_false(switched); assert_equal("GUILD_ACTIVE_LEDGER_IMPOSED", switchReason)
    local archived = dibs.MultiLedger.ArchiveLedger(nil, ledgerId)
    assert_false(archived.ok); assert_equal("GUILD_ACTIVE_LEDGER_CANNOT_ARCHIVE", archived.reasonCode)

    local again, againReason = dibs.MultiLedger.SetGuildActiveLedger(ledgerId)
    assert_true(again); assert_equal("UNCHANGED", againReason)
  end)

  it("applies the imposed ledger on a member client and fails closed until the ledger is known", function()
    local gm = load(); adoptGovernance(gm)
    local ledgerId = approvedLedger(gm, "Raid Team 2")
    assert_true(gm.MultiLedger.SetGuildActiveLedger(ledgerId))
    local record = gm.OperationalPolicy.GetCurrentRecord()

    assert_true(gm.MultiLedger.CanSetGuildActiveLedger("Officer-Realm"))
    assert_false(gm.MultiLedger.CanSetGuildActiveLedger("Player-Realm"))
    local denied, deniedReason = gm.MultiLedger.SetGuildActiveLedger("guild-primary", "Player-Realm")
    assert_false(denied); assert_not_nil(deniedReason)
    assert_equal(ledgerId, gm.MultiLedger.GetActiveLedgerId())

    local member = load(); adoptGovernance(member)
    assert_true(member.OperationalPolicy.ApplyRecord(record, "Tester-Realm"))
    assert_equal("UNAVAILABLE", member.MultiLedger.GetGuildLedgerStatus().state)
    local allowed, reason = member.MultiLedger.RequireGuildActiveLedger()
    assert_false(allowed); assert_equal("GUILD_ACTIVE_LEDGER_UNAVAILABLE", reason)
    local request, createReason = member.PreDibs.Create("Player-Realm", 12345)
    assert_nil(request); assert_equal("GUILD_ACTIVE_LEDGER_UNAVAILABLE", createReason)

    mirrorLedger(member, ledgerId, "Raid Team 2")
    assert_equal(ledgerId, member.MultiLedger.GetActiveLedgerId())
    assert_equal("IMPOSED", member.MultiLedger.GetGuildLedgerStatus().state)
    assert_true(member.MultiLedger.RequireGuildActiveLedger())
  end)

  it("ignores legacy raid ledger messages once a guild ledger is imposed", function()
    local dibs = load(); adoptGovernance(dibs)
    local imposed = approvedLedger(dibs, "Imposed")
    local other = approvedLedger(dibs, "Other")
    assert_true(dibs.MultiLedger.SetGuildActiveLedger(imposed))
    local payload = dibs.Ace3.Serialize({ action = "SET_ACTIVE_LEDGER", ledgerId = other, sender = "Officer-Realm" })
    local ok, reason = dibs.MultiLedger.OnRaidCommReceived("DIBS_RAID", payload, "RAID", "Officer-Realm")
    assert_false(ok); assert_equal("GUILD_ACTIVE_LEDGER_IMPOSED", reason)
    assert_equal(imposed, dibs.MultiLedger.GetActiveLedgerId())
  end)

  it("views another ledger read-only without changing the working ledger", function()
    local dibs = load(); adoptGovernance(dibs)
    local imposed = approvedLedger(dibs, "Imposed")
    assert_true(dibs.MultiLedger.SetGuildActiveLedger(imposed))
    assert_true(dibs.MultiLedger.SetViewLedger("guild-primary"))
    assert_equal("guild-primary", dibs.MultiLedger.GetViewLedgerId())
    assert_equal(imposed, dibs.MultiLedger.GetActiveLedgerId())
    assert_true(dibs.MultiLedger.IsViewingOtherLedger())
    local status = dibs.MultiLedger.GetGuildLedgerStatus()
    assert_equal("guild-primary", status.viewLedgerId)
    assert_true(dibs.MultiLedger.SetViewLedger(imposed))
    assert_false(dibs.MultiLedger.IsViewingOtherLedger())
    local text = dibs.AceGUI.BuildShellStatusText()
    assert_true(string.find(text, "Imposed", 1, true) ~= nil)
    assert_true(string.find(text, "Imposed (Active)", 1, true) ~= nil)
    assert_true(string.find(text, tostring(dibs.VERSION), 1, true) ~= nil)
  end)

  it("offers the footer ledger menu with Active and Read only states", function()
    local dibs = load(); adoptGovernance(dibs)
    local imposed = approvedLedger(dibs, "Imposed")
    assert_true(dibs.MultiLedger.SetGuildActiveLedger(imposed))
    local values = dibs.AceGUI.GetLedgerDropdownValues()
    assert_equal("Imposed (Active)", values[imposed])
    assert_equal("Primary", values["guild-primary"])

    local function fakeRoot()
      local root = { titles = {}, radios = {} }
      function root:CreateTitle(text) self.titles[#self.titles + 1] = text end
      function root:CreateDivider() end
      function root:CreateRadio(text, isSelected, select, data)
        self.radios[#self.radios + 1] = { text = text, isSelected = isSelected, select = select, data = data }
      end
      return root
    end

    local root = fakeRoot()
    assert_true(dibs.AceGUI.PopulateLedgerMenu(root))
    assert_equal(1, #root.titles)
    assert_equal(2, #root.radios)
    assert_true(root.radios[2].isSelected())
    assert_equal("Primary (Read only)", root.radios[1].text)
    root.radios[1].select()
    assert_equal("guild-primary", dibs.MultiLedger.GetViewLedgerId())
    assert_equal(imposed, dibs.MultiLedger.GetActiveLedgerId())
    assert_equal(imposed, dibs.OperationalPolicy.GetActiveLedgerId())

    dibs.MultiLedger.CanSetGuildActiveLedger = function() return false end
    root = fakeRoot()
    assert_true(dibs.AceGUI.PopulateLedgerMenu(root))
    assert_equal(1, #root.titles)
    assert_equal(2, #root.radios)
    assert_equal("Imposed (Active)", root.radios[2].text)
    root.radios[2].select()
    assert_equal(imposed, dibs.MultiLedger.GetViewLedgerId())
    assert_equal(imposed, dibs.MultiLedger.GetActiveLedgerId())
  end)

  it("reports guild sync failures and retries without creating another policy revision", function()
    local dibs = load(); adoptGovernance(dibs)
    local other = approvedLedger(dibs, "Other")
    dibs.Sync.Send = function() return false, "SYNC_UNAVAILABLE" end
    local ok, _, sent, reason = dibs.MultiLedger.SetGuildActiveLedger(other)
    assert_true(ok)
    assert_false(sent)
    assert_equal("SYNC_UNAVAILABLE", reason)
    local revision = dibs.OperationalPolicy.GetState().policyRevision
    local calls = 0
    dibs.Sync.Send = function(message, channel)
      calls = calls + 1
      assert_equal("OPERATIONAL_POLICY", message.entityType)
      assert_equal("GUILD", channel)
      return true, "TEST_SENT"
    end
    ok, _, sent = dibs.MultiLedger.SetGuildActiveLedger(other)
    assert_true(ok)
    assert_true(sent)
    assert_equal(1, calls)
    assert_equal(revision, dibs.OperationalPolicy.GetState().policyRevision)
    local denied = dibs.MultiLedger.SetGuildActiveLedger(other, "Player-Realm")
    assert_false(denied)
    assert_equal(1, calls)
  end)

  it("scopes pending award reservations to their ledger", function()
    local dibs = load(); adoptGovernance(dibs)
    local other = approvedLedger(dibs, "Other")
    local memberKey = dibs.Identity.CanonicalMemberKey("Player-Realm")
    local season = dibs.GetCurrentSeasonId()
    dibs.Governance.GetAwardProposals = function()
      return {
        { proposalId = "p-primary", type = "AWARD", status = "PENDING", amount = 1, seasonId = season,
          ledgerId = "guild-primary", playerSnapshot = { memberKey = memberKey } },
        { proposalId = "p-other", type = "AWARD", status = "PENDING", amount = 2, seasonId = season,
          ledgerId = other, playerSnapshot = { memberKey = memberKey } },
        { proposalId = "p-legacy", type = "AWARD", status = "PENDING", amount = 4, seasonId = season,
          playerSnapshot = { memberKey = memberKey } },
      }
    end
    -- Legacy proposals without a ledger count against the active ledger.
    assert_equal(5, dibs.Ledger.GetPendingDibReservations("Player-Realm", season))
    assert_equal(5, dibs.Ledger.GetPendingDibReservations("Player-Realm", season, "guild-primary"))
    assert_equal(2, dibs.Ledger.GetPendingDibReservations("Player-Realm", season, other))
  end)
end)
