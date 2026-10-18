local wow = require("helpers.wow_api")

describe("Hidden factory reset", function()
  local reloads, now, inCombat, previousTime, previousReload, previousCombat

  before_each(function()
    wow.install({ guildLeader = true })
    dofile("src/Core.lua")
    dofile("src/locales/enUS.lua")
    reloads, now, inCombat = 0, 1000, false
    previousTime, previousReload, previousCombat = _G.time, _G.ReloadUI, _G.InCombatLockdown
    _G.time = function() return now end
    _G.ReloadUI = function() reloads = reloads + 1 end
    _G.InCombatLockdown = function() return inCombat end
    _G.RCLootCouncil_dibsDB = { guilds = { g = { ledgers = { x = {} } } } }
    _G.RCLootCouncil_dibsSandboxDB = { guilds = {} }
    _G.RCLootCouncil_dibsLocalDB = { settings = { a = 1 } }
    _G.DibsDB = { legacy = true }
  end)

  after_each(function()
    _G.time, _G.ReloadUI, _G.InCombatLockdown = previousTime, previousReload, previousCombat
  end)

  local function assertDataKept()
    assert_not_nil(_G.RCLootCouncil_dibsDB)
    assert_not_nil(_G.RCLootCouncil_dibsSandboxDB)
    assert_not_nil(_G.RCLootCouncil_dibsLocalDB)
    assert_equal(0, reloads)
  end

  it("stays out of the public help", function()
    local messages = {}
    Dibs.Message = function(text) messages[#messages + 1] = tostring(text) end
    Dibs.HandleSlashCommand("help")
    for _, text in ipairs(messages) do
      assert_nil(text:lower():find("factoryreset", 1, true))
    end
  end)

  it("requires arming before confirmation and wipes every Dibs SavedVariable", function()
    local chat = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) chat[#chat + 1] = tostring(text) end }
    Dibs.HandleSlashCommand("factoryreset CONFIRM")
    assertDataKept()
    Dibs.HandleSlashCommand("factoryreset")
    assertDataKept()
    local shown = table.concat(chat, "\n")
    assert_not_nil(shown:find("WARNING", 1, true), "Warning must be visible in chat")
    assert_not_nil(shown:find("/dibs factoryreset CONFIRM within 60 seconds", 1, true), "Confirmation hint must be visible in chat")
    now = now + 10
    Dibs.HandleSlashCommand("FactoryReset confirm")
    assert_nil(_G.RCLootCouncil_dibsDB)
    assert_nil(_G.RCLootCouncil_dibsSandboxDB)
    assert_nil(_G.RCLootCouncil_dibsLocalDB)
    assert_nil(_G.DibsDB)
    assert_equal(1, reloads)
  end)

  it("keeps only Officer backups, in a fresh root, when any exist", function()
    _G.RCLootCouncil_dibsDB = { schemaVersion = 1, guilds = {
      g = { ledgers = { x = {} }, backups = { { snapshotId = "snap-1", createdAt = 5 } }, backupRetention = 7 },
      h = { ledgers = { y = {} }, backups = {} },
    } }
    Dibs.HandleSlashCommand("factoryreset")
    Dibs.HandleSlashCommand("factoryreset CONFIRM")
    local root = _G.RCLootCouncil_dibsDB
    assert_not_nil(root)
    assert_nil(next(root.guilds), "No guild data may survive")
    assert_equal("snap-1", root.preservedBackups.g.backups[1].snapshotId)
    assert_equal(7, root.preservedBackups.g.backupRetention)
    assert_nil(root.preservedBackups.h)
    assert_nil(_G.RCLootCouncil_dibsSandboxDB)
    assert_nil(_G.RCLootCouncil_dibsLocalDB)
    assert_equal(1, reloads)
  end)

  it("expires the confirmation window and refuses in combat", function()
    Dibs.HandleSlashCommand("factoryreset")
    now = now + 61
    Dibs.HandleSlashCommand("factoryreset CONFIRM")
    assertDataKept()

    Dibs.HandleSlashCommand("factoryreset")
    inCombat = true
    Dibs.HandleSlashCommand("factoryreset CONFIRM")
    assertDataKept()
    inCombat = false
    Dibs.HandleSlashCommand("factoryreset CONFIRM")
    assertDataKept()
  end)
end)
