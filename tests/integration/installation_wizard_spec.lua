local loader = require("helpers.load_addon")

local roster = { "Tester-Realm", "Officer-Realm", "Member-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, guildLeader, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = guildLeader, guildMembers = roster, guildRankIndices = ranks,
  } }))
end

describe("Installation readiness projection", function()
  it("resolves the active ledger once for the legacy ledger and Pre-Dibs status checks", function()
    local dibs = load("Tester-Realm", true)
    local resolvedGuildDB = dibs.GetDB()
    local originalActiveLedger = dibs.Ledger.GetActiveLedgerId
    local originalHasHistory = dibs.Ledger.HasNonAllocationTransactions
    local originalHistoryCount = dibs.PreDibs.GetHistoryCount
    local originalSyncBehind = dibs.Sync.IsSyncBehind
    local originalSyncCompatibility = dibs.Sync.CanEnforceV2
    local originalBaselineSummary = dibs.HistoricalBaseline.GetInstallationSummary
    local activeReads, ledgerTarget, predibsTarget, activeDatabase, historyDatabase, baselineDatabase = 0, nil, nil, nil, nil, nil
    local syncBehindDatabase, syncCompatibilityDatabase
    dibs.Ledger.GetActiveLedgerId = function(db)
      activeReads = activeReads + 1
      activeDatabase = db
      return "guild-primary"
    end
    dibs.Ledger.HasNonAllocationTransactions = function(targetLedgerId, db)
      ledgerTarget = targetLedgerId
      historyDatabase = db
      return false
    end
    dibs.PreDibs.GetHistoryCount = function(targetLedgerId)
      predibsTarget = targetLedgerId
      return 0
    end
    dibs.HistoricalBaseline.GetInstallationSummary = function(db)
      baselineDatabase = db
      return originalBaselineSummary(db)
    end
    dibs.Sync.IsSyncBehind = function(db) syncBehindDatabase = db; return false end
    dibs.Sync.CanEnforceV2 = function(_, db) syncCompatibilityDatabase = db; return true end

    local status = dibs.Installation.GetStatus()

    dibs.Ledger.GetActiveLedgerId = originalActiveLedger
    dibs.Ledger.HasNonAllocationTransactions = originalHasHistory
    dibs.PreDibs.GetHistoryCount = originalHistoryCount
    dibs.Sync.IsSyncBehind = originalSyncBehind
    dibs.Sync.CanEnforceV2 = originalSyncCompatibility
    dibs.HistoricalBaseline.GetInstallationSummary = originalBaselineSummary
    assert_equal(1, activeReads)
    assert_equal(resolvedGuildDB, activeDatabase)
    assert_equal(resolvedGuildDB, historyDatabase)
    assert_equal(resolvedGuildDB, baselineDatabase)
    assert_equal(resolvedGuildDB, syncBehindDatabase)
    assert_equal(resolvedGuildDB, syncCompatibilityDatabase)
    assert_equal("guild-primary", ledgerTarget)
    assert_equal(ledgerTarget, predibsTarget)
    assert_equal("NOT_INITIALIZED", status.state)
  end)

  it("builds installation status without copying governance or authority history", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local getState = dibs.Governance.GetState
    local getAuthorityState = dibs.Governance.GetAuthorityState
    local isV2Enforced = dibs.Governance.IsV2Enforced
    dibs.Governance.GetState = function() error("full governance state copy should not be needed") end
    dibs.Governance.GetAuthorityState = function() error("full authority state copy should not be needed") end
    dibs.Governance.IsV2Enforced = function() error("compact status should provide protocol state") end

    local ok, status = pcall(dibs.Installation.GetStatus)
    dibs.Governance.GetState = getState
    dibs.Governance.GetAuthorityState = getAuthorityState
    dibs.Governance.IsV2Enforced = isV2Enforced
    assert_true(ok, tostring(status))
    assert_equal("READY_TO_INITIALIZE", status.state)
    assert_false(status.protocol.active)
  end)

  it("builds the compact historical baseline summary from a supplied guild DB", function()
    local dibs = load("Tester-Realm", true)
    local resolvedGuildDB = dibs.GetDB()
    local getDB = dibs.GetDB
    dibs.GetDB = function() error("summary should reuse the supplied guild DB") end

    local ok, summary = pcall(dibs.HistoricalBaseline.GetInstallationSummary, resolvedGuildDB)

    dibs.GetDB = getDB
    assert_true(ok, tostring(summary))
    assert_equal(0, summary.evidenceCount)
    assert_equal(false, summary.baselinePresent)
  end)

  it("counts Pre-Dibs history without migrating the legacy SavedVariables store", function()
    local dibs = load("Tester-Realm", true)
    local root = dibs.GetDB().preDibs
    root.ledgerStorageVersion = nil
    root.ledgers = {}
    root.requests = { { requestId = "legacy-predib" } }

    assert_equal(1, dibs.PreDibs.GetHistoryCount())
    assert_nil(root.ledgerStorageVersion)
    assert_equal(1, #dibs.PreDibs.GetHistory())
    assert_equal(1, dibs.PreDibs.GetHistoryCount())
  end)

  it("reads history count from the resolved guild DB without re-running DB resolution", function()
    local dibs = load("Tester-Realm", true)
    local getDB = dibs.GetDB
    dibs.GetDB = function() error("read-only history count should use the resolved guild DB") end
    local ok, count = pcall(dibs.PreDibs.GetHistoryCount, "guild-primary")
    dibs.GetDB = getDB
    assert_true(ok, tostring(count))
    assert_equal(0, count)
  end)

  it("reports NOT_INITIALIZED before governance adoption and hides the actor from initializing", function()
    local dibs = load("Tester-Realm", true)
    local status = dibs.Installation.GetStatus()
    assert_equal("NOT_INITIALIZED", status.state)
    assert_equal("CLEAN", status.installType)
    assert_true(status.actor.isGM)

    local member = load("Member-Realm", false)
    local memberStatus = member.Installation.GetStatus()
    assert_equal("NOT_INITIALIZED", memberStatus.state)
    assert_false(memberStatus.actor.isGM)
  end)

  it("reports READY_TO_INITIALIZE on a clean guild after governance adoption", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local status = dibs.Installation.GetStatus()
    assert_equal("READY_TO_INITIALIZE", status.state)
    assert_equal("CLEAN", status.installType)
    assert_equal(0, status.legacy.evidenceCount)
    assert_false(status.legacy.reconciliationRequired)
  end)

  it("reports RECONCILIATION_REQUIRED when real legacy ledger data has not been scanned yet", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local season = dibs.Seasons.Create("Legacy Season")
    assert_not_nil(season)
    assert_not_nil(dibs.Ledger.Grant("Member-Realm", 1, "legacy grant", "test", season.id))
    local status = dibs.Installation.GetStatus()
    assert_equal("RECONCILIATION_REQUIRED", status.state)
    assert_equal("UPGRADE", status.installType)
    assert_true(status.legacy.hasUncollectedEvidence)
  end)
end)

describe("Installation.Initialize orchestrator", function()
  it("rejects a non-GM without mutating anything", function()
    local dibs = load("Member-Realm", false)
    local result = dibs.Installation.Initialize(nil)
    assert_false(result.ok)
    assert_equal("GUILD_MASTER_REQUIRED", result.reasonCode)
    assert_equal("POLICY_UNINITIALIZED", dibs.Governance.GetState().status)
  end)

  it("initializes a clean guild in one call and is idempotent", function()
    local dibs = load("Tester-Realm", true)
    local result = dibs.Installation.Initialize(nil)
    assert_true(result.ok, tostring(result.reasonCode))
    assert_equal("READY", result.status.state)
    assert_true(dibs.Governance.IsV2Enforced())
    assert_equal("GENESIS", result.status.baseline.type)

    local governanceRevisionAfterFirst = dibs.Governance.GetState().revision
    local second = dibs.Installation.Initialize(nil)
    assert_true(second.ok)
    assert_equal("ALREADY_INITIALIZED", second.reasonCode)
    assert_equal(governanceRevisionAfterFirst, dibs.Governance.GetState().revision)
  end)

  it("lets a verified guild master review legacy evidence", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = {
        playerName = "GameMaster-Realm", guildLeader = true,
        guildMembers = { "GameMaster-Realm" }, guildRankIndices = { [1] = 0 },
      },
    })
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test authority" }))
    local season = dibs.Seasons.Create("Legacy Test")
    assert_not_nil(season)
    assert_not_nil(dibs.Ledger.Grant("GameMaster-Realm", 1, "legacy grant", "test", season.id))

    local blocked = dibs.Installation.Initialize(nil)
    assert_false(blocked.ok)
    assert_equal("LEGACY_RECONCILIATION_REQUIRED", blocked.reasonCode)
    local evidence = dibs.HistoricalBaseline.GetEvidence()
    assert_true(#evidence > 0)
    local recorded, reason = dibs.HistoricalBaseline.RecordDecision(
      nil, evidence[1].evidenceId, "INCLUDE", { reason = "reviewed in test mode" })
    assert_not_nil(recorded, tostring(reason))
  end)

  it("blocks one-click initialization when legacy evidence has open findings, and resumes after reconciliation", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local season = dibs.Seasons.Create("Legacy Season")
    assert_not_nil(dibs.Ledger.Grant("Member-Realm", 1, "legacy grant", "test", season.id))

    local blocked = dibs.Installation.Initialize(nil)
    assert_false(blocked.ok)
    assert_equal("baseline", blocked.stage)
    assert_equal("LEGACY_RECONCILIATION_REQUIRED", blocked.reasonCode)
    assert_true(blocked.status.legacy.evidenceCount > 0)
    assert_nil(dibs.HistoricalBaseline.GetBaseline())

    for _, evidence in ipairs(dibs.HistoricalBaseline.GetEvidence()) do
      assert_not_nil(dibs.HistoricalBaseline.RecordDecision(nil, evidence.evidenceId, "INCLUDE", { reason = "reviewed" }))
    end

    local resumed = dibs.Installation.Initialize(nil)
    assert_true(resumed.ok, tostring(resumed.reasonCode))
    assert_equal("READY", resumed.status.state)
    assert_equal("RECONCILED", resumed.status.baseline.type)
  end)

  it("does not silently acknowledge incomplete evidence sources", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local added = dibs.HistoricalBaseline.CollectEvidence(nil, {
      sourceId = "manual-import", sourceClient = "Tester-Realm", sourceType = "LEDGER_TRANSACTION", complete = false,
    }, { { originalId = "tx-1", record = { transactionId = "tx-1", playerName = "Member-Realm", amount = 1, seasonId = "S1", actionType = "DIB_GRANTED" } } })
    assert_not_nil(added)
    assert_not_nil(dibs.HistoricalBaseline.RecordDecision(nil, added[1], "INCLUDE", { reason = "reviewed" }))

    local blocked = dibs.Installation.Initialize(nil)
    assert_false(blocked.ok)
    assert_equal("baseline", blocked.stage)
    assert_equal("INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED", blocked.reasonCode)
    assert_nil(dibs.HistoricalBaseline.GetBaseline())

    local resumed = dibs.Installation.Initialize(nil, { acknowledgeIncompleteEvidence = true })
    assert_true(resumed.ok, tostring(resumed.reasonCode))
    assert_equal("READY", resumed.status.state)
  end)

  it("resumes from the authority stage after a partial reload-simulated failure", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    assert_not_nil(dibs.HistoricalBaseline.FinalizeBaseline(nil))
    local status = dibs.Installation.GetStatus()
    assert_equal("READY_TO_INITIALIZE", status.state)
    assert_false(dibs.Governance.IsV2Enforced())

    local result = dibs.Installation.Initialize(nil)
    assert_true(result.ok, tostring(result.reasonCode))
    assert_equal("READY", result.status.state)
  end)
end)

describe("P0 regression: Governance.ActivateV2 never silently acknowledges incomplete evidence", function()
  it("stops on incomplete evidence sources unless the caller explicitly acknowledges them", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local added = dibs.HistoricalBaseline.CollectEvidence(nil, {
      sourceId = "manual-import", sourceClient = "Tester-Realm", sourceType = "LEDGER_TRANSACTION", complete = false,
    }, { { originalId = "tx-1", record = { transactionId = "tx-1", playerName = "Member-Realm", amount = 1, seasonId = "S1", actionType = "DIB_GRANTED" } } })
    assert_not_nil(dibs.HistoricalBaseline.RecordDecision(nil, added[1], "INCLUDE", { reason = "reviewed" }))

    local blocked, blockedReason = dibs.Governance.ActivateV2(nil)
    assert_false(blocked)
    assert_equal("INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED", blockedReason)
    assert_nil(dibs.HistoricalBaseline.GetBaseline())
    assert_false(dibs.Governance.IsV2Enforced())

    local enabled, enableReason = dibs.Governance.ActivateV2(nil, { acknowledgeIncompleteEvidence = true })
    assert_true(enabled, tostring(enableReason))
  end)

  it("still allows the deterministic empty/genesis baseline for a truly clean guild", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local enabled, reason = dibs.Governance.ActivateV2(nil)
    assert_true(enabled, tostring(reason))
    assert_true(dibs.Governance.IsV2Enforced())
  end)
end)

describe("Guild Configuration next steps after activation", function()
  local function findLatestWidget(predicate)
    for index = #(_G.__dibsAceWidgets or {}), 1, -1 do
      local widget = _G.__dibsAceWidgets[index]
      if predicate(widget) then return widget end
    end
  end

  local function clickLatestButton(text)
    local widget = findLatestWidget(function(candidate) return candidate.kind == "Button" and candidate.text == text end)
    assert_not_nil(widget, "Button not found: " .. text)
    widget.callbacks.OnClick(widget, "OnClick")
    return widget
  end

  it("links a ready guild to Raid Readiness without changing its route", function()
    local dibs = load("Tester-Realm", true)
    local result = dibs.Installation.Initialize(nil)
    assert_true(result.ok, tostring(result.reasonCode))
    assert_equal("READY", result.status.state)
    local frame = dibs.OfficerUI.CreateWindow("installation")
    frame:ActivateRoute("installation")
    local navigationByLabel = {}
    for _, entry in ipairs(dibs.OfficerUI.GetNavigationTree()) do
      navigationByLabel[entry.text] = entry.value
    end
    assert_equal("wizard", navigationByLabel["Guided Setup"])
    assert_equal("setup", navigationByLabel["Raid Readiness"])
    assert_equal("installation", navigationByLabel["Guild Ledgers"])
    assert_nil(navigationByLabel["Setup Assistant"])
    assert_nil(navigationByLabel["Guild Setup"])
    assert_not_nil(findLatestWidget(function(widget) return widget.kind == "Button" and widget.text == "Open Raid Readiness" end))

    clickLatestButton("Open Raid Readiness")
    assert_equal("setup", frame.activeTab)
    frame:ActivateRoute(navigationByLabel["Guided Setup"])
    assert_equal("wizard", frame.activeTab)
  end)

  it("opens the existing installation route from the renamed Guild Configuration link", function()
    local dibs = load("Tester-Realm", true)
    local frame = dibs.OfficerUI.CreateWindow("sync")
    frame:ActivateRoute("sync")
    clickLatestButton("Open Guild Ledgers")
    assert_equal("installation", frame.activeTab)
  end)

  it("reuses the installation ledger snapshot for the active-ledger selector", function()
    local dibs = load("Tester-Realm", true)
    local frame = dibs.OfficerUI.CreateWindow("overview")
    local originalGetLedgers = dibs.MultiLedger.GetLedgers
    local originalGetDropdownValues = dibs.AceGUI.GetLedgerDropdownValues
    local ledgerReads, dropdownArgs, dropdownValues = 0, nil, nil
    dibs.MultiLedger.GetLedgers = function(...)
      ledgerReads = ledgerReads + 1
      return originalGetLedgers(...)
    end
    dibs.AceGUI.GetLedgerDropdownValues = function(ledgers, activeId, viewId)
      dropdownArgs = { ledgers, activeId, viewId }
      dropdownValues = originalGetDropdownValues(ledgers, activeId, viewId)
      return dropdownValues
    end

    frame:ActivateRoute("installation")

    dibs.MultiLedger.GetLedgers = originalGetLedgers
    dibs.AceGUI.GetLedgerDropdownValues = originalGetDropdownValues
    assert_equal(1, ledgerReads, "installation should read the ledger catalog once")
    assert_not_nil(dropdownArgs)
    assert_equal("table", type(dropdownArgs[1]), "selector should receive the rendered ledger snapshot")
    assert_equal("guild-primary", dropdownArgs[2])
    assert_not_nil(dropdownValues["guild-primary"], "selector should retain the default ledger option")
    local selector = findLatestWidget(function(widget)
      return widget.kind == "Dropdown" and widget.label == "Ledger to activate"
    end)
    assert_not_nil(selector, "active-ledger selector should remain populated")
  end)

  it("reuses the route database for Installation status and ledger reads", function()
    local dibs = load("Tester-Realm", true)
    local frame = dibs.OfficerUI.CreateWindow("overview")
    local originalSetShellStatus = dibs.AceGUI.SetShellStatus
    local originalGetStatus = dibs.Installation.GetStatus
    local originalGetLedgers = dibs.MultiLedger.GetLedgers
    local originalGetActiveLedgerId = dibs.MultiLedger.GetActiveLedgerId
    local originalGetGuildLedgerStatus = dibs.MultiLedger.GetGuildLedgerStatus
    local routeDB = dibs.GetDB()
    local statusDB, catalogDB, activeDB, guildStatusDB
    dibs.AceGUI.SetShellStatus = function(shell, text)
      local ok = originalSetShellStatus(shell, text)
      return ok, routeDB
    end
    dibs.Installation.GetStatus = function(actor, dbOverride)
      statusDB = dbOverride
      return originalGetStatus(actor, dbOverride)
    end
    dibs.MultiLedger.GetLedgers = function(options, dbOverride)
      catalogDB = dbOverride
      return originalGetLedgers(options, dbOverride)
    end
    dibs.MultiLedger.GetActiveLedgerId = function(dbOverride)
      activeDB = dbOverride
      return originalGetActiveLedgerId(dbOverride)
    end
    dibs.MultiLedger.GetGuildLedgerStatus = function(dbOverride)
      guildStatusDB = dbOverride
      return originalGetGuildLedgerStatus(dbOverride)
    end

    frame:ActivateRoute("installation")

    dibs.AceGUI.SetShellStatus = originalSetShellStatus
    dibs.Installation.GetStatus = originalGetStatus
    dibs.MultiLedger.GetLedgers = originalGetLedgers
    dibs.MultiLedger.GetActiveLedgerId = originalGetActiveLedgerId
    dibs.MultiLedger.GetGuildLedgerStatus = originalGetGuildLedgerStatus
    assert_equal(routeDB, statusDB, "Installation status should use the route's resolved DB")
    assert_equal(routeDB, catalogDB, "ledger catalog should use the route's resolved DB")
    assert_equal(routeDB, activeDB, "active ledger lookup should use the route's resolved DB")
    assert_equal(routeDB, guildStatusDB, "guild ledger status should use the route's resolved DB")
  end)

  it("archives and permanently deletes a non-default ledger through Guild Configuration", function()
    local dibs = load("Tester-Realm", true)
    local proposed = dibs.MultiLedger.ProposeLedger(nil, "Retired Raid")
    assert_true(proposed.ok)
    assert_true(dibs.MultiLedger.ApproveLedger(nil, proposed.ledgerId).ok)
    local originalSend = dibs.SyncV2.Send
    dibs.SyncV2.Send = function() return true, "TEST_SENT" end

    dibs.OfficerUI.CreateWindow("installation")
    clickLatestButton("Archive")
    clickLatestButton("Confirm archive")
    assert_equal("ARCHIVED", dibs.GetDB().ledgers[proposed.ledgerId].status)

    clickLatestButton("Delete permanently")
    clickLatestButton("Confirm permanent deletion")
    dibs.SyncV2.Send = originalSend
    assert_nil(dibs.GetDB().ledgers[proposed.ledgerId])
    assert_not_nil(dibs.GetDB().ledgerDeletionTombstones[proposed.ledgerId])
  end)

  it("lists the default ledger and proposes a ledger from Guild Ledgers", function()
    local dibs = load("Tester-Realm", true)
    local frame = dibs.OfficerUI.CreateWindow("installation")
    frame:ActivateRoute("installation")
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Label" and type(widget.text) == "string" and widget.text:find("Default]", 1, true) ~= nil
    end), "Default ledger not listed")

    frame.newLedgerProposedName = "Split Run"
    clickLatestButton("Propose Ledger")
    local proposedId
    for id, ledger in pairs(dibs.GetDB().ledgers) do
      if ledger.name == "Split Run" then proposedId = id end
    end
    assert_not_nil(proposedId, "Proposed ledger not stored")
    assert_equal("PROPOSED", dibs.GetDB().ledgers[proposedId].status)
    clickLatestButton("Approve")
    assert_equal("APPROVED", dibs.GetDB().ledgers[proposedId].status)
  end)

  local function selectDropdown(label, value)
    local widget = findLatestWidget(function(candidate)
      return candidate.kind == "Dropdown" and candidate.label == label
    end)
    assert_not_nil(widget, "Dropdown not found: " .. label)
    widget.callbacks.OnValueChanged(widget, "OnValueChanged", value)
  end

  local function prepareActivation()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "activation test" }))
    local proposal = dibs.MultiLedger.ProposeLedger(nil, "Raid Two")
    assert_true(proposal.ok)
    assert_true(dibs.MultiLedger.ApproveLedger(nil, proposal.ledgerId).ok)
    local frame = dibs.OfficerUI.CreateWindow("overview")
    local sends = {}
    dibs.Sync.Send = function(message, channel)
      sends[#sends + 1] = { message = message, channel = channel }
      return true, "TEST_SENT"
    end
    return dibs, frame, proposal.ledgerId, sends
  end

  it("keeps dashboard selection read-only and activates only after management confirmation", function()
    local dibs, frame, target, sends = prepareActivation()
    selectDropdown("View ledger", target)
    assert_equal(target, dibs.MultiLedger.GetViewLedgerId())
    assert_equal("guild-primary", dibs.MultiLedger.GetActiveLedgerId())
    assert_nil(dibs.OperationalPolicy.GetActiveLedgerId())
    assert_equal(0, #sends)

    clickLatestButton("Manage ledgers")
    assert_equal("installation", frame.activeTab)
    selectDropdown("Ledger to activate", target)
    assert_equal("guild-primary", dibs.MultiLedger.GetActiveLedgerId())
    assert_equal(0, #sends)
    clickLatestButton("Activate for guild...")
    assert_equal("guild-primary", dibs.MultiLedger.GetActiveLedgerId())
    assert_equal(0, #sends)
    clickLatestButton("Cancel activation")
    assert_nil(frame.ledgerActivationConfirmId)
    assert_nil(dibs.OperationalPolicy.GetActiveLedgerId())

    clickLatestButton("Activate for guild...")
    clickLatestButton("Confirm activation and guild sync")
    assert_equal(target, dibs.MultiLedger.GetActiveLedgerId())
    assert_equal(target, dibs.OperationalPolicy.GetActiveLedgerId())
    assert_equal(1, #sends)
    assert_equal("GUILD", sends[1].channel)
    assert_equal("OPERATIONAL_POLICY", sends[1].message.entityType)
    assert_nil(frame.ledgerActivationConfirmId)
  end)

  it("shows the viewed ledger contents on the dashboard without activating it", function()
    local dibs, _, target, sends = prepareActivation()
    local requestedLedgers = {}
    local originalGetTransactions = dibs.Ledger.GetTransactions
    dibs.Ledger.GetTransactions = function(seasonId, player, ledgerId)
      requestedLedgers[#requestedLedgers + 1] = ledgerId or "active"
      return originalGetTransactions(seasonId, player, ledgerId)
    end
    selectDropdown("View ledger", target)
    local projection = dibs.OfficerUI.GetDashboardProjection()
    dibs.Ledger.GetTransactions = originalGetTransactions
    assert_equal(target, projection.viewLedger.id)
    assert_true(projection.viewLedger.readOnly)
    assert_equal(target, requestedLedgers[#requestedLedgers])
    assert_not_nil(findLatestWidget(function(widget)
      return type(widget.text) == "string" and widget.text:find("Read-only:", 1, true) ~= nil
    end), "Read-only badge not shown")
    assert_equal("guild-primary", dibs.MultiLedger.GetActiveLedgerId())
    assert_equal(0, #sends)
  end)

  it("keeps the dashboard controls together and the read-only warning on a separate row", function()
    local dibs, _, target, sends = prepareActivation()
    local function assertControlRow()
      local dropdown = findLatestWidget(function(widget)
        return widget.kind == "Dropdown" and widget.label == "View ledger"
      end)
      local manage = findLatestWidget(function(widget)
        return widget.kind == "Button" and widget.text == "Manage ledgers"
      end)
      assert_not_nil(dropdown)
      assert_not_nil(manage)
      assert_equal(dropdown.parent, manage.parent)
      assert_equal(3, #dropdown.parent.children, "Only season, selector and management belong in the control row")
      assert_equal(dropdown, dropdown.parent.children[2])
      assert_equal(manage, dropdown.parent.children[3])
      return dropdown.parent
    end
    assertControlRow()
    selectDropdown("View ledger", target)
    local controlRow = assertControlRow()
    local warning = findLatestWidget(function(widget)
      return type(widget.text) == "string" and widget.text:find("Read-only:", 1, true) ~= nil
    end)
    assert_not_nil(warning)
    assert_equal(controlRow.parent, warning.parent, "Warning must be outside the controls' Flow layout")
    selectDropdown("View ledger", "guild-primary")
    assertControlRow()
    assert_equal("guild-primary", dibs.MultiLedger.GetActiveLedgerId())
    assert_equal(0, #sends)
  end)

  it("invalidates activation confirmation when the selection or page changes", function()
    local dibs, frame, target, sends = prepareActivation()
    frame:ActivateRoute("installation")
    selectDropdown("Ledger to activate", target)
    clickLatestButton("Activate for guild...")
    selectDropdown("Ledger to activate", "guild-primary")
    assert_nil(frame.ledgerActivationConfirmId)
    clickLatestButton("Activate for guild...")
    frame:ActivateRoute("overview")
    assert_nil(frame.ledgerActivationConfirmId)
    assert_equal("guild-primary", dibs.MultiLedger.GetActiveLedgerId())
    assert_equal(0, #sends)
  end)

  it("rechecks authority, combat and the current ledger at confirmation", function()
    for _, blockedBy in ipairs({ "authority", "combat", "stale" }) do
      local dibs, frame, target, sends = prepareActivation()
      frame:ActivateRoute("installation")
      selectDropdown("Ledger to activate", target)
      clickLatestButton("Activate for guild...")
      local originalCombat = _G.InCombatLockdown
      if blockedBy == "authority" then
        dibs.MultiLedger.CanSetGuildActiveLedger = function() return false end
      elseif blockedBy == "combat" then
        _G.InCombatLockdown = function() return true end
      else
        frame.ledgerActivationPreviousId = "outdated-ledger"
      end
      clickLatestButton("Confirm activation and guild sync")
      _G.InCombatLockdown = originalCombat
      assert_nil(dibs.OperationalPolicy.GetActiveLedgerId(), blockedBy)
      assert_equal("guild-primary", dibs.MultiLedger.GetActiveLedgerId(), blockedBy)
      assert_equal(0, #sends, blockedBy)
      assert_nil(frame.ledgerActivationConfirmId)
    end
  end)

  it("shows failed guild sync instead of claiming all members are synchronized", function()
    local dibs, frame, target = prepareActivation()
    frame:ActivateRoute("installation")
    selectDropdown("Ledger to activate", target)
    dibs.Sync.Send = function() return false, "SYNC_UNAVAILABLE" end
    local statusText
    frame.SetStatus = function(_, text) statusText = text end
    clickLatestButton("Activate for guild...")
    clickLatestButton("Confirm activation and guild sync")
    assert_equal(target, dibs.MultiLedger.GetActiveLedgerId())
    assert_not_nil(statusText:find("guild sync could not be sent: SYNC_UNAVAILABLE", 1, true))
  end)
end)
