local wow = require("helpers.wow_api")

describe("Minimap button", function()
  before_each(function()
    wow.install({ guildLeader = true })
    _G.Minimap = _G.CreateFrame("Frame")
    dofile("src/Core.lua")
    dofile("src/locales/enUS.lua")
    dofile("src/modules/Permissions.lua")
    dofile("src/ui/MinimapButton.lua")
  end)

  it("creates a local shortcut without changing authority state", function()
    local button = Dibs.MinimapButton.Create()
    assert_true(button ~= nil)
    assert_equal(button.parent, _G.Minimap)
    assert_equal(button.icon._texture, Dibs.ICON_TEXTURE)
  end)

  it("keeps creation safe when Minimap is unavailable", function()
    local previous = _G.Minimap
    _G.Minimap = nil
    Dibs.MinimapButton.button = nil
    assert_equal(Dibs.MinimapButton.Create(), nil)
    _G.Minimap = previous
  end)
end)
