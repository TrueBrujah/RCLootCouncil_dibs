local loader = require("helpers.load_addon")

local function load()
  return select(2, loader.load({ withAce3 = true, wow = {
    guildLeader = true,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
  } }))
end

local function findButton(widget, text)
  if type(widget) ~= "table" then return nil end
  if widget.kind == "Button" and (widget.text == text or widget.label == text) then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findButton(child, text)
    if found then return found end
  end
  return nil
end

local function findEnabledCheckBox(widget)
  if type(widget) ~= "table" then return nil end
  if widget.kind == "CheckBox" and widget.disabled ~= true then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findEnabledCheckBox(child)
    if found then return found end
  end
  return nil
end

local function findCheckBox(widget, label)
  if type(widget) ~= "table" then return nil end
  if widget.kind == "CheckBox" and (label == nil or widget.label == label) then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findCheckBox(child, label)
    if found then return found end
  end
  return nil
end

local function findLabel(widget, text)
  if type(widget) ~= "table" then return nil end
  if widget.kind == "Label" and widget.text == text then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findLabel(child, text)
    if found then return found end
  end
  return nil
end

local function containsText(widget, text)
  if type(widget) ~= "table" then return false end
  if tostring(widget.text or ""):find(text, 1, true) or tostring(widget.label or ""):find(text, 1, true) then return true end
  for _, child in ipairs(widget.children or {}) do
    if containsText(child, text) then return true end
  end
  return false
end

local function hasNavigationEntry(tree, value)
  for _, entry in ipairs(tree or {}) do
    if entry.value == value then return true end
  end
  return false
end

local function hasNavigationSection(tree, section)
  for _, entry in ipairs(tree or {}) do
    if entry.section == section then return true end
  end
  return false
end

local function collectCheckBoxes(widget, result)
  result = result or {}
  if type(widget) ~= "table" then return result end
  if widget.kind == "CheckBox" then result[#result + 1] = widget end
  for _, child in ipairs(widget.children or {}) do collectCheckBoxes(child, result) end
  return result
end

local function adopt(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, {
    reason = "module test governance",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "GOVERNANCE_ONLY" },
  }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil, {
    allowPublicPreDibs = true,
    preDibModes = { [dibs.GetCurrentSeasonId()] = "WILD_OPEN" },
  }))
end

describe("B12 module management", function()
  it("renders the GM bootstrap action and refreshes the Modules page after confirmation", function()
    local dibs = load()
    local frame = dibs.OfficerUI.CreateWindow("modules")
    local initialize = findButton(frame.contentHost, "Initialize Guild Governance")
    assert_not_nil(initialize)
    initialize.callbacks.OnClick()
    local confirm = findButton(frame.contentHost, "Initialize")
    assert_not_nil(confirm)
    confirm.callbacks.OnClick()
    assert_equal("GOVERNANCE_ADOPTED", dibs.Governance.GetState().status)
    assert_not_nil(findEnabledCheckBox(frame.contentHost))
  end)

  it("does not render a bootstrap action for an officer", function()
    local dibs = select(2, loader.load({ withAce3 = true, wow = {
      playerName = "Officer-Realm", guildLeader = false,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
    } }))
    local frame = dibs.OfficerUI.CreateWindow("modules")
    assert_nil(findButton(frame.contentHost, "Initialize Guild Governance"))
  end)

  it("exposes bootstrap only to the verified GM and does not auto-adopt", function()
    local dibs = load()
    assert_equal("POLICY_UNINITIALIZED", dibs.Governance.GetState().status)
    local before = dibs.DeepCopy(dibs.GetDB())
    assert_true(dibs.Governance.CanAdoptInitial(nil))
    assert_equal("POLICY_UNINITIALIZED", dibs.Governance.GetState().status)
    assert_equal(before.governance.status, dibs.GetDB().governance.status)
    assert_equal(before.governance.revision, dibs.GetDB().governance.revision)
    assert_equal(before.governance.hash, dibs.GetDB().governance.hash)

    local officer = select(2, loader.load({ withAce3 = true, wow = {
      playerName = "Officer-Realm", guildLeader = false,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
    } }))
    assert_false(officer.Governance.CanAdoptInitial(nil))

    local player = select(2, loader.load({ withAce3 = true, wow = {
      playerName = "Player-Realm", guildLeader = false,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
    } }))
    assert_false(player.Governance.CanAdoptInitial(nil))
  end)

  it("creates canonical governance audit evidence through the existing bootstrap service", function()
    local dibs = load()
    local ok, reason = dibs.Governance.AdoptInitial(nil, {
      reason = "MODULE_MANAGEMENT_BOOTSTRAP",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "GOVERNANCE_ONLY" },
    })
    assert_true(ok, tostring(reason))
    local state, record = dibs.Governance.GetState(), dibs.Governance.GetCurrentRecord()
    assert_equal("GOVERNANCE_ADOPTED", state.status)
    assert_equal(1, state.revision)
    assert_equal(1, #state.auditLog)
    assert_equal("MODULE_MANAGEMENT_BOOTSTRAP", record.audit.reason)
    assert_equal("Tester-Realm", record.authorNameRealm)
  end)

  it("lets a GM create module state without adopting unrelated operational policy", function()
    local dibs = load()
    assert_true(dibs.Governance.AdoptInitial(nil, {
      reason = "module-only governance",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "GOVERNANCE_ONLY" },
    }))
    assert_false(dibs.OperationalPolicy.IsAdopted())
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ preDibs = false }, nil)
    assert_true(changed, tostring(reason))
    assert_true(dibs.OperationalPolicy.IsAdopted())
    assert_false(dibs.OperationalPolicy.IsModuleEnabled("preDibs"))
    assert_nil(dibs.OperationalPolicy.GetValues().allowPublicPreDibs)
  end)

  it("treats canonical GM governance as sufficient without operational policy", function()
    local dibs = load()
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "module-only UI governance" }))
    assert_false(dibs.OperationalPolicy.IsAdopted())
    local diagnostics = dibs.OperationalPolicy.GetModuleManagementDiagnostics(nil)
    assert_true(diagnostics.governanceInitialized)
    assert_true(diagnostics.governanceActive)
    assert_false(diagnostics.operationalPolicyReady)
    assert_true(diagnostics.canManageModules)
    local frame = dibs.OfficerUI.CreateWindow("modules")
    assert_not_nil(findEnabledCheckBox(frame.contentHost))
  end)

  it("accepts a short local player name when the roster provides the canonical Name-Realm", function()
    local dibs = select(2, loader.load({ withAce3 = true, wow = {
      playerName = "Tester", guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 },
    } }))
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "short name identity" }))
    local diagnostics = dibs.OperationalPolicy.GetModuleManagementDiagnostics(nil)
    assert_equal("Tester-Realm", diagnostics.canonicalPlayer)
    assert_equal("Tester-Realm", diagnostics.governanceGM)
    assert_true(diagnostics.gmIdentityMatch)
    assert_true(diagnostics.canManageModules)
  end)

  it("renders the exact blocking reason for an officer", function()
    local gm = load()
    assert_true(gm.Governance.AdoptInitial(nil, { reason = "officer read-only" }))
    local savedVariables = gm.DeepCopy(gm.GetDB())
    local dibs = select(2, loader.load({ withAce3 = true, savedVariables = savedVariables, wow = {
      playerName = "Officer-Realm", guildLeader = false,
      guildMembers = { "Tester-Realm", "Officer-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 },
    } }))
    local diagnostics = dibs.OperationalPolicy.GetModuleManagementDiagnostics(nil)
    assert_false(diagnostics.canManageModules)
    assert_equal("CURRENT_GUILD_MASTER_REQUIRED", diagnostics.blockingReason)
    local frame = dibs.OfficerUI.CreateWindow("modules")
    assert_not_nil(findEnabledCheckBox(frame.contentHost) or findCheckBox(frame.contentHost))
    assert_not_nil(findLabel(frame.contentHost, "Module management unavailable"))
  end)

  it("keeps checkbox changes local until Save delegates to the policy service", function()
    local dibs = load()
    adopt(dibs)
    local calls = 0
    local changeModules = dibs.OperationalPolicy.ChangeModules
    dibs.OperationalPolicy.ChangeModules = function(...)
      calls = calls + 1
      return changeModules(...)
    end
    local frame = dibs.OfficerUI.CreateWindow("modules")
    local checkbox = findCheckBox(frame.contentHost)
    assert_not_nil(checkbox)
    checkbox.callbacks.OnValueChanged(checkbox, "OnValueChanged", false)
    dibs.AceGUI.FlushRefreshes()
    assert_true(dibs.OperationalPolicy.IsModuleEnabled("preDibs"))
    assert_true(frame.moduleDraft.preDibs == false)
    assert_not_nil(findLabel(frame.contentHost, "Modules - Unsaved changes"))
    assert_not_nil(findButton(frame.contentHost, "Reset"))
    local save = findButton(frame.contentHost, "Save changes")
    assert_not_nil(save)
    save.callbacks.OnClick()
    assert_equal(1, calls)
    assert_false(dibs.OperationalPolicy.IsModuleEnabled("preDibs"))
  end)

  it("resets the draft to the authoritative module state", function()
    local dibs = load()
    adopt(dibs)
    local frame = dibs.OfficerUI.CreateWindow("modules")
    local checkbox = findCheckBox(frame.contentHost)
    checkbox.callbacks.OnValueChanged(checkbox, "OnValueChanged", false)
    dibs.AceGUI.FlushRefreshes()
    assert_false(frame.moduleDraft.preDibs)
    findButton(frame.contentHost, "Reset").callbacks.OnClick()
    assert_true(frame.moduleDraft.preDibs)
    assert_true(dibs.OperationalPolicy.IsModuleEnabled("preDibs"))
  end)

  it("preserves the draft when Save fails and disables only dependent modules", function()
    local dibs = load()
    adopt(dibs)
    local frame = dibs.OfficerUI.CreateWindow("modules")
    local originalChange = dibs.OperationalPolicy.ChangeModules
    dibs.OperationalPolicy.ChangeModules = function() return false, "TEST_SAVE_FAILED" end
    local checkbox = findCheckBox(frame.contentHost)
    checkbox.callbacks.OnValueChanged(checkbox, "OnValueChanged", false)
    dibs.AceGUI.FlushRefreshes()
    assert_false(frame.moduleDraft.preDibs)
    assert_true(dibs.OperationalPolicy.IsModuleEnabled("preDibs"))
    local controls = collectCheckBoxes(frame.contentHost)
    local enabled = 0
    for _, control in ipairs(controls) do if control.disabled ~= true then enabled = enabled + 1 end end
    assert_equal(6, enabled)
    findButton(frame.contentHost, "Save changes").callbacks.OnClick()
    assert_false(frame.moduleDraft.preDibs)
    assert_true(dibs.OperationalPolicy.IsModuleEnabled("preDibs"))
    dibs.OperationalPolicy.ChangeModules = originalChange
  end)

  it("lets an explicitly authorized officer create module state", function()
    local gm = load()
    assert_true(gm.Governance.AdoptInitial(nil, {
      reason = "module officer governance",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    }))
    local savedVariables = gm.DeepCopy(gm.GetDB())
    local dibs = select(2, loader.load({ withAce3 = true, savedVariables = savedVariables, wow = {
      playerName = "Officer-Realm",
      guildLeader = false,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
    } }))
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ requests = false }, "Officer-Realm")
    assert_true(changed, tostring(reason))
    assert_false(dibs.OperationalPolicy.IsModuleEnabled("requests"))
  end)

  it("keeps core services immutable and changes optional modules in one policy revision", function()
    local dibs = load(); adopt(dibs)
    local core = dibs.OperationalPolicy.GetCoreModuleDefinitions()
    assert_equal(7, #core)
    assert_true(core[1].alwaysEnabled)
    local beforeRequests = dibs.GetDB().disputes
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ preDibs = false, requests = false }, nil, "test module change")
    assert_true(changed, tostring(reason))
    assert_equal(2, dibs.OperationalPolicy.GetState().policyRevision)
    assert_false(dibs.OperationalPolicy.IsModuleEnabled("preDibs"))
    assert_false(dibs.OperationalPolicy.IsModuleEnabled("requests"))
    assert_equal(beforeRequests, dibs.GetDB().disputes)
    local audit = dibs.OperationalPolicy.GetCurrentRecord().audit.moduleChanges
    assert_true(audit ~= nil)
    assert_true(audit.old.preDibs)
    assert_false(audit.new.preDibs)
    assert_equal("preDibs", audit.changes[1].moduleId)
    assert_true(audit.changes[1].oldState)
    assert_false(audit.changes[1].newState)
    assert_not_nil(dibs.OperationalPolicy.GetCurrentRecord().audit.governanceRevision)
    local request, requestReason = dibs.Disputes.CreateReport({}, nil)
    assert_nil(request)
    assert_equal("MODULE_DISABLED_REQUESTS", requestReason)
    local public, publicReason = dibs.PreDibs.CreatePublic(nil, 1)
    assert_nil(public)
    assert_equal("MODULE_DISABLED_PRE_DIBS", publicReason)
  end)

  it("rejects invalid dependencies without changing the current policy", function()
    local dibs = load(); adopt(dibs)
    local before = dibs.OperationalPolicy.GetState()
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ rclootcouncil = false }, nil)
    assert_false(changed)
    assert_equal("MODULE_DEPENDENCY_RCLootCouncil", reason)
    local after = dibs.OperationalPolicy.GetState()
    assert_equal(before.policyRevision, after.policyRevision)
    assert_true(dibs.OperationalPolicy.IsModuleEnabled("rclootcouncil"))
  end)

  it("denies unknown module keys and preserves disabled module data for re-enable", function()
    local dibs = load(); adopt(dibs)
    dibs.GetDB().preDibs.requests = { { requestId = "preserved" } }
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ sandbox = false }, nil)
    assert_false(changed)
    assert_equal("INVALID_MODULE_POLICY", reason)
    changed, reason = dibs.OperationalPolicy.ChangeModules({ preDibs = false }, nil)
    assert_true(changed, tostring(reason))
    assert_equal("preserved", dibs.GetDB().preDibs.requests[1].requestId)
    changed, reason = dibs.OperationalPolicy.ChangeModules({ preDibs = true }, nil)
    assert_true(changed, tostring(reason))
    assert_true(dibs.OperationalPolicy.IsModuleEnabled("preDibs"))
    assert_equal("preserved", dibs.GetDB().preDibs.requests[1].requestId)
  end)

  it("hides disabled navigation entries and empty groups while keeping Modules available", function()
    local dibs = load(); adopt(dibs)
    local changed, reason = dibs.OperationalPolicy.ChangeModules({
      requests = false, preDibs = false, announcements = false,
      rclootcouncil = false, historicalReconciliation = false, lootEligibility = false,
    }, nil)
    assert_true(changed, tostring(reason))
    local navigation = dibs.OfficerUI.GetNavigationTree()
    assert_false(hasNavigationEntry(navigation, "disputes"))
    assert_false(hasNavigationEntry(navigation, "preDibs"))
    assert_false(hasNavigationEntry(navigation, "announcements"))
    assert_false(hasNavigationEntry(navigation, "integration"))
    assert_false(hasNavigationEntry(navigation, "eligibility"))
    assert_false(hasNavigationSection(navigation, "INTEGRATIONS"))
    assert_true(hasNavigationEntry(navigation, "overview"))
    assert_true(hasNavigationEntry(navigation, "history"))
    assert_true(hasNavigationEntry(navigation, "modules"))
  end)

  it("renders a disabled state for a stale Officer route instead of a functional workflow", function()
    local dibs = load(); adopt(dibs)
    local frame = dibs.OfficerUI.CreateWindow("disputes")
    assert_true(containsText(frame.contentHost, "Requests"))
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ requests = false }, nil)
    assert_true(changed, tostring(reason))
    frame:Refresh()
    assert_true(containsText(frame.contentHost, "Requests is disabled by the Guild Master."))
    assert_nil(findButton(frame.contentHost, "Resolve"))
    local request, requestReason = dibs.Disputes.CreateReport({}, nil)
    assert_nil(request)
    assert_equal("MODULE_DISABLED_REQUESTS", requestReason)
  end)

  it("rejects a disabled slash route and restores it with preserved data", function()
    local dibs = load(); adopt(dibs)
    dibs.GetDB().preDibs.requests = { { requestId = "slash-preserved" } }
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ preDibs = false }, nil)
    assert_true(changed, tostring(reason))
    local messages = {}
    local originalMessage = dibs.Message
    dibs.Message = function(message) messages[#messages + 1] = tostring(message) end
    dibs.HandleSlashCommand("pre 123")
    dibs.Message = originalMessage
    assert_equal("Pre-Dibs is disabled by the Guild Master.", messages[1])
    changed, reason = dibs.OperationalPolicy.ChangeModules({ preDibs = true }, nil)
    assert_true(changed, tostring(reason))
    assert_true(hasNavigationEntry(dibs.PlayerUI.GetNavigation(), "requests"))
    assert_equal("slash-preserved", dibs.GetDB().preDibs.requests[1].requestId)
  end)
end)
