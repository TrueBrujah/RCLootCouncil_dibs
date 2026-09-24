local loader = require("helpers.load_addon")

describe("Sync addon message trace", function()
  it("does not record any trace entries when Developer Mode is disabled", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.Sync.Send({ type = "HELLO" }, "GUILD")
    local sent = dibs.Ace3.libs.comm.sent[1]
    dibs.Sync.OnAddonMessage(sent.prefix, sent.payload, sent.channel, "Tester-Realm")
    local syncEntries = 0
    for _, entry in ipairs(dibs.DebugLogs.entries) do if entry.module == "Sync" then syncEntries = syncEntries + 1 end end
    assert_equal(0, syncEntries)
  end)

  it("records incoming and outgoing Sync messages only while Developer Mode is enabled", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true, savedVariables = {} })
    dibs.DeveloperMode.SetEnabled(true)
    dibs.Sync.Send({ type = "HELLO" }, "GUILD")
    local sent = dibs.Ace3.libs.comm.sent[1]
    local result = dibs.Sync.OnAddonMessage(sent.prefix, sent.payload, sent.channel, "Tester-Realm")

    assert_true(result)
    local modules = {}
    for _, entry in ipairs(dibs.DebugLogs.entries) do modules[entry.module] = (modules[entry.module] or 0) + 1 end
    assert_true((modules["Sync"] or 0) >= 2)

    local sawSend, sawRecv = false, false
    for _, entry in ipairs(dibs.DebugLogs.entries) do
      if entry.module == "Sync" and entry.message:find("SEND", 1, true) then sawSend = true end
      if entry.module == "Sync" and entry.message:find("RECV", 1, true) then sawRecv = true end
    end
    assert_true(sawSend)
    assert_true(sawRecv)
  end)
end)
