local loader = require("helpers.load_addon")

local function countEntries(map)
  local count = 0
  for _ in pairs(map or {}) do count = count + 1 end
  return count
end

describe("Guild data isolation", function()
  it("keeps settings and seasons isolated per guild within the same account SavedVariables", function()
    local _, dibsA = loader.load({ wow = { guildName = "Alpha Raiders" } })
    local dbA = dibsA.GetDB()
    dbA.settings.allowPublicPreDibs = false
    dibsA.Seasons.Create("Alpha Season")
    local seasonCountA = countEntries(dbA.seasons)
    local guildKeyA = dibsA.currentGuildKey
    local savedRoot = _G.RCLootCouncil_dibsDB

    local _, dibsB = loader.load({ wow = { guildName = "Beta Legion" } })
    _G.RCLootCouncil_dibsDB = savedRoot
    local dbB = dibsB.GetDB()
    local guildKeyB = dibsB.currentGuildKey

    assert_true(guildKeyA ~= guildKeyB, "expected distinct guild keys")
    assert_equal(true, dbB.settings.allowPublicPreDibs)
    assert_equal(0, countEntries(dbB.seasons))
    assert_equal(seasonCountA, countEntries(savedRoot.guilds[guildKeyA].seasons))
    assert_equal(false, savedRoot.guilds[guildKeyA].settings.allowPublicPreDibs)
  end)

  it("isolates alt characters without a guild from each other", function()
    local _, dibsA = loader.load({ wow = { inGuild = false, playerName = "AltOne-Realm" } })
    dibsA.GetDB().settings.allowPublicPreDibs = false
    local savedRoot = _G.RCLootCouncil_dibsDB

    local _, dibsB = loader.load({ wow = { inGuild = false, playerName = "AltTwo-Realm" } })
    _G.RCLootCouncil_dibsDB = savedRoot
    local dbB = dibsB.GetDB()

    assert_equal(true, dbB.settings.allowPublicPreDibs)
  end)

  it("migrates a legacy flat SavedVariables root into the current guild bucket", function()
    local _, dibs = loader.load({ wow = { guildName = "Legacy Guild" } })
    dibs.GetDB().settings.allowPublicPreDibs = false
    local guildKey = dibs.currentGuildKey
    -- Simulate a pre-guild-scoping save captured before this migration existed.
    _G.RCLootCouncil_dibsDB = _G.RCLootCouncil_dibsDB.guilds[guildKey]

    local db = dibs.GetDB()
    assert_equal(false, db.settings.allowPublicPreDibs)
    assert_not_nil(_G.RCLootCouncil_dibsDB.guilds)
    assert_not_nil(_G.RCLootCouncil_dibsDB.guilds[guildKey])
  end)
end)
