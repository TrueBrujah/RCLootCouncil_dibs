local loader = require("helpers.load_addon")

local function load(opts)
  local _, dibs = loader.load(opts or { wow = { guildLeader = true } })
  return dibs
end

local function command(dibs, fields, context)
  local value = {
    transactionId = "b03-" .. tostring(fields.transactionId or "tx"),
    type = fields.type or "DIB_USED",
    playerName = fields.playerName or "Tester-Realm",
    seasonId = fields.seasonId or dibs.GetCurrentSeasonId(),
    amount = fields.amount == nil and -1 or fields.amount,
    reason = fields.reason or "B03 test",
    source = fields.source or "b03-test",
    playerGuid = fields.playerGuid,
    awardRef = fields.awardRef,
  }
  -- Use internal=true for direct CommitLocalTransaction calls in tests
  local ctx = context or { action = "ledger.use", internal = true }
  return dibs.Ledger.CommitLocalTransaction(ctx, value, context and context.ledgerId)
end

describe("B03 local canonical ledger", function()
  it("detects non-allocation history with an early-exit cache invalidated on ledger changes", function()
    local dibs = load()
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    ledger.transactions = {
      allocation = { type = "SEASON_ALLOCATION" },
    }
    dibs.Ledger.MarkTransactionsChanged("guild-primary")
    assert_false(dibs.Ledger.HasNonAllocationTransactions("guild-primary"))

    ledger.transactions.manual = { type = "DIB_ADMIN_ADJUSTMENT" }
    dibs.Ledger.MarkTransactionsChanged("guild-primary")
    assert_true(dibs.Ledger.HasNonAllocationTransactions("guild-primary"))

    ledger.transactions.manual = nil
    dibs.Ledger.MarkTransactionsChanged("guild-primary")
    assert_false(dibs.Ledger.HasNonAllocationTransactions("guild-primary"))
  end)

  it("commits a valid local use with an immutable Name-Realm snapshot", function()
    local dibs = load()
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    local result = command(dibs, { transactionId = "use" })
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_equal("COMMITTED_LOCAL", result.reasonCode)
    assert_equal(before - 1, dibs.Ledger.GetBalance("Tester-Realm"))
    assert_equal("tester-realm", result.value.memberKey)
    assert_equal("Tester-Realm", result.value.identitySnapshot.displayName)
    assert_equal("LOCAL_CANONICAL", result.value.classification)
    assert_not_nil(result.value.canonicalContentHash)
  end)

  it("rejects an insufficient use atomically unless explicit local debt is enabled", function()
    local dibs = load()
    local beforeCount, beforeBalance = #dibs.Ledger.GetAllTransactions(), dibs.Ledger.GetBalance("Tester-Realm")
    local rejected = command(dibs, { transactionId = "no-debt", amount = -2 })
    assert_false(rejected.accepted); assert_equal("INSUFFICIENT_BALANCE", rejected.reasonCode)
    assert_equal(beforeCount, #dibs.Ledger.GetAllTransactions()); assert_equal(beforeBalance, dibs.Ledger.GetBalance("Tester-Realm"))
      local accepted = command(dibs, { transactionId = "debt", amount = -2 }, { action = "ledger.use", debtPolicy = { allowDebt = true, source = "B03_TEST" }, internal = true })
    assert_true(accepted.accepted); assert_true(accepted.value.debtPolicy.allowDebt)
  end)

  it("rejects zero, invalid signs, invalid actions, and unknown identities before mutation", function()
    local dibs = load(); local before = #dibs.Ledger.GetAllTransactions()
    assert_equal("INVALID_AMOUNT", command(dibs, { transactionId = "zero", amount = 0 }).reasonCode)
    assert_equal("INVALID_QUANTITY_SIGN", command(dibs, { transactionId = "sign", amount = 1 }).reasonCode)
    assert_equal("INVALID_ACTION_TYPE", command(dibs, { transactionId = "action", type = "NOT_AN_ACTION" }).reasonCode)
    assert_equal("UNKNOWN_ROSTER_MEMBER", command(dibs, { transactionId = "identity", playerName = "Unknown-Realm" }).reasonCode)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("stores a GUID only as witness metadata", function()
    local dibs = load()
    local result = command(dibs, { transactionId = "guid", playerGuid = "Player-1-WITNESS" })
    assert_true(result.accepted)
    assert_equal("tester-realm", result.value.memberKey)
    assert_equal("Player-1-WITNESS", result.value.guidWitness)
  end)

  it("handles same-ID replay and conflicts without changing durable state", function()
    local dibs = load()
    local first = command(dibs, { transactionId = "replay", awardRef = "award-b03" })
    local count, balance = #dibs.Ledger.GetAllTransactions(), dibs.Ledger.GetBalance("Tester-Realm")
    local replay = command(dibs, { transactionId = "replay", awardRef = "award-b03" })
    local conflict = command(dibs, { transactionId = "replay", awardRef = "different-award" })
    assert_true(first.accepted); assert_true(replay.accepted); assert_true(replay.idempotentReplay)
    assert_equal("IDEMPOTENT_REPLAY", replay.reasonCode); assert_false(conflict.accepted); assert_equal("TRANSACTION_CONFLICT", conflict.reasonCode)
    assert_equal(count, #dibs.Ledger.GetAllTransactions()); assert_equal(balance, dibs.Ledger.GetBalance("Tester-Realm"))
  end)

  it("keeps legacy IDs and records readable while compatibility mutators use the command", function()
    local legacy = {
      schemaVersion = 6,
      guilds = { ["realm:testguild"] = {
        version = 6, currentSeasonId = "season-legacy", seasons = { ["season-legacy"] = { id = "season-legacy", name = "Legacy", isArchived = false } }, rankRules = {},
        ledger = { transactions = { ["legacy-b03"] = { transactionId = "legacy-b03", playerName = "Legacy-Realm", amount = -1, seasonId = "season-legacy", type = "DIB_USED", createdAt = 1700000000 } }, playerStates = {}, awardTransactions = {}, evidenceTransactions = {} },
        permissions = { adminEvents = {}, activeStandaloneAdmins = {} }, preDibs = { requests = {}, modePolicies = {}, acquisitions = {} }, settings = {}, sync = { seenTransactions = {}, peerStates = {} },
      } }, persistenceRecovery = { version = 1, backups = {}, quarantine = {}, nextBackupId = 1 },
    }
    local dibs = load({ savedVariables = legacy, wow = { guildLeader = true } })
    assert_equal("legacy-b03", dibs.GetDB().ledger.transactions["legacy-b03"].transactionId)
    local readable = false
    for _, transaction in ipairs(dibs.Ledger.GetAllTransactions()) do
      if transaction.transactionId == "legacy-b03" and transaction.playerName == "Legacy-Realm" then readable = true end
    end
    assert_true(readable)
    local tx, reason = dibs.Ledger.Grant("Unknown-Realm", 1, "must validate", "test", dibs.GetCurrentSeasonId())
    assert_nil(tx); assert_equal("UNKNOWN_ROSTER_MEMBER", reason)
  end)

  it("migrates legacy db.ledger into db.ledgers['guild-primary'] and maintains active pointer", function()
    local legacy = {
      schemaVersion = 6,
      guilds = { ["realm:testguild"] = {
        version = 6, currentSeasonId = "season-migration", seasons = { ["season-migration"] = { id = "season-migration", name = "Migration", isArchived = false } }, rankRules = {},
        ledger = { transactions = { ["tx-migrated"] = { transactionId = "tx-migrated", playerName = "Tester-Realm", amount = 3, seasonId = "season-migration", type = "DIB_GRANTED", createdAt = 1700000001 } }, playerStates = {}, awardTransactions = {}, evidenceTransactions = {} },
        permissions = { adminEvents = {}, activeStandaloneAdmins = {} }, preDibs = { requests = {}, modePolicies = {}, acquisitions = {} }, settings = {}, sync = { seenTransactions = {}, peerStates = {} },
      } }, persistenceRecovery = { version = 1, backups = {}, quarantine = {}, nextBackupId = 1 },
    }
    local dibs = load({ savedVariables = legacy, wow = { guildLeader = true } })
    local db = dibs.GetDB()
    assert_not_nil(db.ledgers)
    assert_not_nil(db.ledgers["guild-primary"])
    assert_equal("guild-primary", dibs.Ledger.GetActiveLedgerId())
    assert_equal("tx-migrated", db.ledgers["guild-primary"].transactions["tx-migrated"].transactionId)
    -- db.ledger should be maintained as backward compatible reference
    assert_equal(db.ledgers["guild-primary"], db.ledger)
  end)

  it("isolates transactions between different ledger partitions", function()
    local dibs = load()
    dibs.SyncV2.BroadcastCatalogDigest = function() return true, "TEST_SENT" end
    local primaryBefore = dibs.Ledger.GetBalance("Tester-Realm", nil, "guild-primary")
    local proposal = dibs.MultiLedger.ProposeLedger("Tester-Realm", "Alt raid")
    assert_true(proposal.ok)
    assert_true(dibs.MultiLedger.ApproveLedger("Tester-Realm", proposal.ledgerId).ok)

    -- Commit transaction in secondary ledger partition
      local result = command(dibs, { transactionId = "alt-grant", type = "DIB_GRANTED", amount = 2 }, { action = "ledger.grant", ledgerId = proposal.ledgerId, internal = true })
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_equal("COMMITTED_LOCAL", result.reasonCode)

    -- Primary balance must be unchanged
    assert_equal(primaryBefore, dibs.Ledger.GetBalance("Tester-Realm", nil, "guild-primary"))
    -- Alt raid balance must reflect the grant
    assert_equal(2, dibs.Ledger.GetBalance("Tester-Realm", nil, proposal.ledgerId))
  end)

  it("returns copies from read APIs and leaves B02a identity/governance available", function()
    local dibs = load()
    local result = command(dibs, { transactionId = "copy" })
    local transaction = dibs.Ledger.GetTransactionForAward(nil) or result.value
    transaction.reason = "mutated read copy"
    local history = dibs.Ledger.GetHistory("Tester-Realm")
    assert_true(history[#history].reason ~= "mutated read copy")
    assert_equal("RESOLVED", dibs.Identity.ResolveRosterMember("Tester-Realm").status)
    assert_equal("POLICY_UNINITIALIZED", dibs.Governance.GetState().status)
  end)

  it("caches a bounded history index and invalidates it after a ledger commit", function()
    local dibs = load()
    local initial = dibs.Ledger.GetPlayerHistorySummary("Tester-Realm")

    assert_true(command(dibs, { transactionId = "history-page-grant", type = "DIB_GRANTED", amount = 5 },
      { action = "ledger.grant", internal = true }).accepted)
    assert_true(command(dibs, { transactionId = "history-page-use", type = "DIB_USED", amount = -3 }).accepted)
    assert_true(command(dibs, { transactionId = "history-page-refund", type = "DIB_REFUNDED", amount = 1 },
      { action = "ledger.refund", internal = true }).accepted)

    local summary = dibs.Ledger.GetPlayerHistorySummary("Tester-Realm")
    assert_equal(initial.count + 3, summary.count)
    assert_equal(initial.seasonUsed + 2, summary.seasonUsed)
    assert_equal(initial.balance + 3, summary.balance)
    local firstPage, total, page = dibs.Ledger.GetHistoryPage("Tester-Realm", nil, nil, 1, 2)
    assert_equal(2, #firstPage)
    assert_equal(summary.count, total)
    assert_equal(1, page)
    firstPage[1].reason = "mutated page copy"
    local storedReason
    for _, transaction in ipairs(dibs.Ledger.GetHistory("Tester-Realm")) do
      if transaction.transactionId == firstPage[1].transactionId then storedReason = transaction.reason end
    end
    assert_true(storedReason ~= "mutated page copy")

    assert_true(command(dibs, { transactionId = "history-page-late-grant", type = "DIB_GRANTED", amount = 2 },
      { action = "ledger.grant", internal = true }).accepted)
    local refreshed = dibs.Ledger.GetPlayerHistorySummary("Tester-Realm")
    assert_equal(summary.count + 1, refreshed.count)
    assert_equal(summary.balance + 2, refreshed.balance)
    assert_equal(summary.seasonUsed, refreshed.seasonUsed)
  end)

  it("returns lightweight recent-history choices with the total count", function()
    local dibs = load()
    local result = command(dibs, {
      transactionId = "history-choice-grant", type = "DIB_GRANTED", amount = 2,
      itemID = 12345, reason = "Test grant",
    }, { action = "ledger.grant", internal = true })
    assert_true(result.accepted)

    local choices, total = dibs.Ledger.GetRecentHistoryChoices("Tester-Realm", nil, nil, 50)
    assert_true(total >= 1)
    assert_equal(total, #choices)
    local grant
    for _, choice in ipairs(choices) do
      if choice.transactionId == "b03-history-choice-grant" then grant = choice end
      assert_nil(choice.context, "dropdown choice should not copy full transaction context")
      assert_nil(choice.actorSnapshot, "dropdown choice should not copy actor snapshots")
    end
    assert_not_nil(grant)
    assert_equal("DIB_GRANTED", grant.type)
    assert_equal("Test grant", grant.reason)
  end)

  it("reuses bounded recent-history choices until ledger revisions change", function()
    local dibs = load()
    assert_true(command(dibs, {
      transactionId = "history-choice-cache-first", type = "DIB_GRANTED", amount = 2,
      reason = "Cached grant",
    }, { action = "ledger.grant", internal = true }).accepted)

    local previousProfiler = _G.debugprofilestop
    local profilerTick = 0
    _G.debugprofilestop = function()
      profilerTick = profilerTick + 1
      return profilerTick
    end
    dibs.UIRenderStats.Reset()
    dibs.UIRenderStats.SetEnabled(true)
    local first, firstTotal = dibs.Ledger.GetRecentHistoryChoices("Tester-Realm", nil, nil, 50)
    first[1].reason = "caller mutation"
    local cached = dibs.Ledger.GetRecentHistoryChoices("Tester-Realm", nil, nil, 50)
    assert_true(cached[1].reason ~= "caller mutation", "cached projection must not be exposed to callers")
    assert_true(command(dibs, {
      transactionId = "history-choice-cache-second", type = "DIB_GRANTED", amount = 1,
      reason = "New grant",
    }, { action = "ledger.grant", internal = true }).accepted)
    local refreshed, total = dibs.Ledger.GetRecentHistoryChoices("Tester-Realm", nil, nil, 50)
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = previousProfiler

    assert_equal(firstTotal + 1, total)
    assert_equal(total, #refreshed)
    local hits, misses, dbReads, ledgerIds, ledgerNormalizations
    for _, row in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if row.kind == "Ledger data" and row.page == "recent-history-choices-cache-hit" then hits = row.count end
      if row.kind == "Ledger data" and row.page == "recent-history-choices-cache-miss" then misses = row.count end
      if row.kind == "Ledger data" and row.page == "recent-history-choices-db-read" then dbReads = row.count end
      if row.kind == "Ledger data" and row.page == "recent-history-choices-ledger-id" then ledgerIds = row.count end
      if row.kind == "Ledger data" and row.page == "recent-history-choices-ledger-normalize" then ledgerNormalizations = row.count end
    end
    assert_equal(1, hits)
    assert_equal(2, misses, "a new ledger revision must invalidate the cached choices")
    assert_equal(3, dbReads)
    assert_equal(3, ledgerIds)
    assert_equal(3, ledgerNormalizations)
  end)

  it("selects only the newest history choices without sorting all history IDs", function()
    local dibs = load()
    local seasonId = dibs.GetCurrentSeasonId()
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local state = { allocation = 0, transactions = {} }
    ledger.transactions = {}
    ledger.playerStates[seasonId] = { ["tester-realm"] = state }
    for index = 1, 80 do
      local id = "choice-" .. tostring(index)
      ledger.transactions[id] = {
        transactionId = id, type = "DIB_USED", amount = -1,
        playerName = "Tester-Realm", playerKey = "tester-realm",
        seasonId = seasonId, createdAt = index,
      }
      state.transactions[index] = id
    end
    dibs.Ledger.MarkTransactionsChanged("guild-primary")

    local choices, total = dibs.Ledger.GetRecentHistoryChoices("Tester-Realm", seasonId, "guild-primary", 50)
    assert_equal(80, total)
    assert_equal(50, #choices)
    assert_equal("choice-31", choices[1].transactionId)
    assert_equal("choice-80", choices[#choices].transactionId)
  end)

  it("aggregates season activity without returning transaction records", function()
    local dibs = load()
    local seasonId = dibs.GetCurrentSeasonId()
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    ledger.transactions = {
      use1 = { seasonId = seasonId, playerName = "Member-Realm", type = "DIB_USED", amount = -2, createdAt = 10 },
      use2 = { seasonId = seasonId, playerName = "Member-Realm", type = "DIB_USED", amount = -1, createdAt = 20 },
      grant = { seasonId = seasonId, playerName = "Member-Realm", type = "DIB_GRANTED", amount = 4, createdAt = 15 },
      correction = { seasonId = seasonId, playerName = "Member-Realm", type = "DIB_REFUNDED", amount = 1, createdAt = 30 },
      outsider = { seasonId = seasonId, playerName = "Former-Realm", type = "DIB_USED", amount = -9 },
      otherSeason = { seasonId = "old-season", playerName = "Member-Realm", type = "DIB_USED", amount = -9 },
    }
    dibs.Ledger.MarkTransactionsChanged("guild-primary")

    local summary = dibs.Ledger.GetSeasonActivitySummary(seasonId, "guild-primary", function(name)
      return name == "Member-Realm" and name or nil
    end, 2)
    assert_equal(5, summary.transactions)
    assert_equal(1, summary.players)
    assert_equal(4, summary.granted)
    assert_equal(3, summary.used)
    assert_equal(2, summary.awards)
    assert_equal(1, summary.corrections)
    assert_equal(2, summary.awardCount["member-realm"])
    assert_equal(2, #summary.recentTransactions)
    assert_equal("Member-Realm", summary.recentTransactions[1].playerName)
    assert_equal("DIB_REFUNDED", summary.recentTransactions[1].type)
    assert_equal("DIB_USED", summary.recentTransactions[2].type)
    assert_nil(summary[1], "aggregate should not expose a transaction array")
  end)

  it("computes a player summary without sorting the full history", function()
    local dibs = load()
    local originalSort = table.sort
    table.sort = function() error("summary query must not sort history rows") end
    local ok, summary = pcall(dibs.Ledger.GetPlayerHistorySummary, "Tester-Realm")
    table.sort = originalSort

    assert_true(ok, tostring(summary))
    assert_true(summary.count > 0)
  end)
end)
