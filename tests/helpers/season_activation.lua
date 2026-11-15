local loader = require("helpers.load_addon")
local F = require("helpers.seasonal_roster_fixtures")
local Helper = {}
Helper.members = { "GameMaster-Realm", "Officer-Realm", "Player-Realm" }
Helper.ranks = { [1] = 0, [2] = 1, [3] = 3 }
function Helper.load(player, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player or Helper.members[1], guildLeader = player == nil or player == Helper.members[1],
    guildMembers = Helper.members, guildRankIndices = Helper.ranks } }))
end
function Helper.make(linked, withEnd)
  local dibs = Helper.load()
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "activation service test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
    { allowPublicPreDibs = true, preDibModes = {} }, "activation service test"))
  assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil, "enable test"))
  local baseline = assert(dibs.HistoricalBaseline.FinalizeBaseline(nil))
  assert_true(dibs.Governance.Change(nil, { future = { authority = {
    schema = 1, state = "ACTIVE", coordinator = assert(dibs.Identity.CreateSnapshot(Helper.members[1])),
    ledgerEpoch = 7, transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash } } } }))
  assert_true(dibs.Governance.EnableV2(nil, { Helper.members[1] }))
  local old = assert(dibs.Seasons.Create("Prior season")).id
  assert_not_nil(dibs.Ledger.Grant(Helper.members[1], 5, "Prior balance", "test", old))
  local timestamp = dibs.GetTimestamp()
  local created = dibs.SeasonalRoster.CreateSeason({ name = "Activation service", startAt = timestamp + 1000,
    endAt = withEnd and timestamp + 2000 or nil,
    registrationStartAt = timestamp - 100 }, "service-create", Helper.members[1])
  assert_true(created.ok, created.code)
  local id = created.value
  if linked then
    local link = dibs.SeasonalRoster.DeclareRelationship(id,
      { mainCharacter = Helper.members[1], altCharacter = Helper.members[3] }, 0, "service-declare")
    assert_true(link.ok, link.code)
    local reviewed = dibs.SeasonalRoster.ReviewRelationship(id, link.value, "approved", link.revision,
      "service-link-review", "Known alternate", Helper.members[1])
    assert_true(reviewed.ok, reviewed.code)
  end
  local opened = dibs.SeasonalRoster.SetRegistrationState(id, "OPEN", created.revision,
    "service-open", "Open test season", Helper.members[1])
  assert_true(opened.ok, opened.code)
  local enrolled = dibs.SeasonalRoster.UpsertOwnEnrollment(id, F.enrollment({ character = Helper.members[1] }), 0, "service-signup")
  assert_true(enrolled.ok, enrolled.code)
  assert_true(dibs.SeasonalRoster.AdminUpdateEnrollment(id, enrolled.value, { status = "ACTIVE" }, enrolled.revision,
    "Reviewed signup", "service-approve", Helper.members[1]).ok)
  local closed = dibs.SeasonalRoster.SetRegistrationState(id, "CLOSED", opened.revision,
    "service-close", "Close test season", Helper.members[1])
  assert_true(closed.ok, closed.code)
  dibs.GetDB().rankRules[id] = { ["0"] = { rankIndex = 0, rankName = "Guild Master", allocation = 3, enabled = true } }
  local published = dibs.SeasonalRoster.PublishRankAllocations(id, closed.revision,
    "service-publish", "Initial allocation rules", Helper.members[1])
  assert_true(published.ok, published.code)
  return dibs, id, old, published.revision
end
function Helper.activate(dibs, id, op)
  local preview = assert(dibs.SeasonalRoster.PreviewActivation(id, Helper.members[1]))
  assert_true(preview.ready)
  local result = dibs.SeasonalRoster.ActivateSeason(id, preview.previewId, preview.seasonRevision,
    op or "service-activate", "Activate reviewed roster", Helper.members[1], true)
  assert_true(result.ok, result.code)
  return result, preview
end
return Helper
