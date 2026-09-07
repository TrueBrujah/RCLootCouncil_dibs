local loader = require("helpers.load_addon")

describe("RCLootCouncil response normalization", function()
  it("normalizes explicit DIB labels with case and display punctuation", function()
    local _, dibs = loader.load({ rclootcouncil = loader.makeRCLootCouncil() })
    assert_equal("DIB", select(1, dibs.RCLootCouncil.NormalizeDibResponse("  [dib]  ")))
    assert_equal("DIB", select(1, dibs.RCLootCouncil.NormalizeDibResponse("DIBS")))
  end)

  it("resolves numeric response identifiers through RCLootCouncil", function()
    local rc = loader.makeRCLootCouncil()
    rc.GetResponse = function(_, _, value)
      if tonumber(value) == 4 then return { text = "DIB" } end
      return { text = "Need" }
    end
    local _, dibs = loader.load({ rclootcouncil = rc })
    assert_equal("DIB", select(1, dibs.RCLootCouncil.NormalizeDibResponse(4)))
    assert_equal("NON_DIB_RESPONSE", select(2, dibs.RCLootCouncil.NormalizeDibResponse(1)))
  end)

  it("rejects empty and conflicting response values", function()
    local _, dibs = loader.load({ rclootcouncil = loader.makeRCLootCouncil() })
    assert_equal("EMPTY_RESPONSE", select(2, dibs.RCLootCouncil.NormalizeDibResponse("   ")))
    assert_equal("AMBIGUOUS_RESPONSE", select(2, dibs.RCLootCouncil.NormalizeDibResponse({ text = "DIB", response = "Need" })))
    assert_false(dibs.RCLootCouncil.IsDibResponse("DIB + Need"))
  end)
end)
