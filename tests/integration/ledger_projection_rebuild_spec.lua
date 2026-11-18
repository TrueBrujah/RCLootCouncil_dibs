local loader = require("helpers.load_addon")

local roster = { "Coordinator-Realm", "Officer-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function activateV2()
  local _, dibs = loader.load({ withAce3 = true, wow = {
    playerName = "Coordinator-Realm", guildLeader = true,
    guildMembers = roster, guildRankIndices = ranks,
  } })
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "projection rebuild test" }))
  local baseline = assert(dibs.HistoricalBaseline.FinalizeBaseline(nil))
  local coordinator = assert(dibs.Identity.CreateSnapshot("Coordinator-Realm"))
  assert_true(dibs.Governance.Change(nil, { future = { authority = {
    schema = 1, state = "ACTIVE", coordinator = coordinator, ledgerEpoch = 7,
    transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
  } } }))
  assert_true(dibs.Governance.EnableV2(nil, { "Coordinator-Realm" }))
  return dibs
end

describe("Ledger projection rebuild", function()
  it("rebuilds missing award rows from the verified journal without changing commits", function()
    local dibs = activateV2()
    local seasonId = dibs.GetCurrentSeasonId()
    local committed = dibs.Ledger.CommitSeasonAllocation({ actor = "Coordinator-Realm" }, {
      playerName = "Player-Realm", amount = 5, reason = "projection rebuild allocation",
      source = "projection-rebuild-test", seasonId = seasonId,
    })
    assert_true(committed.accepted, tostring(committed.reasonCode))
    local transactionId = committed.value.canonicalTransactionId

    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local commits = dibs.DeepCopy(ledger.canonical.commits)
    local nextSeq, rootHash = ledger.canonical.nextSeq, ledger.canonical.rootHash
    local balance = dibs.Ledger.GetBalance("Player-Realm", seasonId, "guild-primary")
    local state = dibs.Ledger.GetPlayerState("Player-Realm", seasonId, "guild-primary")
    ledger.transactions[transactionId] = nil
    ledger.playerStates[seasonId] = nil

    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_true(rebuilt.rebuilt, tostring(rebuilt.reasonCode))
    assert_not_nil(ledger.transactions[transactionId])
    assert_equal(balance, dibs.Ledger.GetBalance("Player-Realm", seasonId, "guild-primary"))
    local rebuiltState = dibs.Ledger.GetPlayerState("Player-Realm", seasonId, "guild-primary")
    assert_equal(state.allocation, rebuiltState.allocation)
    assert_equal(state.balance, rebuiltState.balance)
    assert_equal(nextSeq, ledger.canonical.nextSeq)
    assert_equal(rootHash, ledger.canonical.rootHash)
    for position, commit in pairs(commits) do
      assert_equal(commit.commitHash, ledger.canonical.commits[position].commitHash,
        "rebuild changed canonical history")
    end
  end)

  it("refuses an unsupported canonical record without touching any projection", function()
    local dibs = activateV2()
    local committed = dibs.Ledger.CommitSeasonAllocation({ actor = "Coordinator-Realm" }, {
      playerName = "Player-Realm", amount = 2, reason = "unsupported record guard",
      source = "projection-rebuild-test", seasonId = dibs.GetCurrentSeasonId(),
    })
    assert_true(committed.accepted, tostring(committed.reasonCode))
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local position = tostring(committed.value.ledgerEpoch) .. ":" .. tostring(committed.value.sequence)
    local transactionTable, stateTable = ledger.transactions, ledger.playerStates
    local nextSeq, rootHash = ledger.canonical.nextSeq, ledger.canonical.rootHash
    ledger.canonical.commits[position].recordClass = "FUTURE_TEST_RECORD"

    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_false(rebuilt.rebuilt)
    assert_equal("UNSUPPORTED_CANONICAL_RECORD", rebuilt.reasonCode)
    assert_true(transactionTable == ledger.transactions, "refusal replaced transaction projections")
    assert_true(stateTable == ledger.playerStates, "refusal replaced balance projections")
    assert_equal(nextSeq, ledger.canonical.nextSeq)
    assert_equal(rootHash, ledger.canonical.rootHash)
  end)
end)
