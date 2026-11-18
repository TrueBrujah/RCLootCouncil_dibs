local loader = require("helpers.load_addon")

local function load(options)
  local _, dibs = loader.load(options or { withAce3 = true, wow = { guildLeader = true } })
  local notices = {}
  dibs.Message = function(message) notices[#notices + 1] = message end
  return dibs, notices
end

describe("Scoped guided setup preset feedback", function()
  it("applies the same real standalone policy silently and retains status for the addon", function()
    local dibs, notices = load()
    assert_true(dibs.RCOptions.ApplyInstallationPreset("progression", { silent = true }))
    assert_equal(0, #notices)
    assert_true(dibs.RCOptions.state.status:find("preset applied", 1, true) ~= nil)
    assert_true(dibs.RCLootCouncil.IsDibEnabledForType("TOKEN"))
    assert_true(dibs.RCLootCouncil.IsDibEnabledForType("TOKEN_SET"))
    assert_false(dibs.RCLootCouncil.IsDibEnabledForType("MOUNTS"))
  end)

  it("does not suppress subsequent direct options notices", function()
    local dibs, notices = load()
    assert_true(dibs.RCOptions.ApplyInstallationPreset("progression", { silent = true }))
    assert_true(dibs.RCOptions.ApplyInstallationPreset("broad"))
    assert_equal(2, #notices)
    assert_true(notices[1]:find("DIB semantic template", 1, true) ~= nil)
    assert_true(notices[2]:find("preset applied", 1, true) ~= nil)
    assert_true(dibs.RCLootCouncil.IsDibEnabledForType("MOUNTS"))
  end)

  it("suppresses projection success notices without skipping the projection", function()
    local dibs, notices = load()
    local projected = 0
    dibs.RCLootCouncil.RefreshConfigProjection = function() projected = projected + 1; return true, true end
    assert_true(dibs.RCOptions.ApplyInstallationPreset("progression", { silent = true }))
    assert_equal(1, projected)
    assert_equal(0, #notices)
    assert_true(dibs.RCOptions.state.status:find("configured RCLootCouncil sets", 1, true) ~= nil)
  end)

  it("retains invalid-template and permission failures without chat spam", function()
    local dibs, notices = load()
    local ok, reason = dibs.RCOptions.ApplyInstallationPreset("unknown", { silent = true })
    assert_false(ok)
    assert_equal("UNKNOWN_DIBS_SEMANTIC_TEMPLATE", reason)
    assert_equal(0, #notices)
    dibs.Permissions.Can = function() return false end
    ok, reason = dibs.RCOptions.ApplyInstallationPreset("progression", { silent = true })
    assert_false(ok)
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
    assert_equal(0, #notices)
  end)

  it("returns a nested draft-write error silently and stops applying the template", function()
    local dibs, notices = load()
    local writes = 0
    dibs.RCLootCouncil.SetDibEnabledForType = function()
      writes = writes + 1
      return nil, "TEST_WRITE_REJECTED"
    end
    local ok, reason = dibs.RCOptions.ApplyInstallationPreset("progression", { silent = true })
    assert_false(ok)
    assert_equal("TEST_WRITE_REJECTED", reason)
    assert_equal(1, writes)
    assert_equal(0, #notices)
    assert_equal("TEST_WRITE_REJECTED", dibs.RCOptions.state.status)
  end)
end)
