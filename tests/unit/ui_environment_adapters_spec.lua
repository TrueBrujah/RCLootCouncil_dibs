local loader = require("helpers.load_addon")

describe("B11a presentation environment adapters", function()
  after_each(function()
    _G.ElvUI = nil
    _G.Tukui = nil
    _G.ELVUI = nil
  end)

  it("falls back to native Midnight when no external environment exists", function()
    local _, dibs = loader.load()
    local tokens, probe = dibs.EnvironmentAdapters.ResolveTokens()
    assert_equal("NATIVE", probe.environment)
    assert_equal("absent", probe.status)
    assert_equal("MIDNIGHT", tokens.theme)
  end)

  it("accepts only presentation hints from an available adapter", function()
    local _, dibs = loader.load()
    _G.ELVUI = { DibsPresentationHints = { font = "ExternalFont", scale = 1.2, ledger = "forbidden" } }
    local tokens, probe = dibs.EnvironmentAdapters.ResolveTokens()
    assert_equal("ELVUI", probe.environment)
    assert_equal("available", probe.status)
    assert_equal("ExternalFont", tokens.typography.font)
    assert_equal(1.2, tokens.scale)
    assert_nil(tokens.ledger)
  end)

  it("returns native Midnight after a provider failure or unsupported hint", function()
    local _, dibs = loader.load()
    assert_true(dibs.EnvironmentAdapters.Register("ELVUI", function() return "failed", nil, "BROKEN" end))
    local tokens, probe = dibs.EnvironmentAdapters.ResolveTokens()
    assert_equal("ELVUI", probe.environment)
    assert_equal("failed", probe.status)
    assert_equal("MIDNIGHT", tokens.theme)
    assert_true(dibs.EnvironmentAdapters.Register("ELVUI", function() return "available", { scale = 99 }, "BAD_HINT" end))
    tokens, probe = dibs.EnvironmentAdapters.ResolveTokens()
    assert_equal("MIDNIGHT", tokens.theme)
    assert_nil(tokens.adapterHints.scale)
  end)
end)
