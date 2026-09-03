local loader = require("helpers.load_addon")

describe("Sync privacy", function()
  it("rejects live loot session fields in snapshots", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local ok = dibs.Sync.ApplySnapshot({
      transactions = {},
      candidates = { "A" },
    })
    assert_false(ok)
  end)
end)
