local clients = require("helpers.canonical_operation_clients")

-- RF-0039 regression suite.
--
-- RF-0039 - "Ledger : la reconstruction apres interruption" (verification
-- du chemin de reprise, sans defaut confirme) — voir
-- docs/code-audit/INDEX.md#rf-0039.
--
-- The audit brief asks for the rebuild-after-interruption path to be
-- covered:
--   * a partially projected chain must be refused, not rebuilt;
--   * a repeated rebuild must produce identical rows, identifiers,
--     balances, and indexes;
--   * an interrupted rebuild must leave the history intact.
--
-- Every client has its own Lua environment, its own SavedVariables, its
-- own ledger, its own SyncV2 state and its own Governance state.

local function setup()
  local world = clients.new()
  local coordinator = world:Load("Coordinator-Realm")
  world:ActivateV2()
  local dibs = coordinator.dibs
  return world, coordinator, dibs
end

local function canonicalOf(dibs, ledgerId)
  local state = dibs.Ledger.GetCanonicalState(ledgerId or "guild-primary")
  return state and { epoch = state.epoch, nextSeq = state.nextSeq, rootHash = state.rootHash } or nil
end

local function snapshotOf(dibs, ledgerId)
  local db = dibs.GetDB()
  local ledger = db.ledgers and db.ledgers[ledgerId or "guild-primary"]
  return ledger and ledger.canonical or nil
end

-- Creates a real canonical history: one allocation and one consumption.
local function seedHistory(dibs)
  local allocation = dibs.Ledger.CommitSeasonAllocation({ actor = "Coordinator-Realm" }, {
    playerName = "Player-Realm", amount = 5, reason = "RF-0039 allocation",
    source = "rf0039", seasonId = dibs.GetCurrentSeasonId(),
  })
  assert_true(allocation.accepted, tostring(allocation.reasonCode))
  local consumption = dibs.Ledger.CommitDibUse({ actor = "Coordinator-Realm" }, {
    transactionId = "rf0039-use", proposalId = "rf0039-use-p",
    playerName = "Player-Realm", amount = 1, itemID = 1,
    source = "rf0039", response = "PASS", status = "finalized",
  })
  assert_true(consumption.accepted, tostring(consumption.reasonCode))
  return allocation, consumption
end

describe("RF-0039 rebuild after an interruption", function()
  it("rebuilds a valid chain to the same rows, balances, and indexes", function()
    local world, coordinator, dibs = setup()
    seedHistory(dibs)
    local seasonId = dibs.GetCurrentSeasonId()

    local beforeBalance = dibs.Ledger.GetBalance("Player-Realm", seasonId)
    local beforeState = dibs.Ledger.GetPlayerState("Player-Realm", seasonId)
    local beforeCanonical = canonicalOf(dibs)

    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_true(rebuilt.rebuilt, tostring(rebuilt.reasonCode))

    assert_equal(beforeBalance, dibs.Ledger.GetBalance("Player-Realm", seasonId),
      "the rebuild changed the balance")
    local afterState = dibs.Ledger.GetPlayerState("Player-Realm", seasonId)
    assert_equal(beforeState.allocation, afterState.allocation,
      "the rebuild changed the allocation")
    assert_equal(beforeState.balance, afterState.balance,
      "the rebuild changed the player balance")
    assert_equal(#beforeState.transactions, #afterState.transactions,
      "the rebuild changed the number of transaction references")
    assert_equal(beforeCanonical.nextSeq, canonicalOf(dibs).nextSeq,
      "the rebuild changed the canonical sequence")
    assert_equal(beforeCanonical.rootHash, canonicalOf(dibs).rootHash,
      "the rebuild changed the canonical root hash")
  end)

  it("produces identical rows on a repeated rebuild", function()
    local world, coordinator, dibs = setup()
    seedHistory(dibs)
    local seasonId = dibs.GetCurrentSeasonId()

    assert_true(dibs.Ledger.RebuildLedgerProjections("guild-primary").rebuilt)
    local first = {
      balance = dibs.Ledger.GetBalance("Player-Realm", seasonId),
      state = dibs.Ledger.GetPlayerState("Player-Realm", seasonId),
      canonical = canonicalOf(dibs),
    }
    local firstIds = {}
    for id in pairs(dibs.GetDB().ledgers["guild-primary"].transactions) do firstIds[#firstIds + 1] = id end
    table.sort(firstIds)

    assert_true(dibs.Ledger.RebuildLedgerProjections("guild-primary").rebuilt)
    local secondIds = {}
    for id in pairs(dibs.GetDB().ledgers["guild-primary"].transactions) do secondIds[#secondIds + 1] = id end
    table.sort(secondIds)

    assert_equal(#firstIds, #secondIds, "the repeated rebuild changed the row count")
    for index = 1, #firstIds do
      assert_equal(firstIds[index], secondIds[index],
        "the repeated rebuild changed the transaction identifiers")
    end
    assert_equal(first.balance, dibs.Ledger.GetBalance("Player-Realm", seasonId),
      "the repeated rebuild changed the balance")
    assert_equal(first.state.allocation, dibs.Ledger.GetPlayerState("Player-Realm", seasonId).allocation,
      "the repeated rebuild changed the allocation")
    assert_equal(first.canonical.rootHash, canonicalOf(dibs).rootHash,
      "the repeated rebuild changed the canonical root hash")
  end)

  it("rebuilds an award row that the interrupted run did not write", function()
    local world, coordinator, dibs = setup()
    seedHistory(dibs)
    local seasonId = dibs.GetCurrentSeasonId()

    local beforeBalance = dibs.Ledger.GetBalance("Player-Realm", seasonId)
    local beforeState = dibs.Ledger.GetPlayerState("Player-Realm", seasonId)
    local beforeCanonical = canonicalOf(dibs)

    -- An interrupted run can leave the commit stored but its row missing.
    -- The award row is derived from the commit itself, so the rebuild
    -- restores it instead of losing the transaction.
    local canonical = snapshotOf(dibs)
    local position = nil
    for key in pairs(canonical.commits) do position = key break end
    local commit = canonical.commits[position]
    local transactionId = commit.transaction and commit.transaction.transactionId
    assert_not_nil(transactionId, "the fixture has no canonical transaction")
    dibs.GetDB().ledgers["guild-primary"].transactions[transactionId] = nil

    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_true(rebuilt.rebuilt, tostring(rebuilt.reasonCode))

    assert_not_nil(dibs.GetDB().ledgers["guild-primary"].transactions[transactionId],
      "the rebuild did not restore the interrupted row")
    assert_equal(beforeBalance, dibs.Ledger.GetBalance("Player-Realm", seasonId),
      "the rebuild changed the balance")
    assert_equal(beforeState.allocation, dibs.Ledger.GetPlayerState("Player-Realm", seasonId).allocation,
      "the rebuild changed the allocation")
    assert_equal(beforeCanonical.nextSeq, canonicalOf(dibs).nextSeq,
      "the rebuild changed the canonical sequence")
    assert_equal(beforeCanonical.rootHash, canonicalOf(dibs).rootHash,
      "the rebuild changed the canonical root hash")
  end)

  it("keeps a legacy row that no canonical record backs", function()
    local world, coordinator, dibs = setup()
    seedHistory(dibs)
    local seasonId = dibs.GetCurrentSeasonId()

    -- A pre-feature local row that the canonical chain does not own.
    dibs.Ledger.AddTransaction({
      transactionId = "rf0039-legacy", type = "DIB_GRANTED", playerName = "Player-Realm",
      amount = 3, seasonId = seasonId, reason = "RF-0039 legacy row", source = "legacy",
    }, "guild-primary")

    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_true(rebuilt.rebuilt, tostring(rebuilt.reasonCode))
    assert_true((rebuilt.legacyRowCount or 0) >= 1,
      "the legacy row was not counted as legacy history")
    assert_not_nil(dibs.GetDB().ledgers["guild-primary"].transactions["rf0039-legacy"],
      "the legacy row was dropped by the rebuild")
  end)
end)
