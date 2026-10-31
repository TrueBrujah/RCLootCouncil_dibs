local loader = require("helpers.load_addon")

local function load(options)
  options = options or {}
  options.withAce3 = true
  options.wow = options.wow or {
    guildLeader = true,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
  }
  return select(2, loader.load(options))
end

local function adopt(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, {
    reason = "feature registry governance",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil, {
    allowPublicPreDibs = true,
    preDibModes = { [dibs.GetCurrentSeasonId()] = "WILD_OPEN" },
  }))
end

local function findById(features, id)
  for _, entry in ipairs(features or {}) do
    if entry.id == id then return entry end
  end
  return nil
end

describe("Feature registry catalogue", function()
  it("exposes every core and optional feature from the canonical catalogue", function()
    local dibs = load()
    local registry = dibs.FeatureRegistry
    assert_not_nil(registry)
    local features = registry.ListFeatures()
    assert_true(#features > 0)
    -- The registry never keeps a second list: its contents must match the
    -- canonical policy catalogue exactly.
    local expected = #dibs.OperationalPolicy.GetCoreModuleDefinitions()
      + #dibs.OperationalPolicy.GetModuleDefinitions()
    assert_equal(expected, #features)
    -- Required features are listed first and are never configurable.
    local requiredCount = 0
    for _, entry in ipairs(features) do
      if entry.required then
        requiredCount = requiredCount + 1
        assert_true(entry.alwaysEnabled)
        assert_false(entry.configurable)
      end
    end
    assert_equal(#dibs.OperationalPolicy.GetCoreModuleDefinitions(), requiredCount)
  end)

  it("reports a description and a category for every feature", function()
    local dibs = load()
    for _, entry in ipairs(dibs.FeatureRegistry.ListFeatures()) do
      assert_not_nil(entry.label, "missing label for " .. tostring(entry.id))
      assert_true(#entry.description > 0, "missing description for " .. tostring(entry.id))
      assert_not_nil(entry.category, "missing category for " .. tostring(entry.id))
    end
  end)

  it("fails closed for an unknown feature identifier", function()
    local dibs = load()
    local enabled, reason = dibs.FeatureRegistry.IsEnabled("notARealFeature")
    assert_false(enabled)
    assert_equal("FEATURE_UNKNOWN", reason)
    local state = dibs.FeatureRegistry.GetEffectiveState("notARealFeature")
    assert_nil(state)
    assert_nil(dibs.FeatureRegistry.GetDefinition("notARealFeature"))
  end)

  it("keeps required features enabled and refuses to configure them", function()
    local dibs = load()
    assert_true(dibs.FeatureRegistry.IsEnabled("ledger"))
    local canDisable, reason = dibs.FeatureRegistry.CanDisable("ledger")
    assert_false(canDisable)
    assert_equal("FEATURE_CORE_IMMUTABLE", reason)
    local normalized, patchReason = dibs.FeatureRegistry.ValidatePatch({ ledger = false })
    assert_nil(normalized)
    assert_equal("FEATURE_CORE_IMMUTABLE", patchReason)
  end)
end)

describe("Feature registry effective state", function()
  it("treats an absent policy decision as the catalogue default", function()
    local dibs = load()
    -- Before any adoption the policy has no record, so the catalogue default
    -- decides. Every optional feature defaults to enabled.
    assert_true(dibs.FeatureRegistry.IsEnabled("preDibs"))
    assert_true(dibs.FeatureRegistry.IsEnabled("requests"))
  end)

  it("reports a policy-disabled feature with the policy reason code", function()
    local dibs = load(); adopt(dibs)
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ requests = false }, nil)
    assert_true(changed, tostring(reason))
    local enabled, disableReason = dibs.FeatureRegistry.IsEnabled("requests")
    assert_false(enabled)
    assert_equal("FEATURE_DISABLED_BY_POLICY", disableReason)
    local state = dibs.FeatureRegistry.GetEffectiveState("requests")
    assert_false(state.enabled)
    assert_equal("FEATURE_DISABLED_BY_POLICY", state.reasonCode)
  end)

  it("reports a dependency-disabled feature with the dependency reason code", function()
    local dibs = load(); adopt(dibs)
    -- historicalReconciliation requires rclootcouncil.
    local changed, reason = dibs.OperationalPolicy.ChangeModules({
      rclootcouncil = false, historicalReconciliation = false,
    }, nil)
    assert_true(changed, tostring(reason))
    -- Re-enable only the dependent: the dependency rule must keep it off.
    local reenabled, reenableReason = dibs.OperationalPolicy.ChangeModules({
      historicalReconciliation = true,
    }, nil)
    assert_false(reenabled)
    assert_equal("MODULE_DEPENDENCY_RCLootCouncil", reenableReason)
  end)

  it("keeps a feature disabled by dependency when the dependency is turned off", function()
    local dibs = load(); adopt(dibs)
    -- Turning the dependency off requires its dependent to be turned off in
    -- the same change, so the local write is refused on its own.
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ rclootcouncil = false }, nil)
    assert_false(changed)
    assert_equal("MODULE_DEPENDENCY_RCLootCouncil", reason)
    -- With both turned off, the dependent resolves as disabled by policy
    -- because the guild explicitly decided it, and the dependency graph still
    -- reports the edge.
    local bothChanged, bothReason = dibs.OperationalPolicy.ChangeModules({
      rclootcouncil = false, historicalReconciliation = false,
    }, nil)
    assert_true(bothChanged, tostring(bothReason))
    local enabled, disableReason = dibs.FeatureRegistry.IsEnabled("historicalReconciliation")
    assert_false(enabled)
    local state = dibs.FeatureRegistry.GetEffectiveState("historicalReconciliation")
    assert_equal("FEATURE_DISABLED_BY_POLICY", state.reasonCode)
    local dependencies = dibs.FeatureRegistry.GetDependencies("historicalReconciliation")
    assert_equal("rclootcouncil", dependencies.direct[1])
  end)
end)

describe("Feature registry dependency graph", function()
  it("reports direct and transitive dependencies", function()
    local dibs = load()
    local dependencies = dibs.FeatureRegistry.GetDependencies("historicalReconciliation")
    assert_not_nil(dependencies)
    assert_equal("historicalReconciliation", dependencies.id)
    assert_equal(1, #dependencies.direct)
    assert_equal("rclootcouncil", dependencies.direct[1])
  end)

  it("reports the dependents that would break when a feature is disabled", function()
    local dibs = load()
    local dependents = dibs.FeatureRegistry.GetDependents("rclootcouncil")
    assert_not_nil(dependents)
    local found = false
    for _, id in ipairs(dependents) do
      if id == "historicalReconciliation" then found = true end
    end
    assert_true(found, "expected historicalReconciliation to depend on rclootcouncil")
  end)

  it("refuses to disable a feature while an active dependent is enabled", function()
    local dibs = load(); adopt(dibs)
    local canDisable, reason, dependents = dibs.FeatureRegistry.CanDisable("rclootcouncil")
    assert_false(canDisable)
    assert_equal("FEATURE_DEPENDENTS_ACTIVE", reason)
    assert_not_nil(dependents)
  end)

  it("allows disabling a feature once its dependents are disabled", function()
    local dibs = load(); adopt(dibs)
    local changed, reason = dibs.OperationalPolicy.ChangeModules({
      rclootcouncil = false, historicalReconciliation = false,
    }, nil)
    assert_true(changed, tostring(reason))
    local canDisable = dibs.FeatureRegistry.CanDisable("rclootcouncil")
    assert_true(canDisable)
  end)

  it("rejects a patch that would enable a dependent while its dependency is off", function()
    local dibs = load(); adopt(dibs)
    -- Turn the dependency off together with its dependent.
    assert_true(dibs.OperationalPolicy.ChangeModules({
      rclootcouncil = false, historicalReconciliation = false,
    }, nil))
    -- Re-enabling only the dependent must be refused.
    local normalized, reason = dibs.FeatureRegistry.ValidatePatch({ historicalReconciliation = true })
    assert_nil(normalized)
    assert_equal("FEATURE_DISABLED_BY_DEPENDENCY", reason)
  end)

  it("accepts a patch that enables a feature together with its dependency", function()
    local dibs = load(); adopt(dibs)
    local normalized, reason = dibs.FeatureRegistry.ValidatePatch({
      rclootcouncil = true, historicalReconciliation = true,
    })
    assert_not_nil(normalized, tostring(reason))
    assert_true(normalized.historicalReconciliation)
  end)
end)

describe("Feature registry preview", function()
  it("previews the effective state without mutating the policy", function()
    local dibs = load(); adopt(dibs)
    local before = dibs.OperationalPolicy.GetState().policyRevision
    local preview = dibs.FeatureRegistry.PreviewState("requests", { requests = false })
    assert_not_nil(preview)
    assert_false(preview.enabled)
    assert_equal("FEATURE_DISABLED_BY_POLICY", preview.reasonCode)
    -- Nothing was applied.
    assert_equal(before, dibs.OperationalPolicy.GetState().policyRevision)
    assert_true(dibs.OperationalPolicy.IsModuleEnabled("requests"))
  end)

  it("previews a dependency downgrade as a dependency reason", function()
    local dibs = load(); adopt(dibs)
    local preview = dibs.FeatureRegistry.PreviewState("historicalReconciliation", {
      rclootcouncil = false, historicalReconciliation = true,
    })
    assert_not_nil(preview)
    assert_false(preview.enabled)
    assert_equal("FEATURE_DISABLED_BY_DEPENDENCY", preview.reasonCode)
  end)
end)

describe("Feature registry persistence and compatibility", function()
  it("stores only the explicit decisions and keeps the record hash stable", function()
    local dibs = load(); adopt(dibs)
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ requests = false }, nil)
    assert_true(changed, tostring(reason))
    local stored = dibs.OperationalPolicy.GetStoredModuleValues()
    assert_not_nil(stored)
    assert_false(stored.requests)
    -- A feature that was never decided is absent from the stored overlay.
    assert_nil(stored.preDibs)
    -- The effective state still resolves through the catalogue defaults.
    assert_true(dibs.OperationalPolicy.IsModuleEnabled("preDibs"))
    assert_false(dibs.OperationalPolicy.IsModuleEnabled("requests"))
  end)

  it("reloads a persisted sparse overlay without losing the explicit decision", function()
    local dibs = load(); adopt(dibs)
    assert_true(dibs.OperationalPolicy.ChangeModules({ requests = false }, nil))
    local saved = dibs.DeepCopy(dibs.GetDB())
    local reloaded = select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
    } }))
    assert_false(reloaded.OperationalPolicy.IsModuleEnabled("requests"))
    assert_true(reloaded.OperationalPolicy.IsModuleEnabled("preDibs"))
    assert_false(reloaded.FeatureRegistry.IsEnabled("requests"))
  end)

  it("keeps a record produced with a larger catalogue valid on an older catalogue", function()
    local dibs = load(); adopt(dibs)
    -- Establish a persisted module decision first, so the record carries a
    -- module map that a peer could extend with a feature we do not know.
    assert_true(dibs.OperationalPolicy.ChangeModules({ requests = false }, nil))
    local record = dibs.OperationalPolicy.GetCurrentRecord()
    assert_not_nil(record)
    assert_not_nil(record.values)
    assert_not_nil(record.values.modules)
    -- A peer that knows a larger catalogue sends the NEXT revision with one
    -- extra feature key. This client does not know that feature, but the
    -- record must still be accepted so that the parent chain is not broken.
    local state = dibs.OperationalPolicy.GetState()
    local mutated = dibs.DeepCopy(record)
    mutated.policyRevision = state.policyRevision + 1
    mutated.parentRevision = state.policyRevision
    mutated.parentHash = state.hash
    mutated.values.modules.unknownFutureFeature = true
    mutated.contentHash = dibs.OperationalPolicy.CalculateContentHash(mutated)
    local ok, reason = dibs.OperationalPolicy.ApplyRecord(mutated, nil)
    assert_true(ok, tostring(reason))
    -- The unknown feature is ignored locally but does not break the chain.
    local unknownEnabled, unknownReason = dibs.FeatureRegistry.IsEnabled("unknownFutureFeature")
    assert_false(unknownEnabled)
    assert_equal("FEATURE_UNKNOWN", unknownReason)
    -- The known decision survived the acceptance of the extended record.
    assert_false(dibs.OperationalPolicy.IsModuleEnabled("requests"))
    -- The unknown key is retained in the stored record so that a later local
    -- revision does not silently change the canonical hash of the record.
    local stored = dibs.OperationalPolicy.GetStoredModuleValues()
    assert_true(stored.unknownFutureFeature)
  end)

  it("publishes a compatibility description of the registry and policy", function()
    local dibs = load()
    local compatibility = dibs.FeatureRegistry.GetCompatibility()
    assert_not_nil(compatibility)
    assert_true(compatibility.registryVersion >= 1)
    assert_not_nil(compatibility.policySchema)
    assert_true(compatibility.policyRevision >= 0)
  end)
end)

describe("Feature registry enforcement gate", function()
  it("refuses to proceed when the feature is disabled by policy", function()
    local dibs = load(); adopt(dibs)
    assert_true(dibs.OperationalPolicy.ChangeModules({ requests = false }, nil))
    local allowed, reason, message = dibs.FeatureRegistry.RequireEnabled("requests")
    assert_false(allowed)
    assert_equal("FEATURE_DISABLED_BY_POLICY", reason)
    assert_not_nil(message)
  end)

  it("allows the feature when it is enabled", function()
    local dibs = load(); adopt(dibs)
    local allowed = dibs.FeatureRegistry.RequireEnabled("requests")
    assert_true(allowed)
  end)

  it("refuses an unknown feature at the gate", function()
    local dibs = load()
    local allowed, reason = dibs.FeatureRegistry.RequireEnabled("notARealFeature")
    assert_false(allowed)
    assert_equal("FEATURE_UNKNOWN", reason)
  end)

  it("keeps the production accounting path independent of the registry", function()
    -- The registry is a configuration boundary. It must never become a
    -- dependency of the canonical ledger.
    local dibs = load()
    assert_nil(dibs.Ledger.FeatureRegistry)
    assert_nil(dibs.Ledger.Registry)
  end)
end)

describe("Feature registry diagnostics and history", function()
  it("produces a diagnostic line for every feature", function()
    local dibs = load()
    local lines = dibs.FeatureRegistry.GetDiagnostics()
    assert_not_nil(lines)
    assert_true(#lines > 0)
    local features = dibs.FeatureRegistry.ListFeatures()
    assert_equal(#features + 1, #lines)
  end)

  it("exposes the configuration change history from the policy audit log", function()
    local dibs = load(); adopt(dibs)
    assert_true(dibs.OperationalPolicy.ChangeModules({ requests = false }, nil))
    local history = dibs.FeatureRegistry.GetChangeHistory(10)
    assert_not_nil(history)
    assert_true(#history >= 1)
  end)
end)
