local loader = require("helpers.load_addon")

local function setup()
  local _, dibs = loader.load({ withAce3 = true, wow = { playerName = "Tester-Realm", guildLeader = true } })
  return dibs
end

local function repack(dibs, package, mutate)
  mutate(package)
  package.checksum = nil
  local unsigned = assert(dibs.ImportExport.Encode(package))
  package.checksum = dibs.ImportExport.Checksum(unsigned:sub(#dibs.ImportExport.PACKAGE_PREFIX + 1))
  return assert(dibs.ImportExport.Encode(package))
end

describe("ImportExport Apply atomicity", function()
  it("does not clear local settings when a malformed replacement is applied", function()
    local dibs = setup()
    local db = dibs.GetDB()
    db.settings.theme = "keep-local-theme"
    local _, package = dibs.ImportExport.Export("local")
    local encoded = repack(dibs, package, function(value)
      value.payload.presentation = 7
    end)
    local preview = assert(dibs.ImportExport.Preview(encoded, "local", "replace"))

    local ok, result, reason = pcall(dibs.ImportExport.Apply, preview.previewId, true, "malformed local", "Tester-Realm")

    print("AUDIT local-import theme=" .. tostring(db.settings.theme) .. " raised=" .. tostring(not ok))
    assert_equal("keep-local-theme", db.settings.theme, "replace cleared settings before validating the payload")
    assert_true(ok, "Apply raised instead of rejecting malformed presentation data: " .. tostring(result))
    assert_nil(result, "malformed local presentation data was applied")
  end)

  it("does not clear guild settings when a malformed replacement is applied", function()
    local dibs = setup()
    local db = dibs.GetDB()
    db.settings.defaultAllocation = 12
    local _, package = dibs.ImportExport.Export("guild", { actor = "Tester-Realm" })
    local encoded = repack(dibs, package, function(value)
      value.payload.settings = 7
    end)
    local preview = assert(dibs.ImportExport.Preview(encoded, "guild", "replace", "Tester-Realm"))

    local ok, result, reason = pcall(dibs.ImportExport.Apply, preview.previewId, true, "malformed guild", "Tester-Realm")

    print("AUDIT guild-import allocation=" .. tostring(db.settings.defaultAllocation) .. " raised=" .. tostring(not ok))
    assert_equal(12, db.settings.defaultAllocation, "replace cleared guild settings before validating the payload")
    assert_true(ok, "Apply raised instead of rejecting malformed settings: " .. tostring(result))
    assert_nil(result, "malformed guild settings were applied")
  end)

  it("invalidates cached Officer transaction summaries after importing ledger rows", function()
    local dibs = setup()
    local db = dibs.GetDB()
    local ledger = db.ledgers[db.activeLedgerId]
    local seasonId = dibs.GetCurrentSeasonId()
    local transactionId = "officer-diagnostics-import-cache"
    local state = ledger.playerStates[seasonId].tester
    local transaction = {
      transactionId = transactionId, type = "DIB_GRANTED", actionType = "DIB_GRANTED",
      playerName = "Tester-Realm", memberKey = "tester-realm", amount = 3,
      seasonId = seasonId, reason = "cache invalidation fixture", source = "test", createdAt = 1700000000,
    }
    ledger.transactions[transactionId] = transaction
    if state then state.transactions[#state.transactions + 1] = transactionId end
    local _, package = dibs.ImportExport.Export("full", { actor = "Tester-Realm" })
    local expectedCount = dibs.Ledger.GetTransactionDiagnostics().transactionCount

    ledger.transactions[transactionId] = nil
    if state then
      for index = #state.transactions, 1, -1 do
        if state.transactions[index] == transactionId then table.remove(state.transactions, index) end
      end
    end
    local encoded = assert(dibs.ImportExport.Encode(package))
    local preview = assert(dibs.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm"))
    local applied, reason = dibs.ImportExport.Apply(preview.previewId, true, "Officer cache test", "Tester-Realm")

    assert_not_nil(applied, tostring(reason))
    assert_equal(expectedCount, dibs.Ledger.GetTransactionDiagnostics().transactionCount)
  end)
end)
