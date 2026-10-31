local loader = require("helpers.load_addon")

-- RF-0020 regression suite.
--
-- RF-0020 - "OfficerUI : aucune interface n'expose la revue des
-- declarations main/alt par un GM ou un Officier"
-- (docs/code-audit/INDEX.md#rf-0020).
--
-- A player can submit a main/alt declaration and a main-change request
-- since RF-0024, but no officer-facing surface could review them:
-- `CharacterEligibility.ListRelationships`, `ListMainChanges`,
-- `ReviewRelationship` and `ApproveMainChange` had no consumer in
-- `src/ui/`. A submitted declaration therefore stayed `pending` forever.
--
-- The domain contract was already complete and is reused unchanged:
-- `ProtectedActions.Execute("eligibility.relationship.review", ...)` and
-- `ProtectedActions.Execute("eligibility.main.review", ...)` are the only
-- sanctioned mutation paths. The RF-0014 and RF-0017 group guards stay
-- enforced by the domain layer; the surface only exposes them.

local function setup(options)
  options = options or {}
  options.withAce3 = true
  options.wow = options.wow or {
    playerName = "Tester-Realm", guildLeader = true,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Alt-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
  }
  return select(2, loader.load(options))
end

-- Capture the Officer eligibility tab and the table rows it renders.
local function captureOfficerEligibility(dibs, options)
  options = options or {}
  local captured = { headers = {}, labels = {}, buttons = {}, tables = {} }
  local originalAddHeader = dibs.AceGUI.AddHeader
  local originalAddLabel = dibs.AceGUI.AddLabel
  local originalAddButton = dibs.AceGUI.AddButton
  local originalAddTable = dibs.AceGUI.AddTable
  dibs.AceGUI.AddHeader = function(shell, parent, text, description)
    captured.headers[#captured.headers + 1] = tostring(text or "")
    return originalAddHeader(shell, parent, text, description)
  end
  dibs.AceGUI.AddLabel = function(shell, parent, text, fullWidth)
    captured.labels[#captured.labels + 1] = tostring(text or "")
    return originalAddLabel(shell, parent, text, fullWidth)
  end
  dibs.AceGUI.AddButton = function(shell, parent, text, callback, width)
    captured.buttons[#captured.buttons + 1] = { text = tostring(text or ""), callback = callback }
    return originalAddButton(shell, parent, text, callback, width)
  end
  dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, opts)
    captured.tables[#captured.tables + 1] = { columns = columns, rows = rows, options = opts }
    return originalAddTable(shell, parent, columns, rows, height, rowActions, opts)
  end

  local frame = dibs.OfficerUI.CreateWindow()
  frame:Show()
  frame.SelectTab("eligibility")
  frame:Refresh()

  dibs.AceGUI.AddHeader = originalAddHeader
  dibs.AceGUI.AddLabel = originalAddLabel
  dibs.AceGUI.AddButton = originalAddButton
  dibs.AceGUI.AddTable = originalAddTable
  return captured, frame
end

local function hasText(list, needle)
  for _, value in ipairs(list or {}) do
    if type(value) == "string" and value:find(needle, 1, true) then return true end
  end
  return false
end

describe("RF-0020 officers can review main/alt declarations", function()
  it("lists a pending player declaration in the Officer eligibility tab", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Tester-Realm", altCharacterId = "Alt-Realm",
      seasonId = seasonId,
    }, "Tester-Realm"))

    local captured = captureOfficerEligibility(dibs)

    assert_true(hasText(captured.headers, "Main / alt declarations"),
      "the Officer eligibility tab has no Main / alt declarations section")
    local found = false
    for _, tableInfo in ipairs(captured.tables) do
      for _, row in ipairs(tableInfo.rows or {}) do
        if row.relationshipId then found = true end
      end
    end
    assert_true(found, "no pending relationship row is offered for review")
  end)

  it("approves a pending declaration through the protected action path", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    local relationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Tester-Realm", altCharacterId = "Alt-Realm",
      seasonId = seasonId,
    }, "Tester-Realm"))

    local captured, frame = captureOfficerEligibility(dibs)

    local approve
    for _, button in ipairs(captured.buttons) do
      if button.text:find("Approve", 1, true) then approve = button.callback break end
    end
    assert_not_nil(approve, "no Approve control is offered for a pending relationship")
    approve()

    local reviewed = dibs.CharacterEligibility.GetRelationshipStatus("Tester-Realm", seasonId)
    local found = nil
    for _, entry in ipairs(reviewed) do
      if entry.relationshipId == relationship.relationshipId then found = entry end
    end
    assert_not_nil(found, "the relationship disappeared after approval")
    assert_equal("approved", found.status, "the declaration was not approved")
    assert_equal("group:tester-realm", dibs.CharacterEligibility.GetPlayerGroup("Alt-Realm", seasonId),
      "the approved alt was not attached to the declaring player's group")
  end)

  it("rejects a declaration without changing the protected data", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    local relationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Tester-Realm", altCharacterId = "Alt-Realm",
      seasonId = seasonId,
    }, "Tester-Realm"))

    local captured = captureOfficerEligibility(dibs)

    -- FR-014 / FR-019 of spec 005: a refusal carries a reason. The officer
    -- surface collects one before submitting.
    captured.reason = "Not this player's character"
    dibs.OfficerUI.ReviewEligibilityRelationship(relationship.relationshipId, "rejected", captured.reason)

    local reviewed = dibs.CharacterEligibility.GetRelationshipStatus("Tester-Realm", seasonId)
    for _, entry in ipairs(reviewed) do
      if entry.relationshipId == relationship.relationshipId then
        assert_equal("rejected", entry.status, "the declaration was not rejected")
      end
    end
    -- A refusal must leave the protected loot grouping untouched.
    assert_equal("character:alt-realm", dibs.CharacterEligibility.GetPlayerGroup("Alt-Realm", seasonId),
      "a rejected declaration changed the protected-loot group")
  end)

  it("refuses a rejection that carries no reason", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    local relationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Tester-Realm", altCharacterId = "Alt-Realm",
      seasonId = seasonId,
    }, "Tester-Realm"))

    local result = dibs.OfficerUI.ReviewEligibilityRelationship(relationship.relationshipId, "rejected")
    assert_false(result.ok, "a rejection without a reason was accepted")
    -- The domain reason is reported as the diagnostic; `reasonCode` carries
    -- the authority decision of the protected action.
    assert_equal("REASON_REQUIRED", result.diagnostic)

    local reviewed = dibs.CharacterEligibility.GetRelationshipStatus("Tester-Realm", seasonId)
    for _, entry in ipairs(reviewed) do
      if entry.relationshipId == relationship.relationshipId then
        assert_equal("pending", entry.status, "the declaration was rejected without a reason")
      end
    end
  end)

  it("never merges two unrelated players when approving a main change", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    -- The stranger is linked to their own main, so their character already
    -- belongs to another player's group.
    local stranger = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Stranger-Realm", altCharacterId = "Stranger-Alt-Realm",
      seasonId = seasonId,
    }, "Stranger-Realm"))
    assert(dibs.CharacterEligibility.ReviewRelationship(stranger.relationshipId, "approved", "Tester-Realm"))

    local change, reason = dibs.CharacterEligibility.RequestMainChange({
      oldMainId = "Tester-Realm", newMainId = "Stranger-Realm", reason = "swap", seasonId = seasonId,
    }, "Tester-Realm")
    assert_nil(change, "a main change to another player's character was accepted")
    assert_equal("MAIN_CHANGE_GROUP_MISMATCH", reason)

    local captured = captureOfficerEligibility(dibs)
    assert_true(hasText(captured.headers, "Main / alt declarations"),
      "the Officer eligibility tab has no Main / alt declarations section")
  end)

  it("keeps the protected action as the only mutation path", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    local relationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Tester-Realm", altCharacterId = "Alt-Realm",
      seasonId = seasonId,
    }, "Tester-Realm"))

    -- A member without guild authority must not be able to approve through
    -- the officer surface. The surface must route through the protected
    -- action, which enforces the GM/officer authority.
    local memberDib = setup({ wow = {
      playerName = "Plain-Realm", guildLeader = false,
      guildMembers = { "Plain-Realm", "Tester-Realm", "Alt-Realm" },
      guildRankIndices = { [1] = 3, [2] = 3, [3] = 3 },
    } })
    local denied = memberDib.ProtectedActions.Execute("eligibility.relationship.review", "Plain-Realm", {
      relationshipId = relationship.relationshipId, status = "approved",
    })
    assert_false(denied.ok, "a non-officer was allowed to approve a relationship")
    assert_equal("GUILD_ADMIN_REQUIRED", denied.reasonCode)

    -- The officer surface itself must not be able to approve without the
    -- protected action's authority check. The domain also carries its own
    -- authority guard, so a surface that skipped the protected action
    -- would still be refused here; removing both guards must be
    -- detected.
    local plain = setup({ wow = {
      playerName = "Plain-Realm", guildLeader = false,
      guildMembers = { "Plain-Realm", "Tester-Realm", "Alt-Realm" },
      guildRankIndices = { [1] = 3, [2] = 3, [3] = 3 },
    } })
    local plainRelationship = assert(plain.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Plain-Realm", altCharacterId = "Alt-Realm",
      seasonId = plain.Seasons.GetCurrent().id,
    }, "Plain-Realm"))
    local plainResult = plain.OfficerUI.ReviewEligibilityRelationship(plainRelationship.relationshipId, "approved")
    assert_false(plainResult.ok, "a non-officer approved a relationship through the officer surface")
    local plainReviewed = plain.CharacterEligibility.GetRelationshipStatus("Plain-Realm", plain.Seasons.GetCurrent().id)
    for _, entry in ipairs(plainReviewed) do
      if entry.relationshipId == plainRelationship.relationshipId then
        assert_equal("pending", entry.status, "a non-officer approved a relationship")
      end
    end
  end)
end)
