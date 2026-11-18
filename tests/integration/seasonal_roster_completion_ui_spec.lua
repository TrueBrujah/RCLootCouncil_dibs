local loader = require("helpers.load_addon")

local function load(locale)
  local _, dibs = loader.load({ withAce3 = true, wow = { locale = locale or "enUS", guildLeader = true,
    guildMembers = { "Tester-Realm", "Player-Realm" }, guildRankIndices = { [1] = 0, [2] = 3 } } })
  -- These service-boundary UI cases exercise an already configured guild.
  -- Fresh/partial route gating has its own real-state navigation suites.
  dibs.Wizard.GetNavigationAccess = function()
    return { foundationReady = true, preservedHistory = true,
      routes = { wizard = true, seasonalRoster = true, vault = true, history = true },
      dependencies = { seasonConfigured = true, rosterConfigured = true, ranksPublished = true, ledgerReady = true } }
  end
  return dibs
end

-- Capture the shared adapter's controls, preserving callback semantics without
-- coupling service-boundary checks to native frame geometry.
local function capture(dibs)
  local controls = { buttons = {}, edits = {}, checks = {}, labels = {}, tables = {} }
  dibs.AceGUI.AddButton = function(_, _, text, callback)
    controls.buttons[text] = callback; return {}
  end
  dibs.AceGUI.AddEditBox = function(_, _, text, callback)
    controls.edits[text] = callback; return { SetText = function() end }
  end
  dibs.AceGUI.AddCheckBox = function(_, _, text, value, callback)
    controls.checks[text] = callback; return {}
  end
  dibs.AceGUI.AddLabel = function(_, _, text) controls.labels[#controls.labels + 1] = text end
  dibs.AceGUI.AddHeader = function() end
  dibs.AceGUI.AddInlineGroup = function() return {} end
  dibs.AceGUI.AddTable = function(_, _, columns, rows, height, actions, options)
    controls.tables[#controls.tables + 1] = { rows = rows, columns = columns, options = options }
  end
  dibs.AceGUI.AddPaginationFooter = function(_, _, options)
    controls.pager = options; return { UpdateState = function() end }
  end
  dibs.AceGUI.SetValue = function() end
  dibs.Permissions.Evaluate = function() return { allowed = true } end
  return controls
end

local function frame()
  return { Refresh = function(self) self.refreshes = (self.refreshes or 0) + 1 end }
end

describe("Seasonal roster completion UI", function()
  it("requires reason and explicit preview-bound confirmation before activation", function()
    local dibs = load()
    local controls, view, calls = capture(dibs), frame(), 0
    local season = { seasonId = "season-ui", revision = 4 }
    local preview = { previewId = "preview-1", ready = true }
    dibs.SeasonalRoster.ActivateSeason = function(id, previewId, revision, operation, reason, actor, confirmed)
      calls = calls + 1
      assert_equal(season.seasonId, id); assert_equal("preview-1", previewId); assert_equal(4, revision)
      assert_true(#operation > 0); assert_equal("Reviewed cohort", reason); assert_true(confirmed)
      return { ok = true }
    end
    local function render() dibs.OfficerUI.RenderSeasonCommit({}, {}, view, season, preview, false) end
    render()
    controls.buttons[dibs.L.SEASONAL_ROSTER_ACTIVATE]()
    assert_equal(0, calls)
    assert_equal(dibs.OfficerUI.SeasonalText("CONFIRMATION_REQUIRED"), view.seasonalRosterMessage)
    render()
    controls.checks[dibs.L.SEASONAL_ROSTER_CONFIRM_ACTIVATE](true)
    controls.buttons[dibs.L.SEASONAL_ROSTER_ACTIVATE]()
    assert_equal(0, calls)
    assert_equal(dibs.OfficerUI.SeasonalText("REASON_REQUIRED"), view.seasonalRosterMessage)
    render()
    controls.edits[dibs.L.SEASONAL_ROSTER_ADMIN_REASON]("Reviewed cohort")
    controls.checks[dibs.L.SEASONAL_ROSTER_CONFIRM_ACTIVATE](true)
    controls.buttons[dibs.L.SEASONAL_ROSTER_ACTIVATE]()
    assert_equal(1, calls)
    assert_false(view.seasonActivateConfirmed)
    assert_equal(dibs.L.SEASONAL_ROSTER_ACTIVATED, view.seasonalRosterMessage)
  end)

  it("invalidates confirmation when preview or reason changes and hides unauthorized commits", function()
    local dibs = load()
    local controls, view = capture(dibs), frame()
    local season = { seasonId = "season-ui", revision = 1 }
    dibs.OfficerUI.RenderSeasonCommit({}, {}, view, season, { previewId = "old", ready = true }, false)
    controls.checks[dibs.L.SEASONAL_ROSTER_CONFIRM_ACTIVATE](true)
    dibs.OfficerUI.RenderSeasonCommit({}, {}, view, season, { previewId = "new", ready = true }, false)
    assert_false(view.seasonActivateConfirmed)
    controls.checks[dibs.L.SEASONAL_ROSTER_CONFIRM_ACTIVATE](true)
    controls.edits[dibs.L.SEASONAL_ROSTER_ADMIN_REASON]("changed reason")
    assert_false(view.seasonActivateConfirmed)
    controls.buttons = {}
    dibs.Permissions.Evaluate = function() return { allowed = false } end
    dibs.OfficerUI.RenderSeasonCommit({}, {}, view, season, { previewId = "new", ready = true }, false)
    assert_nil(controls.buttons[dibs.L.SEASONAL_ROSTER_ACTIVATE])
  end)

  it("sends reconciliation dependencies, preserves conflict messages and never retries a stale preview", function()
    local dibs = load("frFR")
    local controls, view, calls = capture(dibs), frame(), 0
    local preview = { seasonId = "season-ui", previewId = "drift", ready = true, seasonRevision = 5,
      rosterRevision = 9, sourceLedgerRevision = "ledger-7" }
    dibs.SeasonalRoster.ApplySeasonReconciliation = function(actor, id, revisions, operation, reason, confirmed)
      calls = calls + 1
      assert_equal("drift", id); assert_equal(5, revisions.seasonRevision); assert_equal(9, revisions.rosterRevision)
      assert_equal("ledger-7", revisions.sourceLedgerRevision); assert_equal("season-ui", revisions.seasonId)
      assert_equal("Rang vérifié", reason); assert_true(confirmed)
      return { ok = false, code = "STALE_REVISION" }
    end
    dibs.OfficerUI.RenderSeasonCommit({}, {}, view, { seasonId = "season-ui", revision = 5 }, preview, true)
    controls.edits[dibs.L.SEASONAL_ROSTER_ADMIN_REASON]("Rang vérifié")
    controls.checks[dibs.L.SEASONAL_ROSTER_CONFIRM_RECONCILE](true)
    controls.buttons[dibs.L.SEASONAL_ROSTER_APPLY_RECONCILE]()
    assert_equal(1, calls); assert_nil(view.seasonalRosterReconciliationPreview)
    assert_equal(dibs.L.SEASONAL_ROSTER_CODE_STALE_REVISION, view.seasonalRosterMessage)
    controls.buttons[dibs.L.SEASONAL_ROSTER_APPLY_RECONCILE]()
    assert_equal(1, calls)
  end)

  it("bounds reconciliation rows, reports affected people and blocks unready application", function()
    local dibs = load()
    local controls, view = capture(dibs), frame()
    local preview = { seasonId = "season-ui", previewId = "drift", ready = false, rows = {},
      blockers = { { code = "GUILD_ADMIN_REQUIRED" } } }
    for index = 1, 61 do preview.rows[index] = { character = "Player" .. index, assignedAllocation = 3, allocation = 5, delta = 2 } end
    dibs.SeasonalRoster.PreviewSeasonReconciliation = function() return preview end
    view.seasonalRosterReconciliationPreview = preview
    dibs.OfficerUI.RenderSeasonReconciliation({}, {}, view, { seasonId = "season-ui", revision = 5 })
    assert_equal(20, #controls.tables[1].rows)
    assert_not_nil(controls.pager)
    assert_nil(controls.buttons[dibs.L.SEASONAL_ROSTER_APPLY_RECONCILE])
    assert_equal(string.format(dibs.L.SEASONAL_ROSTER_RECONCILE_COUNTS, 61, 61), controls.labels[1])
    controls.pager.onNext(); assert_equal(2, view.seasonalRosterReconciliationPage)
  end)

  it("delegates preserved history reads and exposes no write action while disabled", function()
    local dibs = load()
    local controls = capture(dibs)
    dibs.SeasonalRoster.GetPreservedHistory = function()
      return { { seasonId = "old", name = "Old season", revision = 3, lifecycleState = "ARCHIVED" } }
    end
    dibs.OfficerUI.RenderPreservedSeasonHistory({}, {}, frame())
    assert_equal("Old season", controls.tables[1].rows[1][2])
    assert_nil(next(controls.buttons))
    local found = false
    for _, entry in ipairs(dibs.OfficerUI.GetNavigationTree()) do if entry.value == "seasonalRoster" then found = true end end
    assert_true(found)
  end)

  it("binds player declarations to authenticated identity and selected season", function()
    local dibs = load()
    local controls, view = capture(dibs), frame()
    dibs.SeasonalRoster.GetSeasonIdentityReview = function() return { revision = 7, relationships = {}, mainChanges = {} } end
    dibs.SeasonalRoster.DeclareRelationship = function(id, input, revision)
      assert_equal("selected-season", id); assert_equal(7, revision)
      assert_equal(dibs.GetPlayerName(), input.mainCharacter); assert_equal("Alt-Realm", input.altCharacter)
      return { ok = true }
    end
    dibs.SeasonalRoster.RequestMainChange = function() return { ok = false, code = "OWNER_MISMATCH" } end
    dibs.PlayerUI.RenderSeasonIdentity({}, {}, view, { seasonId = "selected-season", revision = 7 })
    controls.edits[dibs.L.SEASONAL_ROSTER_ALT_CHARACTER]("Alt-Realm")
    controls.buttons[dibs.L.SEASONAL_ROSTER_DECLARE_ALT]()
    assert_equal(dibs.L.SEASONAL_ROSTER_IDENTITY_SUBMITTED, view.seasonalRosterMessage)
    controls.buttons[dibs.L.SEASONAL_ROSTER_REQUEST_MAIN]()
    assert_equal(dibs.L.SEASONAL_ROSTER_CODE_OWNER_MISMATCH, view.seasonalRosterMessage)
  end)

  it("validates calendar dates and fractional time before submitting a draft", function()
    local dibs = load()
    local value, failure = dibs.OfficerUI.ParseSeasonDateTime("2026-02-30", "12", "00", true)
    assert_nil(value); assert_equal("INVALID_DATE", failure)
    value, failure = dibs.OfficerUI.ParseSeasonDateTime("2026-11-14", "12.5", "00", true)
    assert_nil(value); assert_equal("INVALID_TIME", failure)
    value, failure = dibs.OfficerUI.ParseSeasonDateTime("", "00", "00", false)
    assert_nil(value); assert_nil(failure)
  end)

  it("loads the second season's own form and revision before saving after a season switch", function()
    local dibs = load()
    local selectSeason, save, saved
    local dropdown, button = dibs.AceGUI.AddDropdown, dibs.AceGUI.AddButton
    dibs.AceGUI.AddDropdown = function(shell, parent, label, values, callback, ...)
      if label == dibs.L.SEASONAL_ROSTER_SEASON then selectSeason = callback end
      return dropdown(shell, parent, label, values, callback, ...)
    end
    dibs.AceGUI.AddButton = function(shell, parent, label, callback, ...)
      if label == dibs.L.SEASONAL_ROSTER_SAVE_ENROLLMENT then save = callback end
      return button(shell, parent, label, callback, ...)
    end
    dibs.SeasonalRoster.ListSeasons = function()
      return {
        { seasonId = "A", name = "A", revision = 1, categories = { "RAIDER" },
          lifecycle = { registrationStatus = "OPEN" } },
        { seasonId = "B", name = "B", revision = 2, categories = { "RAIDER" },
          lifecycle = { registrationStatus = "OPEN" } },
      }
    end
    dibs.SeasonalRoster.GetOwnEnrollments = function(id)
      return { { enrollmentId = "own-" .. id, character = "Character" .. id .. "-Realm", revision = id == "A" and 3 or 8,
        primarySpec = id == "A" and "balance" or "restoration", roles = { id == "A" and "DAMAGER" or "HEALER" },
        categoryId = "RAIDER", requestedPath = "STANDARD", status = "ACTIVE" } }
    end
    dibs.SeasonalRoster.GetSeasonIdentityReview = function() return { revision = 0, relationships = {}, mainChanges = {} } end
    dibs.SeasonalRoster.GetPublicRosterPage = function()
      return { rows = {}, page = 1, pages = 1, total = 0 }
    end
    dibs.SeasonalRoster.UpsertOwnEnrollment = function(id, input, revision)
      saved = { id = id, input = input, revision = revision }; return { ok = false, code = "STALE_REVISION" }
    end
    local window = dibs.PlayerUI.CreateWindow()
    window.SelectTab("seasonal-roster")
    assert_equal("CharacterA-Realm", window.seasonalRosterCharacter)
    window.seasonalRosterPrimarySpec = "unsaved-A-edit"
    selectSeason("B")
    assert_equal("CharacterB-Realm", window.seasonalRosterCharacter)
    assert_equal("restoration", window.seasonalRosterPrimarySpec)
    save()
    assert_equal("B", saved.id); assert_equal(8, saved.revision)
    assert_equal("CharacterB-Realm", saved.input.character)
    assert_equal("HEALER", saved.input.roles[1])
    assert_equal("own-B", saved.input.enrollmentId)
  end)

  it("renders a bounded officer review list inside the real shared window", function()
    local dibs = load()
    local rowCount, widths
    local addTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, actions, options)
      if columns[1].title == dibs.L.SEASONAL_ROSTER_CHARACTER then rowCount, widths = #rows, columns end
      return addTable(shell, parent, columns, rows, height, actions, options)
    end
    dibs.SeasonalRoster.ListSeasons = function()
      return { { seasonId = "officer-ui", revision = 2, name = "Reviewed season", registrationState = "CLOSED",
        categories = { "RAIDER" }, lifecycle = { seasonStatus = "REVIEW", registrationStatus = "CLOSED" } } }
    end
    dibs.SeasonalRoster.GetSeasonIdentityReview = function() return { revision = 2, relationships = {}, mainChanges = {} } end
    dibs.SeasonalRoster.GetOfficerEnrollments = function()
      local rows = {}
      for index = 1, 65 do rows[index] = { enrollmentId = "row" .. index, character = "Character" .. index,
        categoryId = "RAIDER", status = "PENDING_REVIEW", primarySpec = "balance", roles = { "DAMAGER" }, revision = 1 } end
      return rows
    end
    dibs.SeasonalRoster.GetSeasonRevisionHistory = function() return {} end
    local window = dibs.OfficerUI.CreateWindow("seasonalRoster")
    window:ActivateRoute("seasonalRoster")
    assert_equal(20, rowCount)
    assert_equal(3, widths[1].weight)
    assert_true(widths[1].minWidth > 0)
    assert_not_nil(window.seasonalRosterCorrectButton)
    assert_equal("seasonalRoster", window.activeTab)
  end)

  it("localizes permissions, confirmation and stale revision recovery in both languages", function()
    local english = load("enUS").L.SEASONAL_ROSTER_CODE_STALE_REVISION
    local dibs = load("frFR")
    assert_true(english ~= dibs.L.SEASONAL_ROSTER_CODE_STALE_REVISION)
    for _, code in ipairs({ "PERMISSION_DENIED", "GUILD_ADMIN_REQUIRED", "MODULE_DISABLED", "REASON_REQUIRED",
      "STALE_REVISION", "STALE_PREVIEW", "OPERATION_CONFLICT", "CONFIRMATION_REQUIRED" }) do
      assert_true(dibs.OfficerUI.SeasonalText(code) ~= code, code)
    end
  end)

  it("declares and reviews Main / Alt through real seasonal services and rejects a stale review", function()
    local dibs = load()
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "identity UI test",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true, preDibModes = {} }))
    local created = dibs.SeasonalRoster.CreateSeason({ name = "Identity season", startAt = dibs.GetTimestamp() + 100,
      registrationStartAt = dibs.GetTimestamp() }, "identity-ui-create")
    assert_true(created.ok, tostring(created.code))
    local season = dibs.SeasonalRoster.ListSeasons()[1]
    local controls, view = capture(dibs), frame()
    dibs.PlayerUI.RenderSeasonIdentity({}, {}, view, season)
    controls.edits[dibs.L.SEASONAL_ROSTER_ALT_CHARACTER]("Alt-Realm")
    controls.buttons[dibs.L.SEASONAL_ROSTER_DECLARE_ALT]()
    assert_equal(dibs.L.SEASONAL_ROSTER_IDENTITY_SUBMITTED, view.seasonalRosterMessage)
    local review = dibs.SeasonalRoster.GetSeasonIdentityReview(season.seasonId)
    assert_equal(1, #review.relationships)
    assert_equal("pending", review.relationships[1].status)
    dibs.OfficerUI.RenderSeasonIdentity({}, {}, view, season)
    controls.edits[dibs.L.SEASONAL_ROSTER_REVIEW_REASON]("Explicit identity review")
    local approve = controls.buttons[dibs.L.SEASONAL_ROSTER_APPROVE .. " — Alt-Realm"]
    assert_not_nil(approve)
    approve()
    review = dibs.SeasonalRoster.GetSeasonIdentityReview(season.seasonId)
    assert_equal("approved", review.relationships[1].status)
    assert_equal(dibs.L.SEASONAL_ROSTER_IDENTITY_REVIEWED, view.seasonalRosterMessage)
    approve()
    assert_equal(dibs.L.SEASONAL_ROSTER_CODE_STALE_REVISION, view.seasonalRosterMessage)
    dibs.PlayerUI.RenderSeasonIdentity({}, {}, view, season)
    controls.edits[dibs.L.SEASONAL_ROSTER_ALT_CHARACTER]("Alt-Realm")
    controls.buttons[dibs.L.SEASONAL_ROSTER_REQUEST_MAIN]()
    assert_equal(dibs.L.SEASONAL_ROSTER_IDENTITY_SUBMITTED, view.seasonalRosterMessage)
    dibs.OfficerUI.RenderSeasonIdentity({}, {}, view, season)
    local identityTable = controls.tables[#controls.tables]
    for _, row in ipairs(identityTable.rows) do
      if row.kind == "main" then identityTable.options.onRowClick(row) end
    end
    dibs.OfficerUI.RenderSeasonIdentity({}, {}, view, season)
    controls.buttons[dibs.L.SEASONAL_ROSTER_APPROVE .. " — Alt-Realm"]()
    review = dibs.SeasonalRoster.GetSeasonIdentityReview(season.seasonId)
    assert_equal("approved", review.mainChanges[1].status)
    assert_equal(14 * 86400, review.mainChanges[1].probationEndsAt - review.mainChanges[1].effectiveAt)
    assert_not_nil(review.mainChanges[1].approverId)
  end)

  it("edits draft dates through the real service without activating the season", function()
    local dibs = load()
    local originalDate, originalTime = _G.date, _G.time
    _G.date = os.date
    _G.time = function(value) if type(value) == "table" then return os.time(value) end return originalTime() end
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "date UI test",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true, preDibModes = {} }))
    local active = dibs.GetCurrentSeasonId()
    local created = dibs.SeasonalRoster.CreateSeason({ name = "Date season", startAt = dibs.GetTimestamp() + 100,
      registrationStartAt = dibs.GetTimestamp() }, "date-ui-create")
    assert_true(created.ok, tostring(created.code))
    local seasons = dibs.SeasonalRoster.ListSeasons()
    local controls, view = capture(dibs), frame()
    dibs.OfficerUI.RenderSeasonConfiguration({}, {}, view, seasons[1], seasons)
    view.seasonalRosterChangeReason = "Reviewed calendar"
    controls.edits[dibs.L.SEASONAL_ROSTER_NAME]("Edited season")
    controls.checks[dibs.L.SEASONAL_ROSTER_DIFFICULTY_NORMAL](true)
    controls.buttons[dibs.L.SEASONAL_ROSTER_SAVE_CONFIGURATION]()
    assert_equal(dibs.L.SEASONAL_ROSTER_DRAFT_SAVED, view.seasonalRosterMessage)
    assert_equal(active, dibs.GetCurrentSeasonId())
    local updated = dibs.SeasonalRoster.ListSeasons()[1]
    assert_equal("Edited season", updated.name)
    assert_equal("NORMAL", updated.categories[1])
    assert_equal("NORMAL", updated.raidDifficulties[1])
    _G.date, _G.time = originalDate, originalTime
  end)

  it("requires a reason and confirmation for each historical Alt correction", function()
    local dibs = load()
    local controls, view, calls = capture(dibs), frame(), 0
    local preview = { seasonId = "legacy-season", previewId = "legacy-preview", mainCharacterKey = "tester-realm",
      resultingPersonBalance = 5, pendingReservations = false,
      sourceBalances = { { character = "Tester-Realm", characterKey = "tester-realm", balance = 5, pendingReservations = 0 },
        { character = "Alt-Realm", characterKey = "alt-realm", balance = 3, pendingReservations = 0 } },
      adjustments = { { character = "Alt-Realm", amount = -3 } } }
    view.seasonLegacyPreview = preview
    dibs.SeasonalRoster.ApplyLegacyBalanceCorrection = function(id, character, expected, reason, operation, confirmation)
      calls = calls + 1
      assert_equal("legacy-season", id); assert_equal("Alt-Realm", character)
      assert_equal("legacy-preview", expected.previewId); assert_equal("Reviewed legacy balances", reason)
      assert_true(confirmation); return { ok = true }
    end
    local season = { seasonId = "legacy-season" }
    local label = string.format(dibs.L.SEASONAL_ROSTER_BALANCE_CORRECT_ALT, "Alt-Realm")
    dibs.OfficerUI.RenderSeasonLegacyBalance({}, {}, view, season)
    controls.buttons[label]()
    assert_equal(0, calls)
    view.seasonLegacyPreview = preview
    dibs.OfficerUI.RenderSeasonLegacyBalance({}, {}, view, season)
    controls.edits[dibs.L.SEASONAL_ROSTER_BALANCE_CORRECTION_REASON]("Reviewed legacy balances")
    controls.checks[dibs.L.SEASONAL_ROSTER_BALANCE_CONFIRM](true)
    controls.buttons[label]()
    assert_equal(1, calls)
    assert_nil(view.seasonLegacyPreview)
    assert_false(view.seasonLegacyConfirmed)
    assert_equal(5, preview.resultingPersonBalance)
  end)
  it("preserves a local form across remote revisions and requires explicit reload", function()
    local dibs = load()
    local originalDate, originalTime = _G.date, _G.time
    register_reset(function() _G.date, _G.time = originalDate, originalTime end)
    _G.date, _G.time = os.date, os.time
    local controls, view = capture(dibs), frame()
    local season = { seasonId = "local-edit", revision = 1, name = "Saved name", categories = { "RAIDER" },
      categoryCatalog = { { id = "RAIDER", name = "Veteran", description = "Retained identity", active = true,
        order = 3, version = 2 } }, raidRules = "Saved rules", raidSchedule = {}, raidDifficulties = {},
      lifecycle = { seasonStatus = "DRAFT" } }
    dibs.OfficerUI.RenderSeasonConfiguration({}, {}, view, season)
    view.seasonConfig.name = "Unsaved local name"
    view.seasonConfig.raidRules = "Unsaved local rules"
    season.revision, season.name = 2, "Remote name"
    dibs.OfficerUI.RenderSeasonConfiguration({}, {}, view, season)
    assert_equal("Unsaved local name", view.seasonConfig.name)
    assert_equal("Unsaved local rules", view.seasonConfig.raidRules)
    assert_equal(1, view.seasonConfig.revision)
    view.seasonConfig.seasonalRosterNewStartDate = "2026-05-10"
    view.seasonConfig.seasonalRosterNewRegistrationStartDate = "2026-05-01"
    view.seasonalRosterChangeReason = "Local review"
    controls.checks[dibs.L.SEASONAL_ROSTER_DIFFICULTY_NORMAL](true)
    local saves = 0
    dibs.SeasonalRoster.UpdateDraft = function(id, patch, expectedRevision)
      saves = saves + 1
      assert_equal("local-edit", id)
      assert_equal("Unsaved local name", patch.name)
      assert_equal(1, expectedRevision)
      return { ok = false, code = "STALE_REVISION" }
    end
    controls.buttons[dibs.L.SEASONAL_ROSTER_SAVE_CONFIGURATION]()
    assert_equal(1, saves)
    assert_equal("Unsaved local rules", view.seasonConfig.raidRules)
    assert_equal(1, view.seasonConfig.revision)

    controls.buttons[dibs.L.SEASONAL_ROSTER_RELOAD_CONFIGURATION]()
    dibs.OfficerUI.RenderSeasonConfiguration({}, {}, view, season)
    assert_equal("Remote name", view.seasonConfig.name)
    assert_equal(2, view.seasonConfig.revision)
  end)

  it("retains catalog metadata and inactive historical identities in the shared form", function()
    local dibs = load()
    local originalDate, originalTime = _G.date, _G.time
    register_reset(function() _G.date, _G.time = originalDate, originalTime end)
    _G.date, _G.time = os.date, os.time
    local state = { name = "Configured season", categories = "MYTHIC", raidRules = "Rules", scheduleRows = {},
      raidDifficulties = {}, timeZone = "UTC", seasonalRosterNewStartDate = "2026-05-10",
      seasonalRosterNewRegistrationStartDate = "2026-05-01", categoryCatalog = {
        { id = "MYTHIC", name = "Veteran", description = "Retained identity", active = true, order = 3, version = 2 },
        { id = "CASUAL", name = "Social", active = true, order = 4, version = 1 } } }
    local input = dibs.OfficerUI.BuildSeasonFormInput(state)
    assert_not_nil(input)
    assert_equal("MYTHIC", input.categories[1])
    assert_equal("MYTHIC", input.raidDifficulties[1])
    assert_equal("Veteran", input.categoryCatalog[1].name)
    assert_equal("Retained identity", input.categoryCatalog[1].description)
    assert_equal(2, input.categoryCatalog[1].version)
    assert_false(input.categoryCatalog[2].active)
    assert_true(state.categoryCatalog[2].active)
  end)

  it("requires an explicit supported choice when editing a legacy custom draft", function()
    local dibs = load()
    local controls, view = capture(dibs), frame()
    local season = { seasonId = "legacy-draft", revision = 1, name = "Legacy draft", categories = { "RAIDER" },
      categoryCatalog = { { id = "RAIDER", name = "Raid Team", active = true, version = 2 } },
      raidDifficulties = {}, lifecycle = { seasonStatus = "DRAFT" } }
    dibs.OfficerUI.RenderSeasonConfiguration({}, {}, view, season)
    assert_nil(controls.edits[dibs.L.SEASONAL_ROSTER_CATEGORIES])
    local input, reason = dibs.OfficerUI.BuildSeasonFormInput(view.seasonConfig)
    assert_nil(input)
    assert_equal(dibs.L.SEASONAL_ROSTER_CATEGORY_REQUIRED, reason)
    assert_equal("RAIDER", season.categories[1])
    assert_true(season.categoryCatalog[1].active)
    controls.checks[dibs.L.SEASONAL_ROSTER_DIFFICULTY_HEROIC](true)
    local originalDate, originalTime = _G.date, _G.time
    register_reset(function() _G.date, _G.time = originalDate, originalTime end)
    _G.date, _G.time = os.date, os.time
    view.seasonConfig.seasonalRosterNewStartDate = "2026-05-10"
    view.seasonConfig.seasonalRosterNewRegistrationStartDate = "2026-05-01"
    local saved
    dibs.SeasonalRoster.UpdateDraft = function(id, patch, revision)
      saved = patch
      assert_equal(season.seasonId, id); assert_equal(1, revision)
      return { ok = true }
    end
    controls.buttons[dibs.L.SEASONAL_ROSTER_SAVE_CONFIGURATION]()
    assert_not_nil(saved)
    assert_equal("HEROIC", saved.categories[1])
    assert_equal("HEROIC", saved.raidDifficulties[1])
    assert_equal("RAIDER", saved.categoryCatalog[2].id)
    assert_equal(2, saved.categoryCatalog[2].version)
    assert_false(saved.categoryCatalog[2].active)
    assert_true(season.categoryCatalog[1].active)
  end)

  it("creates a direct draft with the same signup categories and difficulties", function()
    local dibs = load()
    local originalDate, originalTime = _G.date, _G.time
    register_reset(function() _G.date, _G.time = originalDate, originalTime end)
    _G.date, _G.time = os.date, os.time
    local controls, view = capture(dibs), frame()
    dibs.OfficerUI.RenderNewSeasonForm({}, {}, view)
    assert_nil(controls.edits[dibs.L.SEASONAL_ROSTER_CATEGORIES])
    view.seasonalRosterNewForm.name = "Direct draft"
    view.seasonalRosterNewForm.seasonalRosterNewStartDate = "2026-05-10"
    view.seasonalRosterNewForm.seasonalRosterNewRegistrationStartDate = "2026-05-01"
    controls.checks[dibs.L.SEASONAL_ROSTER_DIFFICULTY_MYTHIC](false)
    local created
    dibs.SeasonalRoster.CreateSeason = function(input)
      created = input; return { ok = true, value = "direct-draft" }
    end
    controls.buttons[dibs.L.SEASONAL_ROSTER_CREATE]()
    assert_equal("DRAFT", created.registrationState)
    assert_equal(1, #created.categories)
    assert_equal("HEROIC", created.categories[1])
    assert_equal("HEROIC", created.raidDifficulties[1])
    assert_equal(dibs.L.SEASONAL_ROSTER_DIFFICULTY_HEROIC, created.categoryCatalog[1].name)
  end)

  it("blocks draft publication until its displayed choices are saved and hides the competing catalog", function()
    local dibs = load()
    local season = { seasonId = "publish-draft", revision = 1, name = "Draft", categories = { "RAIDER" },
      categoryCatalog = { { id = "RAIDER", name = "Raid Team", active = true } },
      raidDifficulties = {}, registrationState = "DRAFT", raidRules = "Rules",
      lifecycle = { seasonStatus = "DRAFT", registrationStatus = "DRAFT" } }
    dibs.SeasonalRoster.ListSeasons = function() return { season } end
    local controls = capture(dibs)
    local calls = 0
    dibs.SeasonalRoster.SetRegistrationState = function() calls = calls + 1; return { ok = true } end
    local window = dibs.OfficerUI.CreateWindow("seasonalRoster")
    assert_nil(controls.buttons[(dibs.L.SEASONAL_ROSTER_SHOW_SECTION or "Edit") .. " — "
      .. dibs.L.SEASONAL_ROSTER_TECHNICAL_CATALOG])
    controls.buttons[dibs.L.SEASONAL_ROSTER_OPEN]()
    assert_equal(0, calls)
    assert_equal(dibs.L.SEASONAL_ROSTER_SAVE_CATEGORIES_FIRST, window.seasonalRosterMessage)
    season.categories, season.raidDifficulties = { "HEROIC" }, { "HEROIC" }
    window.seasonConfig = nil
    window:Refresh()
    controls.checks[dibs.L.SEASONAL_ROSTER_DIFFICULTY_NORMAL](true)
    controls.buttons[dibs.L.SEASONAL_ROSTER_OPEN]()
    assert_equal(0, calls)
    controls.checks[dibs.L.SEASONAL_ROSTER_DIFFICULTY_NORMAL](false)
    controls.buttons[dibs.L.SEASONAL_ROSTER_OPEN]()
    assert_equal(1, calls)
  end)

  it("preserves published custom categories and existing registrations when viewing management", function()
    local dibs = load()
    local season = { seasonId = "published", revision = 3, name = "Published", categories = { "RAIDER" },
      categoryCatalog = { { id = "RAIDER", name = "Raid Team", active = true, version = 2 } },
      raidDifficulties = { "MYTHIC" }, registrationState = "OPEN", raidRules = "Rules",
      lifecycle = { seasonStatus = "REGISTRATION_OPEN", registrationStatus = "OPEN" } }
    local enrollment = { enrollmentId = "existing", character = "Player-Realm", categoryId = "RAIDER",
      categoryName = "Raid Team", categoryVersion = 2, revision = 4, primarySpec = "balance", roles = {} }
    dibs.SeasonalRoster.ListSeasons = function() return { season } end
    dibs.SeasonalRoster.GetOfficerEnrollments = function() return { enrollment } end
    local controls = capture(dibs)
    local window = dibs.OfficerUI.CreateWindow("seasonalRoster")
    assert_nil(window.seasonConfig)
    assert_nil(controls.checks[dibs.L.SEASONAL_ROSTER_DIFFICULTY_MYTHIC])
    assert_not_nil(controls.buttons[(dibs.L.SEASONAL_ROSTER_SHOW_SECTION or "Edit") .. " — "
      .. dibs.L.SEASONAL_ROSTER_TECHNICAL_CATALOG])
    assert_equal("RAIDER", season.categories[1])
    assert_equal("MYTHIC", season.raidDifficulties[1])
    assert_equal("Raid Team", season.categoryCatalog[1].name)
    assert_true(season.categoryCatalog[1].active)
    assert_equal(3, season.revision)
    assert_equal("RAIDER", enrollment.categoryId)
    assert_equal(2, enrollment.categoryVersion)
    assert_equal(4, enrollment.revision)
  end)

  it("opens creation only by explicit navigation and retains its unfinished input", function()
    local dibs = load()
    local window = dibs.OfficerUI.CreateWindow("seasonalRoster")
    window:ActivateRoute("seasonalRoster")
    assert_nil(window.seasonalRosterCreateButton)
    local toggle = window.seasonalRosterNewSeasonButton
    toggle.callbacks.OnClick(toggle, "OnClick")
    assert_not_nil(window.seasonalRosterCreateButton)
    local draft = window.seasonalRosterNewForm
    draft.nameControl.callbacks.OnTextChanged(draft.nameControl, "OnTextChanged", "Unfinished local season")
    toggle = window.seasonalRosterNewSeasonButton
    toggle.callbacks.OnClick(toggle, "OnClick")
    assert_nil(window.seasonalRosterCreateButton)
    toggle = window.seasonalRosterNewSeasonButton
    toggle.callbacks.OnClick(toggle, "OnClick")
    assert_equal("Unfinished local season", window.seasonalRosterNewForm.name)
    assert_equal(0, #dibs.SeasonalRoster.ListSeasons())
  end)

end)
