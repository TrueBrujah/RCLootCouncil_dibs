local loader = require("helpers.load_addon")

describe("Core API contract", function()
  it("exposes stable season, rank, ledger, and authorization operations", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, playerName = "Tester-Realm", playerGUID = "Player-1-TESTER" } })

    local season = dibs.CoreAPI.createSeason({ name = "ContractSeason" })
    assert_not_nil(season)
    assert_not_nil(season.id)

    local active = dibs.CoreAPI.setActiveSeason({ seasonId = season.id })
    assert_equal(season.id, active.activeSeasonId)

    local list = dibs.CoreAPI.listSeasons()
    assert_true(type(list.seasons) == "table")
    assert_true(#list.seasons >= 1)

    local setRank = dibs.CoreAPI.setRankAllocation({ seasonId = season.id, rankIndex = 1, allocation = 3, rankName = "Officer" })
    assert_equal(3, setRank.allocation)

    local getRank = dibs.CoreAPI.getRankAllocation({ seasonId = season.id, rankIndex = 1 })
    assert_equal(3, getRank.allocation)

    local txId = "tx-contract-001"
    local append = dibs.CoreAPI.appendTransaction({
      transactionId = txId,
      timestamp = time(),
      seasonId = season.id,
      playerGuid = "Player-1-TESTER",
      playerName = "Tester-Realm",
      actionType = "DIB_GRANTED",
      quantityDelta = 2,
      reason = "Contract grant",
    })
    assert_true(append.accepted)
    assert_false(append.idempotentReplay)

    local replay = dibs.CoreAPI.appendTransaction({
      transactionId = txId,
      timestamp = time(),
      seasonId = season.id,
      playerGuid = "Player-1-TESTER",
      playerName = "Tester-Realm",
      actionType = "DIB_GRANTED",
      quantityDelta = 2,
      reason = "Contract grant replay",
    })
    assert_true(replay.accepted)
    assert_true(replay.idempotentReplay)

    local history = dibs.CoreAPI.getTransactions({ seasonId = season.id, playerGuid = "Player-1-TESTER" })
    assert_true(type(history.transactions) == "table")
    assert_equal(1, #history.transactions)

    local state = dibs.CoreAPI.getPlayerSeasonState({ seasonId = season.id, playerGuid = "Player-1-TESTER" })
    assert_not_nil(state)
    assert_equal(2, state.remainingBalance)

    local auth = dibs.CoreAPI.canExecuteAuthoritativeAction({ actionId = "ledger.grant", actor = nil })
    assert_true(auth.allowed)
  end)

  it("keeps core APIs stable with embedded Ace3 services", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    local season = dibs.CoreAPI.createSeason({ name = "Ace3 contract" })
    local rank = dibs.CoreAPI.setRankAllocation({ seasonId = season.id, rankIndex = 1, allocation = 4 })

    assert_true(dibs.Ace3.Has("event"))
    assert_true(dibs.Ace3.Has("gui"))
    assert_not_nil(dibs.Ace3.handlers.events.PLAYER_LOGIN)
    assert_true(dibs.AceGUI.IsAvailable())
    assert_not_nil(dibs.AceGUI.CreateWindow("Probe", 100, 100, { "CENTER", 0, 0 }))
    assert_equal(4, rank.allocation)
    assert_not_nil(dibs.PlayerUI.CreateWindow().dibsAceGUIShell)
    assert_not_nil(dibs.OfficerUI.CreateWindow().dibsAceGUIShell)
  end)

  it("does not let a non-admin call mutating CoreAPI methods", function()
    local _, dibs = loader.load({ wow = { guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } } })
    assert_nil(dibs.CoreAPI.createSeason({ name = "forged" }))
    assert_nil(dibs.CoreAPI.setActiveSeason({ seasonId = dibs.GetCurrentSeasonId() }))
    local result = dibs.CoreAPI.appendTransaction({
      transactionId = "forged-core-api",
      timestamp = time(),
      seasonId = dibs.GetCurrentSeasonId(),
      playerName = "Tester-Realm",
      actionType = "DIB_GRANTED",
      quantityDelta = 99,
      reason = "forged",
    })
    assert_false(result.accepted)
    assert_equal("GUILD_ADMIN_REQUIRED", result.reasonCode)
  end)

  it("does not expose another player's ledger through CoreAPI reads", function()
    local _, dibs = loader.load({ wow = { guildLeader = false, guildMembers = { "Tester-Realm", "Other-Realm", "Officer-Realm" }, guildRankIndices = { [1] = 3, [2] = 3, [3] = 1 } } })
    local seasons = dibs.CoreAPI.listSeasons()
    assert_equal(0, #seasons.seasons)
    assert_equal("OFFICER_SCOPE_REQUIRED", seasons.reasonCode)
    local rank, rankReason = dibs.CoreAPI.getRankAllocation({ seasonId = dibs.GetCurrentSeasonId(), rankIndex = 1 })
    assert_nil(rank)
    assert_equal("OFFICER_SCOPE_REQUIRED", rankReason)
    local forgedScope = dibs.CoreAPI.getTransactions({ actor = "Officer-Realm", seasonId = dibs.GetCurrentSeasonId() })
    assert_equal(0, #forgedScope.transactions)
    assert_equal("PLAYER_SCOPE_REQUIRED", forgedScope.reasonCode)
    local history = dibs.CoreAPI.getTransactions({ seasonId = dibs.GetCurrentSeasonId(), playerGuid = "Other-Realm" })
    assert_equal(0, #history.transactions)
    assert_equal("PLAYER_SCOPE_REQUIRED", history.reasonCode)
    local state, reason = dibs.CoreAPI.getPlayerSeasonState({ seasonId = dibs.GetCurrentSeasonId(), playerGuid = "Other-Realm" })
    assert_nil(state)
    assert_equal("PLAYER_SCOPE_REQUIRED", reason)
  end)
end)
