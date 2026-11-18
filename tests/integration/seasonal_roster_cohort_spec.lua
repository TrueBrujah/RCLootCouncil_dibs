local loader = require("helpers.load_addon")
local fixtures = require("helpers.seasonal_roster_fixtures")

local function encode(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) ~= "table" then return tostring(value) end
  local keys, parts = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if type(a) ~= type(b) then return type(a) < type(b) end
    return a < b
  end)
  for _, key in ipairs(keys) do parts[#parts + 1] = "[" .. encode(key) .. "]=" .. encode(value[key]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function setup(count)
  local gm, members, ranks = "Coordinator-Realm", { "Coordinator-Realm" }, { [1] = 0 }
  for index = 1, count + 900 do
    members[#members + 1] = string.format(index <= count and "Raider%03d-Realm" or "Inactive%03d-Realm", index)
    ranks[#members] = 3
  end
  local _, dibs = loader.load({ withAce3 = true, wow = {
    playerName = gm, guildLeader = true, guildMembers = members, guildRankIndices = ranks } })
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "cohort regression",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
    { allowPublicPreDibs = true, preDibModes = {} }, "cohort regression"))
  assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil, "enable cohort regression"))
  local baseline = assert(dibs.HistoricalBaseline.FinalizeBaseline(nil))
  assert_true(dibs.Governance.Change(nil, { future = { authority = { schema = 1, state = "ACTIVE",
    coordinator = assert(dibs.Identity.CreateSnapshot(gm)), ledgerEpoch = 7,
    transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash } } } }))
  assert_true(dibs.Governance.EnableV2(nil, { gm }))
  local priorSeason = dibs.GetCurrentSeasonId()
  local oldEvent, oldReason = dibs.Ledger.Grant(gm, 5, "previous-season allocation", "manual", priorSeason)
  assert_not_nil(oldEvent, tostring(oldReason))
  local now = dibs.GetTimestamp()
  local created = dibs.SeasonalRoster.CreateSeason({ name = "Approved cohort " .. count,
    startAt = now + 10000, registrationStartAt = now - 10 }, "cohort-create", gm)
  assert_true(created.ok, tostring(created.code))
  local opened = dibs.SeasonalRoster.SetRegistrationState(created.value, "OPEN", created.revision,
    "cohort-open", "Open registration", gm)
  assert_true(opened.ok, tostring(opened.code))
  -- Seed already-reviewed service records. Owner-bound signup/review is tested
  -- separately; this regression measures allocation work against the cohort.
  local season = dibs.GetDB().seasonalRoster.seasons[created.value]
  for index = 1, count do
    local character = string.format("Raider%03d-Realm", index)
    local id = "cohort-" .. index
    season.enrollments[id] = fixtures.enrollment({ enrollmentId = id, seasonId = created.value,
      character = character, characterKey = character:lower(), status = "ACTIVE" })
  end
  season.rosterRevision = count
  local closed = dibs.SeasonalRoster.SetRegistrationState(created.value, "CLOSED", opened.revision,
    "cohort-close", "Review complete", gm)
  assert_true(closed.ok, tostring(closed.code))
  dibs.GetDB().rankRules[created.value] = {
    ["3"] = { rankIndex = 3, rankName = "Member", allocation = 2, enabled = true } }
  local published = dibs.SeasonalRoster.PublishRankAllocations(created.value, closed.revision,
    "cohort-publish", "Publish reviewed allocations", gm)
  assert_true(published.ok, tostring(published.code))
  dibs.Ace3.Serialize = encode
  return dibs, gm, created.value, published.revision, priorSeason
end

describe("seasonal approved-cohort integration", function()
  for _, count in ipairs({ 30, 60 }) do
    it("activates and reconciles " .. count .. " approved people with 900 unrelated guild characters", function()
      local dibs, gm, seasonId, revision, priorSeason = setup(count)
      local oldHistory = dibs.DeepCopy(dibs.Ledger.GetHistory(gm, priorSeason))
      local oldHash = dibs.Sync.CalculateContentHash(oldHistory)
      local preview = assert(dibs.SeasonalRoster.PreviewActivation(seasonId, gm))
      assert_true(preview.ready, preview.blockers[1] and preview.blockers[1].code)
      assert_equal(count, #preview.rows)
      assert_equal(priorSeason, dibs.GetCurrentSeasonId())
      local activated = dibs.SeasonalRoster.ActivateSeason(seasonId, preview.previewId, revision,
        "cohort-activate", "Activate reviewed participants", gm, true)
      assert_true(activated.ok, tostring(activated.code))
      assert_equal(seasonId, dibs.GetCurrentSeasonId())
      local manifest = assert(dibs.SeasonalRoster.GetActivationManifest(seasonId))
      local compactManifest = dibs.DeepCopy(manifest)
      compactManifest.identities, compactManifest.enrollments = {}, {}
      for _, reference in ipairs(manifest.identities) do
        compactManifest.identities[#compactManifest.identities + 1] = { reference.entityId, reference.contentHash }
      end
      for id, enrollmentRevision in pairs(manifest.enrollments) do
        compactManifest.enrollments[#compactManifest.enrollments + 1] = { id, enrollmentRevision }
      end
      local wireManifest = dibs.Sync._activationTransport.compactManifest(manifest)
      assert_true(#encode(wireManifest) <= 8192,
        "compact manifest wire payload must fit the unchanged transfer quota: " .. #encode(wireManifest))
      assert_equal(count, #manifest.identities)
      assert_equal("SEASON_IDENTITY", manifest.identities[1].entityType)
      assert_equal(1, manifest.identities[1].revision)
      assert_equal("identity:" .. seasonId .. ":" .. preview.identities[1].personGroupId,
        manifest.identities[1].entityId)
      assert_equal(dibs.SeasonalRoster.GetActivationIdentitySyncPayload(manifest.identities[1].entityId).contentHash,
        manifest.identities[1].contentHash)
      assert_equal(count, #dibs.Ledger.GetTransactions(seasonId))
      assert_equal(2, dibs.Ledger.GetBalance("Raider001-Realm", seasonId))
      assert_equal(0, dibs.Ledger.GetBalance("Inactive901-Realm", seasonId))
      assert_equal(oldHash, dibs.Sync.CalculateContentHash(dibs.Ledger.GetHistory(gm, priorSeason)))

      local spent = dibs.Ledger.CommitDibUse(nil, { transactionId = "cohort-spent-" .. count,
        playerName = "Raider001-Realm", seasonId = seasonId, amount = 1, source = "cohort test" })
      assert_true(spent.accepted, tostring(spent.reasonCode))
      assert_equal(1, dibs.Ledger.GetBalance("Raider001-Realm", seasonId))
      dibs.GetDB().rankRules[seasonId]["3"].allocation = 4
      local published = dibs.SeasonalRoster.PublishRankAllocations(seasonId, activated.revision,
        "cohort-update-ranks", "Review active-season rank allocation change", gm)
      assert_true(published.ok, tostring(published.code))
      local allocationCalls = 0
      local original = dibs.Ledger.GetPlayerAllocation
      dibs.Ledger.GetPlayerAllocation = function(...)
        allocationCalls = allocationCalls + 1
        return original(...)
      end
      local drift = assert(dibs.SeasonalRoster.PreviewSeasonReconciliation(seasonId, gm))
      dibs.Ledger.GetPlayerAllocation = original
      assert_true(drift.ready, drift.blockers[1] and drift.blockers[1].code)
      assert_equal(count, #drift.rows)
      assert_equal(count, allocationCalls, "reconciliation must not inspect allocations for unrelated guild members")
      for _, row in ipairs(drift.rows) do assert_equal(2, row.delta) end
      local expected = { seasonId = seasonId, seasonRevision = drift.seasonRevision,
        rosterRevision = drift.rosterRevision, sourceLedgerRevision = drift.sourceLedgerRevision }
      local reconciled = dibs.SeasonalRoster.ApplySeasonReconciliation(gm, drift.previewId, expected,
        "cohort-reconcile", "Apply reviewed allocation changes", true)
      assert_true(reconciled.ok, tostring(reconciled.code))
      assert_equal(count, reconciled.affectedCount)
      assert_equal(3, dibs.Ledger.GetBalance("Raider001-Realm", seasonId), "spent Dibs must stay spent")
      assert_equal(0, dibs.Ledger.GetBalance("Inactive901-Realm", seasonId))
      assert_equal(oldHash, dibs.Sync.CalculateContentHash(dibs.Ledger.GetHistory(gm, priorSeason)))
      local transactionCount = #dibs.Ledger.GetTransactions(seasonId)
      local replay = dibs.SeasonalRoster.ApplySeasonReconciliation(gm, drift.previewId, expected,
        "cohort-reconcile", "Apply reviewed allocation changes", true)
      assert_true(replay.ok, tostring(replay.code))
      assert_equal(transactionCount, #dibs.Ledger.GetTransactions(seasonId))
      assert_equal(manifest.contentHash, dibs.SeasonalRoster.GetActivationManifest(seasonId).contentHash)
    end)
  end

  it("refuses an oversized identity snapshot before publishing any activation state", function()
    local dibs, gm, seasonId, revision = setup(30)
    local preview = assert(dibs.SeasonalRoster.PreviewActivation(seasonId, gm))
    local before = dibs.Sync.CalculateContentHash(dibs.GetDB())
    local originalSerialize = dibs.Ace3.Serialize
    dibs.Ace3.Serialize = function(value)
      if type(value) == "table" and value.recordClass == "SEASON_IDENTITY" then
        return string.rep("x", 8193)
      end
      return originalSerialize(value)
    end
    local result = dibs.SeasonalRoster.ActivateSeason(seasonId, preview.previewId, revision,
      "oversized-identity", "Reject oversized identity payload", gm, true)
    dibs.Ace3.Serialize = originalSerialize
    assert_false(result.ok)
    assert_equal("SEASON_IDENTITY_TOO_LARGE", result.code)
    assert_equal(before, dibs.Sync.CalculateContentHash(dibs.GetDB()))
    assert_nil(dibs.SeasonalRoster.GetActivationManifest(seasonId))
  end)
end)
