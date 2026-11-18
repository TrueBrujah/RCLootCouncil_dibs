local loader = require("helpers.load_addon")

local function setupMember()
  local _, dibs = loader.load({ withAce3 = true, wow = {
    playerName = "Tester-Realm",
    guildLeader = false,
    guildMembers = { "Tester-Realm" },
    guildRankIndices = { [1] = 3 },
  } })
  return dibs
end

local function repack(dibs, package)
  package.checksum = nil
  local unsigned = assert(dibs.ImportExport.Encode(package))
  package.checksum = dibs.ImportExport.Checksum(unsigned:sub(#dibs.ImportExport.PACKAGE_PREFIX + 1))
  return assert(dibs.ImportExport.Encode(package))
end

local function assertDeepEqual(expected, actual, path)
  path = path or "value"
  assert_equal(type(expected), type(actual), path .. " type changed")
  if type(expected) ~= "table" then
    assert_equal(expected, actual, path .. " changed")
    return
  end
  for key, value in pairs(expected) do
    assertDeepEqual(value, actual[key], path .. "." .. tostring(key))
  end
  for key in pairs(actual) do
    assert_not_nil(expected[key], path .. " gained " .. tostring(key))
  end
end

describe("Local import scope regression", function()
  it("ignores injected guild policy during a member's local merge", function()
    local dibs = setupMember()
    local db = dibs.GetDB()
    db.settings.officerRankIndices = { [1] = true }
    db.settings.officerMaxRankIndex = 1
    db.settings.defaultAllocation = 12
    local ledgerBefore = dibs.DeepCopy(db.ledger)
    local governanceBefore = dibs.DeepCopy(db.governance)
    local _, package = dibs.ImportExport.Export("local")
    package.payload.presentation.theme = "imported-local-theme"
    package.payload.presentation.officerRankIndices = { [3] = true }
    package.payload.presentation.officerMaxRankIndex = 3
    package.payload.presentation.defaultAllocation = 99
    local preview = assert(dibs.ImportExport.Preview(repack(dibs, package), "local", "merge"))
    local applied, reason = dibs.ImportExport.Apply(preview.previewId, true, "local merge regression", "Tester-Realm")

    assert_not_nil(applied, tostring(reason))
    assert_equal("imported-local-theme", db.settings.theme)
    assert_true(db.settings.officerRankIndices[1])
    assert_nil(db.settings.officerRankIndices[3])
    assert_equal(1, db.settings.officerMaxRankIndex)
    assert_equal(12, db.settings.defaultAllocation)
    assert_false(dibs.Permissions.IsOfficer())
    assert_false(dibs.Permissions.Can("settings.modify"))
    assertDeepEqual(ledgerBefore, db.ledger, "ledger")
    assertDeepEqual(governanceBefore, db.governance, "governance")
  end)

  it("preserves all out-of-scope settings during legitimate local replace", function()
    local dibs = setupMember()
    local db = dibs.GetDB()
    db.settings.defaultAllocation = 12
    db.settings.officerRankIndices = { [1] = true }
    db.settings.officerMaxRankIndex = 1
    db.settings.raidReminderMessage = "guild policy stays"
    db.settings.theme = "old-theme"
    db.settings.pageSize = 17
    local ledgerBefore = dibs.DeepCopy(db.ledger)
    local governanceBefore = dibs.DeepCopy(db.governance)

    local _, package = dibs.ImportExport.Export("local")
    package.payload.presentation = { theme = "new-theme" }
    local preview = assert(dibs.ImportExport.Preview(repack(dibs, package), "local", "replace"))
    local applied, reason = dibs.ImportExport.Apply(preview.previewId, true, "local replace regression", "Tester-Realm")

    assert_not_nil(applied, tostring(reason))
    assert_equal("new-theme", db.settings.theme)
    assert_nil(db.settings.pageSize)
    assert_equal(12, db.settings.defaultAllocation)
    assert_true(db.settings.officerRankIndices[1])
    assert_equal(1, db.settings.officerMaxRankIndex)
    assert_equal("guild policy stays", db.settings.raidReminderMessage)
    assertDeepEqual(ledgerBefore, db.ledger, "ledger")
    assertDeepEqual(governanceBefore, db.governance, "governance")
  end)
end)
