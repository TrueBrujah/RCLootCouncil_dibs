local loader = require("helpers.load_addon")
local Fixtures = require("helpers.seasonal_roster_fixtures")

local guild = { "GameMaster-Realm", "Officer-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function adoptPolicies(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, {
    reason = "season activation test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
    { allowPublicPreDibs = true, preDibModes = {} }, "season activation test"))
  assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil,
    "enable seasonal roster for this test"))
end

local function makeSeason(noRankPolicy, signupCharacter, linkedAlt, publishAllocations)
  local _, gm = loader.load({ withAce3 = true, wow = { playerName = guild[1], guildLeader = true,
    guildMembers = guild, guildRankIndices = ranks } })
  adoptPolicies(gm)
  local now = gm.GetTimestamp()
  local created = gm.SeasonalRoster.CreateSeason({ name = "Activation review", startAt = now + 10000,
    registrationStartAt = now - 10 }, "activation-create", guild[1])
  assert_true(created.ok, tostring(created.code))
  local revision = created.revision
  if noRankPolicy then
    local updated = gm.SeasonalRoster.UpdateDraft(created.value, { noRankPolicy = noRankPolicy }, revision,
      "activation-policy", "Set no-rank allocation policy", guild[1])
    assert_true(updated.ok, tostring(updated.code))
    revision = updated.revision
  end
  if linkedAlt then
    local link = gm.CharacterEligibility.DeclareRelationship({ seasonId = created.value,
      mainCharacter = guild[3], altCharacter = linkedAlt }, guild[3])
    assert_true(link ~= nil)
    assert_equal("approved", gm.CharacterEligibility.ApproveRelationship(link.relationshipId, guild[1]).status)
  end
  local opened = gm.SeasonalRoster.SetRegistrationState(created.value, "OPEN", revision,
    "activation-open", "Open registration", guild[1])
  assert_true(opened.ok, tostring(opened.code))
  local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
  local _, player = loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = guild[3], guildLeader = false, guildMembers = guild, guildRankIndices = ranks,
  } })
  local signup = player.SeasonalRoster.UpsertOwnEnrollment(created.value,
    Fixtures.enrollment({ character = signupCharacter or guild[3] }), 0, "activation-signup")
  assert_true(signup.ok, tostring(signup.code))
  local altSignup
  if linkedAlt then
    altSignup = player.SeasonalRoster.UpsertOwnEnrollment(created.value,
      Fixtures.enrollment({ character = linkedAlt }), 0, "activation-alt-signup")
    assert_true(altSignup.ok, tostring(altSignup.code))
  end
  local _, gmReview = loader.load({ withAce3 = true, savedVariables = _G.RCLootCouncil_dibsDB, wow = {
    playerName = guild[1], guildLeader = true, guildMembers = guild, guildRankIndices = ranks,
  } })
  local approved = gmReview.SeasonalRoster.AdminUpdateEnrollment(created.value, signup.value,
    { status = "ACTIVE" }, signup.revision, "Approved for this season", "activation-approve", guild[1])
  assert_true(approved.ok, tostring(approved.code))
  if altSignup then
    local approvedAlt = gmReview.SeasonalRoster.AdminUpdateEnrollment(created.value, altSignup.value,
      { status = "ACTIVE" }, altSignup.revision, "Approved alternate enrollment", "activation-approve-alt", guild[1])
    assert_true(approvedAlt.ok, tostring(approvedAlt.code))
  end
  local closed = gmReview.SeasonalRoster.SetRegistrationState(created.value, "CLOSED", opened.revision,
    "activation-close", "Close and review the roster", guild[1])
  assert_true(closed.ok, tostring(closed.code))
  gmReview.GetDB().rankRules[created.value] = { ["3"] = {
    rankIndex = 3, rankName = "Member", allocation = 2, enabled = true,
  } }
  if publishAllocations ~= false then
    local published = gmReview.SeasonalRoster.PublishRankAllocations(created.value, closed.revision,
      "activation-publish-ranks", "Publish rank values for activation", guild[1])
    assert_true(published.ok, tostring(published.code))
    closed.revision = published.revision
  end
  return gmReview, created.value, closed.revision
end

describe("seasonal roster activation preview", function()
  it("is read-only and reports the approved Main allocation without activating the season", function()
    local gm, seasonId, seasonRevision = makeSeason()
    local seasonBefore = gm.DeepCopy(gm.GetDB().seasonalRoster)
    local rankRulesBefore = gm.DeepCopy(gm.GetDB().rankRules)
    local eligibilityBefore = gm.DeepCopy(gm.GetDB().characterEligibility or {})
    local ledgerBefore = gm.DeepCopy(gm.GetDB().ledger)
    local activeSeasonBefore = gm.GetCurrentSeasonId()

    local preview, reason = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    assert_true(preview ~= nil, tostring(reason))
    assert_true(preview.ready, table.concat((function()
      local codes = {}
      for _, blocker in ipairs(preview.blockers or {}) do codes[#codes + 1] = blocker.code end
      return codes
    end)(), ","))
    assert_equal(seasonRevision, preview.seasonRevision)
    assert_equal(1, preview.participantCount)
    assert_equal(2, preview.totalAllocation)
    assert_equal(guild[3]:lower(), preview.rows[1].characterKey)
    assert_equal("GUILD_RANK", preview.rows[1].allocationSource)
    assert_equal(seasonBefore.seasons[seasonId].currentRevision,
      gm.GetDB().seasonalRoster.seasons[seasonId].currentRevision)
    assert_equal(gm.Sync.CalculateContentHash(seasonBefore), gm.Sync.CalculateContentHash(gm.GetDB().seasonalRoster))
    assert_equal(gm.Sync.CalculateContentHash(rankRulesBefore), gm.Sync.CalculateContentHash(gm.GetDB().rankRules))
    assert_equal(gm.Sync.CalculateContentHash(eligibilityBefore),
      gm.Sync.CalculateContentHash(gm.GetDB().characterEligibility or {}))
    assert_equal(gm.Sync.CalculateContentHash(ledgerBefore), gm.Sync.CalculateContentHash(gm.GetDB().ledger))
    assert_equal(activeSeasonBefore, gm.GetCurrentSeasonId())
  end)

  it("prepares a content-bound manifest and rejects altered or stale dependencies", function()
    local gm, seasonId = makeSeason()
    local preview = assert(gm.SeasonalRoster.PreviewActivation(seasonId, guild[1]))
    local before = gm.DeepCopy(gm.GetDB().seasonalRoster)
    local manifest, reason = gm.SeasonalRoster.PrepareActivationManifest(seasonId,
      preview.previewId, "prepare-activation-manifest", guild[1])
    assert_not_nil(manifest, tostring(reason))
    assert_equal("PREPARED", manifest.state)
    assert_equal(seasonId, manifest.seasonId)
    local valid, validationReason = gm.SeasonalRoster.ValidateActivationManifest(manifest, guild[1])
    assert_true(valid, tostring(validationReason))
    assert_equal(gm.Sync.CalculateContentHash(before),
      gm.Sync.CalculateContentHash(gm.GetDB().seasonalRoster), "preparation and validation are read-only")
    assert_equal(gm.GetCurrentSeasonId(), gm.GetDB().currentSeasonId)

    local edited = gm.DeepCopy(manifest)
    edited.rows[1].allocation = edited.rows[1].allocation + 1
    valid, validationReason = gm.SeasonalRoster.ValidateActivationManifest(edited, guild[1])
    assert_false(valid)
    assert_equal("ACTIVATION_MANIFEST_HASH_MISMATCH", validationReason)

    edited = gm.DeepCopy(manifest)
    edited.unrecognizedField = true
    edited.contentHash = nil
    edited.contentHash = gm.Sync.CalculateContentHash(edited)
    valid, validationReason = gm.SeasonalRoster.ValidateActivationManifest(edited, guild[1])
    assert_false(valid)
    assert_equal("INVALID_ACTIVATION_MANIFEST", validationReason)

    gm.GetDB().seasonalRoster.seasons[seasonId].rosterRevision =
      gm.GetDB().seasonalRoster.seasons[seasonId].rosterRevision + 1
    valid, validationReason = gm.SeasonalRoster.ValidateActivationManifest(manifest, guild[1])
    assert_false(valid)
    assert_equal("STALE_ACTIVATION_MANIFEST", validationReason)
  end)

  it("refuses to prepare an activation manifest from a stale preview", function()
    local gm, seasonId = makeSeason()
    local preview = assert(gm.SeasonalRoster.PreviewActivation(seasonId, guild[1]))
    local rejected, reason = gm.SeasonalRoster.PrepareActivationManifest(seasonId,
      "stale-preview", "prepare-stale-manifest", guild[1])
    assert_nil(rejected)
    assert_equal("STALE_ACTIVATION_PREVIEW", reason)
    assert_equal(preview.previewId, gm.SeasonalRoster.PreviewActivation(seasonId, guild[1]).previewId)
  end)

  it("invalidates an activation manifest when the reviewed Main/Alt identity changes", function()
    local gm, seasonId = makeSeason()
    local preview = assert(gm.SeasonalRoster.PreviewActivation(seasonId, guild[1]))
    local manifest, reason = gm.SeasonalRoster.PrepareActivationManifest(seasonId,
      preview.previewId, "prepare-before-identity-change", guild[1])
    assert_not_nil(manifest, tostring(reason))

    local relationship = gm.CharacterEligibility.DeclareRelationship({
      seasonId = seasonId, mainCharacter = guild[3], altCharacter = "Player-Alt-Realm",
    }, guild[3])
    assert_not_nil(relationship)
    local approved = gm.CharacterEligibility.ApproveRelationship(relationship.relationshipId, guild[1])
    assert_equal("approved", approved.status)

    local valid, validationReason = gm.SeasonalRoster.ValidateActivationManifest(manifest, guild[1])
    assert_false(valid)
    assert_equal("STALE_ACTIVATION_MANIFEST", validationReason)
  end)

  it("invalidates an activation manifest when the published season allocation snapshot changes", function()
    local gm, seasonId = makeSeason()
    local preview = assert(gm.SeasonalRoster.PreviewActivation(seasonId, guild[1]))
    local manifest, reason = gm.SeasonalRoster.PrepareActivationManifest(seasonId,
      preview.previewId, "prepare-before-allocation-change", guild[1])
    assert_not_nil(manifest, tostring(reason))

    gm.GetDB().rankRules[seasonId]["3"].allocation = 4
    local published = gm.SeasonalRoster.PublishRankAllocations(seasonId, preview.seasonRevision,
      "republish-allocation-snapshot", "Review updated season rank allocation", guild[1])
    assert_true(published.ok, tostring(published.code))

    local valid, validationReason = gm.SeasonalRoster.ValidateActivationManifest(manifest, guild[1])
    assert_false(valid)
    assert_equal("STALE_ACTIVATION_MANIFEST", validationReason)
  end)

  it("blocks an unpublished allocation snapshot and missing off-guild policy", function()
    local gm, seasonId = makeSeason(nil, nil, nil, false)
    local preview = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    assert_false(preview.ready)
    local found = false
    for _, blocker in ipairs(preview.blockers) do
      if blocker.code == "RANK_ALLOCATION_NOT_PUBLISHED" then found = true end
    end
    assert_true(found)

    local guestSignup = gm.SeasonalRoster.AdminUpdateEnrollment(seasonId, "missing", {}, 1,
      "No side effect", "unused-operation", guild[1])
    assert_false(guestSignup.ok)
    assert_equal("ENROLLMENT_NOT_FOUND", guestSignup.code)
  end)

  it("requires an authorized officer and a valid local draft before publishing allocations", function()
    local gm, seasonId, revision = makeSeason()
    local before = gm.DeepCopy(gm.GetDB().seasonalRoster)
    local denied = gm.SeasonalRoster.PublishRankAllocations(seasonId, revision,
      "member-publish-ranks", "Try unauthorized publication", guild[3])
    assert_false(denied.ok)
    assert_equal("GUILD_ADMIN_REQUIRED", denied.code)
    assert_equal(gm.Sync.CalculateContentHash(before), gm.Sync.CalculateContentHash(gm.GetDB().seasonalRoster))

    gm.GetDB().rankRules[seasonId]["3"].allocation = -1
    local invalid = gm.SeasonalRoster.PublishRankAllocations(seasonId, revision,
      "invalid-publish-ranks", "Reject invalid rank allocation", guild[1])
    assert_false(invalid.ok)
    assert_equal("INVALID_INPUT", invalid.code)
    assert_equal(revision, gm.SeasonalRoster.GetCurrentRevision(seasonId))
  end)

  it("uses the season's explicit fixed allocation for approved off-guild participants", function()
    local gm, seasonId = makeSeason({ mode = "FIXED", allocation = 3 }, "Guest-Realm")
    local preview = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    assert_true(preview.ready)
    assert_equal(1, preview.participantCount)
    assert_equal(3, preview.totalAllocation)
    assert_equal("SEASON_NO_RANK_POLICY", preview.rows[1].allocationSource)
  end)

  it("blocks an approved off-guild participant when the season has no explicit policy", function()
    local gm, seasonId = makeSeason(nil, "Guest-Realm")
    local preview = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    assert_false(preview.ready)
    assert_equal("NO_RANK_POLICY_UNCONFIGURED", preview.blockers[1].code)
    assert_equal(0, preview.participantCount)
  end)

  it("lists an off-guild participant as excluded when that season explicitly excludes them", function()
    local gm, seasonId = makeSeason({ mode = "EXCLUDE" }, "Guest-Realm")
    local preview = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    assert_true(preview.ready)
    assert_equal(0, preview.participantCount)
    assert_equal("Guest-Realm", preview.excluded[1].character)
    assert_equal("NO_GUILD_RANK_EXCLUDED", preview.excluded[1].reason)
  end)

  it("counts only the explicitly selected Main when linked Main and Alt are both approved", function()
    local gm, seasonId = makeSeason(nil, nil, "Player-Alt-Realm")
    local preview = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    assert_true(preview.ready)
    assert_equal(1, preview.participantCount)
    assert_equal(guild[3]:lower(), preview.rows[1].characterKey)
    assert_equal(1, #preview.excluded)
    assert_equal("Player-Alt-Realm", preview.excluded[1].character)
    assert_equal("ALT_NOT_COUNTED", preview.excluded[1].reason)
  end)

  it("blocks activation while a linked Alt still has a non-zero legacy balance", function()
    local gm, seasonId = makeSeason(nil, nil, "Player-Alt-Realm")
    local ledger = gm.Ledger
    local getBalance, getReservations = ledger.GetBalance, ledger.GetPendingDibReservations
    ledger.GetBalance = function(name, identitySeasonId, ledgerId)
      if name == "Player-Alt-Realm" then return 2 end
      return getBalance(name, identitySeasonId, ledgerId)
    end
    ledger.GetPendingDibReservations = function(name, identitySeasonId, ledgerId)
      return getReservations(name, identitySeasonId, ledgerId)
    end
    local preview = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    ledger.GetBalance, ledger.GetPendingDibReservations = getBalance, getReservations
    assert_false(preview.ready)
    local found = false
    for _, blocker in ipairs(preview.blockers) do
      if blocker.code == "PERSON_BALANCE_RECONCILIATION_REQUIRED" then found = true end
    end
    assert_true(found)
  end)

  it("blocks activation while a linked Alt has a pending Dibs reservation", function()
    local gm, seasonId = makeSeason(nil, nil, "Player-Alt-Realm")
    local ledger = gm.Ledger
    local getReservations = ledger.GetPendingDibReservations
    ledger.GetPendingDibReservations = function(name, identitySeasonId, ledgerId)
      if name == "Player-Alt-Realm" then return 1 end
      return getReservations(name, identitySeasonId, ledgerId)
    end
    local preview = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    ledger.GetPendingDibReservations = getReservations
    assert_false(preview.ready)
    local found = false
    for _, blocker in ipairs(preview.blockers) do
      if blocker.code == "PERSON_BALANCE_RESERVATIONS_PENDING" then found = true end
    end
    assert_true(found)
  end)

  it("changes the preview identity when the source ledger revision changes", function()
    local gm, seasonId = makeSeason()
    local first = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    local getRevision = gm.Ledger.GetDataRevision
    gm.Ledger.GetDataRevision = function(ledgerId)
      return (getRevision(ledgerId) or 0) + 1
    end
    local second = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    gm.Ledger.GetDataRevision = getRevision
    assert_true(first.ready and second.ready)
    assert_true(first.previewId ~= second.previewId)
    assert_equal(first.sourceLedgerId, second.sourceLedgerId)
    assert_true(second.sourceLedgerRevision > first.sourceLedgerRevision)
  end)

  it("binds preview to the synchronized snapshot, not later local rank edits", function()
    local gm, seasonId = makeSeason()
    local first = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    assert_equal(seasonId, first.dependencies.seasonId)
    assert_true(type(first.dependencies.seasonConfigHash) == "string")
    assert_true(type(first.dependencies.approvedRosterHash) == "string")
    assert_true(type(first.dependencies.guildRosterHash) == "string")
    assert_true(type(first.dependencies.rankRulesHash) == "string")
    assert_equal(gm.GetDB().currentSeasonId, first.dependencies.activeSeasonId)
    gm.GetDB().rankRules[seasonId]["3"].allocation = 5
    local second = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    assert_equal(first.previewId, second.previewId)
    assert_equal(first.dependencies.rankRulesHash, second.dependencies.rankRulesHash)
    assert_equal(2, second.rows[1].allocation)
    local published = gm.SeasonalRoster.PublishRankAllocations(seasonId, second.seasonRevision,
      "activation-republish-ranks", "Update reviewed rank values", guild[1])
    assert_true(published.ok, tostring(published.code))
    local third = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    assert_true(third.previewId ~= first.previewId)
    assert_equal(5, third.rows[1].allocation)
  end)

  it("checks linked legacy balances in the currently active season", function()
    local gm, seasonId = makeSeason(nil, nil, "Player-Alt-Realm")
    local activeSeasonId = gm.GetDB().currentSeasonId
    local ledger = gm.Ledger
    local getBalance, getReservations = ledger.GetBalance, ledger.GetPendingDibReservations
    local balanceSeasonSeen
    ledger.GetBalance = function(name, identitySeasonId, ledgerId)
      if name == "Player-Alt-Realm" then balanceSeasonSeen = identitySeasonId end
      return getBalance(name, identitySeasonId, ledgerId)
    end
    ledger.GetPendingDibReservations = function(name, identitySeasonId, ledgerId)
      return getReservations(name, identitySeasonId, ledgerId)
    end
    local preview = gm.SeasonalRoster.PreviewActivation(seasonId, guild[1])
    ledger.GetBalance, ledger.GetPendingDibReservations = getBalance, getReservations
    assert_true(preview.ready)
    assert_equal(activeSeasonId, balanceSeasonSeen)
    assert_equal(activeSeasonId, preview.balanceSeasonId)
  end)

  it("rejects invalid no-rank policy values and preserves valid policy in season revision", function()
    loader.load({ withAce3 = true })
    local valid, normalized = Dibs.SeasonalRoster.ValidateSeasonInput({ name = "Policy", noRankPolicy = {
      mode = "FIXED", allocation = 4,
    } })
    assert_true(valid)
    assert_equal(4, normalized.noRankPolicy.allocation)
    assert_false(Dibs.SeasonalRoster.ValidateSeasonInput({ name = "Bad policy", noRankPolicy = {
      mode = "FIXED", allocation = 100001,
    } }))
    assert_false(Dibs.SeasonalRoster.ValidateSeasonInput({ name = "Bad policy", noRankPolicy = {
      mode = "UNKNOWN",
    } }))
  end)
end)
