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
  return dibs.Ledger.CommitLocalTransaction(context or { action = "ledger.use" }, value, context and context.ledgerId)
end

describe("B03 local canonical ledger", function()
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
    local accepted = command(dibs, { transactionId = "debt", amount = -2 }, { action = "ledger.use", debtPolicy = { allowDebt = true, source = "B03_TEST" } })
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
    local result = command(dibs, { transactionId = "alt-grant", type = "DIB_GRANTED", amount = 2 }, { action = "ledger.grant", ledgerId = proposal.ledgerId })
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
end)
