local loader = require("helpers.load_addon")

local function getLootCheck(dibs)
  local report = dibs.SetupAssistant.Evaluate()
  for _, item in ipairs(report.checks or {}) do
    if item.id == "loot_types" then return item, report end
  end
  error("Loot Rules readiness check is missing")
end

describe("First installation assistant integration", function()
  it("can omit its optional Sync check without changing the guild setup verdict", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local originalBehind = dibs.Sync.IsSyncBehind
    dibs.Sync.IsSyncBehind = function() return true, "SYNC_BEHIND" end

    local complete = dibs.SetupAssistant.Evaluate({ scope = "guild" })
    local withoutSync = dibs.SetupAssistant.Evaluate({ scope = "guild", includeSyncState = false })
    dibs.Sync.IsSyncBehind = originalBehind

    local completeSync, omittedSync
    for _, item in ipairs(complete.checks or {}) do
      if item.id == "sync_state" then completeSync = item end
    end
    for _, item in ipairs(withoutSync.checks or {}) do
      if item.id == "sync_state" then omittedSync = item end
    end
    assert_not_nil(completeSync)
    assert_equal("degraded", completeSync.state)
    assert_equal(nil, omittedSync)
    assert_equal(complete.status, withoutSync.status,
      "the Sync check is optional and must not affect the guild setup verdict")
  end)

  it("profiles setup and readiness substeps with CPU-only samples", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local timer = _G.debugprofilestop
    register_reset(function()
      _G.debugprofilestop = timer
      dibs.UIRenderStats.SetEnabled(false)
    end)
    local clock = 0
    _G.debugprofilestop = function() clock = clock + 1; return clock end
    dibs.UIRenderStats.SetEnabled(true)

    local report = dibs.SetupAssistant.Evaluate({ scope = "guild" })
    local rows = {}
    for _, row in ipairs(dibs.UIRenderStats.GetReport().pages) do
      rows[row.kind .. "/" .. row.page] = row
    end

    assert_true(report.status == "READY_FOR_RAID" or report.status == "NEEDS_ATTENTION" or report.status == "UNAVAILABLE")
    for _, key in ipairs({
      "Setup data/actor-role", "Setup data/readiness-check-mapping", "Setup data/season-lookup",
      "Setup data/sync-state-check", "Setup data/scope-filter", "Setup data/report-finalization",
      "Setup data/loot-type-option-tree", "Setup data/loot-type-values",
      "RC options data/loot-type-values-core", "RC options data/loot-type-values-settings",
      "RC options data/loot-type-values-rc-buttons", "RC options data/loot-type-values-projection",
      "Readiness data/evaluation-input-state", "Readiness data/fingerprint", "Readiness data/probe-composition",
    }) do
      assert_not_nil(rows[key], key .. " timing should be recorded")
      assert_equal(0, rows[key].heapSampleCount, key .. " timing must avoid global heap sampling")
    end
  end)

  it("reads the Loot Rules option tree and dynamic values once per evaluation", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local originalOptions = dibs.RCOptions.GetLootTypeOptions
    local options = originalOptions()
    local originalValues = options.types.values
    local optionCalls, valueCalls = 0, 0
    dibs.RCOptions.GetLootTypeOptions = function(...)
      optionCalls = optionCalls + 1
      local result = originalOptions(...)
      result.types.values = function(...)
        valueCalls = valueCalls + 1
        return originalValues(...)
      end
      return result
    end

    local ok, report = pcall(dibs.SetupAssistant.Evaluate, { scope = "guild" })

    dibs.RCOptions.GetLootTypeOptions = originalOptions
    options.types.values = originalValues
    assert_true(ok, tostring(report))
    assert_equal(1, optionCalls)
    assert_equal(1, valueCalls)
    assert_not_nil(report)
  end)

  it("skips the season lookup when readiness already supplied season and policy checks", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local originalEvaluate = dibs.Readiness.Evaluate
    local originalGetCurrent = dibs.Seasons.GetCurrent
    dibs.Readiness.Evaluate = function()
      return { status = "READY_FOR_RAID", probes = {
        { name = "season", state = "ready", required = true },
        { name = "policy", state = "ready", required = true },
      } }
    end
    dibs.Seasons.GetCurrent = function() error("both readiness checks already provide the season result") end

    local ok, report = pcall(dibs.SetupAssistant.Evaluate, { scope = "guild" })

    dibs.Readiness.Evaluate = originalEvaluate
    dibs.Seasons.GetCurrent = originalGetCurrent
    assert_true(ok, tostring(report))
    local seen = {}
    for _, item in ipairs(report.checks or {}) do seen[item.id] = true end
    assert_true(seen.season)
    assert_true(seen.policy)

    dibs.Readiness.Evaluate = function()
      return { status = "NEEDS_ATTENTION", probes = {
        { name = "season", state = "ready", required = true },
      } }
    end
    local seasonLookups = 0
    dibs.Seasons.GetCurrent = function()
      seasonLookups = seasonLookups + 1
      return { id = "fallback-season", isArchived = false }
    end
    local originalGetRules = dibs.RankRules.GetRulesForSeason
    dibs.RankRules.GetRulesForSeason = function() return { ["0"] = { allocation = 1 } } end
    local fallbackOk, fallbackReport = pcall(dibs.SetupAssistant.Evaluate, { scope = "guild" })
    dibs.Readiness.Evaluate = originalEvaluate
    dibs.Seasons.GetCurrent = originalGetCurrent
    dibs.RankRules.GetRulesForSeason = originalGetRules
    assert_true(fallbackOk, tostring(fallbackReport))
    assert_equal(1, seasonLookups, "a missing policy check should retain the season/rule fallback")
    local hasRankRules = false
    for _, item in ipairs(fallbackReport.checks or {}) do
      if item.id == "rank_rules" and item.state == "ready" then hasRankRules = true end
    end
    assert_true(hasRankRules)
  end)

  it("delegates local dry-run without creating ledger state", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local before = #((dibs.GetDB() or {}).ledger and dibs.GetDB().ledger.transactions or {})
    local result = dibs.SetupAssistant.RunDryRun({
      item = 275658,
      winner = "Tester-Realm",
      response = "DIB",
      status = "test",
      sessionIdentity = "setup-assistant-test",
    }, { allowPlayer = true })
    assert_not_nil(result)
    assert_equal("would_ignore", result.outcome)
    local after = #((dibs.GetDB() or {}).ledger and dibs.GetDB().ledger.transactions or {})
    assert_equal(before, after)
    assert_false(result.wouldConsumeDib)
  end)

  it("returns a bounded unavailable result when the dry-run service is absent", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local original = dibs.DryRun.Run
    dibs.DryRun.Run = nil
    local result, reason = dibs.SetupAssistant.RunDryRun({ item = 275658 }, { allowPlayer = true })
    dibs.DryRun.Run = original
    assert_equal(nil, result)
    assert_equal("DRY_RUN_UNAVAILABLE", reason)
  end)

  it("reports the real Loot Rules option source as available and ready", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local options = dibs.RCOptions.GetLootTypeOptions()
    assert_not_nil(options.types)
    assert_equal("function", type(options.types.values))
    assert_equal("function", type(options.types.get))
    assert_equal("function", type(options.types.set))
    local check = getLootCheck(dibs)
    assert_equal("ready", check.state)
    assert_equal(nil, check.reasonCode)
    assert_equal("options", check.source)
  end)

  it("keeps valid local Loot Rules ready when operational policy is unadopted or adopted", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local changed = dibs.RCLootCouncil.SetDibEnabledForType("MOUNTS", false)
    assert_true(changed)
    assert_equal(false, dibs.GetDB().settings.dibAllowedTypes.MOUNTS)

    dibs.OperationalPolicy.IsAdopted = function() return false end
    local unadopted = getLootCheck(dibs)
    assert_equal("ready", unadopted.state)
    assert_equal("Controls available", unadopted.scopeLabel)
    assert_true(unadopted.scopeExplanation:find("explicitly adopt", 1, true) ~= nil)

    dibs.OperationalPolicy.IsAdopted = function() return true end
    local adopted = getLootCheck(dibs)
    assert_equal("ready", adopted.state)
    assert_true(adopted.scopeExplanation:find("guild authority", 1, true) ~= nil)
  end)

  it("reports a missing Loot Rules option source as unavailable", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.RCOptions.GetLootTypeOptions = nil
    local check = getLootCheck(dibs)
    assert_equal("unavailable", check.state)
    assert_equal("LOOT_TYPES_UNAVAILABLE", check.reasonCode)
  end)

  it("reports malformed Loot Rules option data as a warning", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.RCOptions.GetLootTypeOptions = function()
      return { types = { values = function() return {} end } }
    end
    local check = getLootCheck(dibs)
    assert_equal("degraded", check.state)
    assert_equal("LOOT_TYPES_INVALID", check.reasonCode)
  end)

  it("uses accurate GM and Officer local-scope explanations", function()
    local _, gm = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    gm.Permissions.GetGuildRole = function() return "gm" end
    local gmCheck = getLootCheck(gm)
    assert_equal("Loot Rules controls are available. Review the draft and explicitly adopt it to establish guild authority.", gmCheck.scopeExplanation)

    local _, officer = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    officer.Permissions.GetGuildRole = function() return "officer" end
    local officerCheck = getLootCheck(officer)
    assert_equal("Loot Rules controls are available. Only the Guild Master can adopt or publish guild authority.", officerCheck.scopeExplanation)
  end)

  it("re-probes the Loot Rules option source on each readiness evaluation", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local source = dibs.RCOptions.GetLootTypeOptions()
    local calls = 0
    dibs.RCOptions.GetLootTypeOptions = function()
      calls = calls + 1
      if calls == 1 then return source end
      return nil
    end
    local first = getLootCheck(dibs)
    local second = getLootCheck(dibs)
    assert_equal("ready", first.state)
    assert_equal("unavailable", second.state)
    assert_equal(2, calls)
  end)
end)
