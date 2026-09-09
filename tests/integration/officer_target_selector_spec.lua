local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

describe("Officer target selectors", function()
  it("filters guild players and Adventure Guide loot in correction controls", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Friend-Realm" } },
      withAce3 = true,
    })
    wow.installEncounterJournalContext({
      raidInstances = { { id = 900, name = "Citadel of Testing" } },
      encounters = { [900] = { { id = 901, name = "Test Warden" } } },
      loot = { [901] = { { itemID = 280001, name = "Warden's Curio", link = "|Hitem:280001::::::::::::|h[Warden's Curio]|h|r" } } },
    })
    local request = dibs.Disputes.CreateReport({ category = "wrong_item_player", note = "selector test" })
    assert_not_nil(request)

    local officer = dibs.OfficerUI.CreateWindow()
    officer.SelectTab("disputes")
    local initialWidgets = {}
    for index, widget in ipairs(_G.__dibsAceWidgets or {}) do initialWidgets[index] = widget end
    for _, widget in ipairs(initialWidgets) do
      if widget.kind == "Button" and widget.text == "Open" and widget.callbacks and widget.callbacks.OnClick then
        widget.callbacks.OnClick(widget)
      end
    end

    local playerDropdown, itemDropdown
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Dropdown" and widget.label == "Correct player" then playerDropdown = widget end
      if widget.kind == "Dropdown" and widget.label == "Correct item" then itemDropdown = widget end
    end
    assert_not_nil(playerDropdown)
    assert_equal("Friend-Realm", playerDropdown.list["Friend-Realm"])
    assert_not_nil(itemDropdown)
    local foundItem = false
    for key, label in pairs(itemDropdown.list or {}) do
      if tostring(key):find("280001", 1, true) and tostring(label):find("Warden's Curio", 1, true) then foundItem = true end
    end
    assert_true(foundItem)
  end)
end)
