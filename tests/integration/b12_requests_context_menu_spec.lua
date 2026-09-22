local loader = require("helpers.load_addon")
local mocks = require("helpers.b11_ui_mocks")

local function findMenuEntry(entries, text)
  for _, entry in ipairs(entries or {}) do
    if entry.text == text then return entry end
  end
  return nil
end

describe("B12 request context menus", function()
  after_each(function() mocks.clear() end)

  it("offers object-aware safe actions and keeps advanced mutations out of the row menu", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Player-1" } },
      withAce3 = true,
    })
    local capturedOptions
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      if options and options.contextMenu then capturedOptions = options end
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    local shownPlayer
    local messages = {}
    local originalShow = dibs.PlayerUI.Show
    local originalMessage = dibs.Message
    dibs.Disputes.ListForOfficer = function()
      return {
        {
          requestId = "b12-context-1",
          status = "Open",
          categoryLabel = "Missing Dibs",
          player = { name = "Player-1" },
          evidence = { { item = "Midnight Blade", itemID = 21016, source = "Dibs ledger" } },
        },
      }
    end

    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("disputes")
    frame:Refresh()
    dibs.PlayerUI.Show = function(playerName) shownPlayer = playerName end
    dibs.Message = function(message) messages[#messages + 1] = tostring(message) end
    local request = dibs.Disputes.ListForOfficer(nil)[1]
    local menu = capturedOptions.contextMenu({ request = request })
    local open = findMenuEntry(menu, "Open request")
    local viewDibs = findMenuEntry(menu, "View player Dibs")
    local history = findMenuEntry(menu, "View player history")
    local copyName = findMenuEntry(menu, "Copy Name-Realm")
    local copyItem = findMenuEntry(menu, "Copy item link")
    assert_not_nil(open)
    assert_not_nil(viewDibs)
    assert_not_nil(history)
    assert_not_nil(copyName)
    assert_not_nil(copyItem)
    assert_nil(findMenuEntry(menu, "Correct balance"))
    assert_nil(findMenuEntry(menu, "Refund Dib"))

    viewDibs.callback()
    history.callback()
    copyName.callback()
    copyItem.callback()
    dibs.PlayerUI.Show = originalShow
    dibs.Message = originalMessage
    assert_equal("Player-1", shownPlayer)
    assert_equal("Player history: Player-1", messages[1])
    assert_equal("Name-Realm: Player-1", messages[2])
    assert_equal("Item: Midnight Blade", messages[3])
  end)

  it("uses the shared menu lifecycle and hides the request menu on cleanup", function()
    local _, dibs = loader.load({ withAce3 = true })
    local state = mocks.installMSA()
    local entries = {
      { text = "Open request", callback = function() end },
      { text = "View player history", callback = function() end },
    }
    assert_true(dibs.AceGUI.ShowContextMenu(entries))
    assert_true(dibs.AceGUI.ShowContextMenu(entries))
    assert_equal(1, state.created)
    assert_equal(2, state.initialized)
    dibs.AceGUI.HideContextMenu()
    dibs.AceGUI.HideContextMenu()
  end)
end)
