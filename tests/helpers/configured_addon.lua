local loader = require("helpers.load_addon")
local M = {}

-- Opt-in fixture for post-setup rendering tests. The default loader remains a
-- real fresh installation; accounting and progressive-navigation suites use it.
function M.foundation(dibs)
  if not dibs.Governance.GetCurrentRecord() then
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "Post-setup UI fixture",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
  end
  if not dibs.HistoricalBaseline.GetBaseline() then
    local baseline, reason = dibs.HistoricalBaseline.FinalizeBaseline(nil)
    assert_not_nil(baseline, tostring(reason))
  end
  return dibs
end

function M.configure(dibs)
  local access = dibs.Wizard.GetNavigationAccess()
  if access.foundationReady and access.dependencies.ranksPublished then return dibs end
  M.foundation(dibs)
  local season = dibs.Seasons.GetCurrent()
  local result = dibs.ProtectedActions.Execute("rank.set", nil, {
    seasonId = season.id, rankIndex = 0, rankName = "Guild Master", allocation = 10, enabled = true,
  })
  assert_true(result.ok, tostring(result.code or result.reasonCode))
  assert_true(dibs.Wizard.GetNavigationAccess().dependencies.ranksPublished)
  return dibs
end

function M.load(options)
  options = options or {}
  if options.wow and options.wow.guildLeader == false then
    -- Prepare the guild as its verified GM, then reload as the subject. The
    -- subject never acquires GM permissions or writes configuration itself.
    local preparation = {}
    for key, value in pairs(options) do preparation[key] = value end
    local roster, ranks, gm = {}, {}, nil
    for index, name in ipairs(options.wow.guildMembers or { options.wow.playerName or "Tester-Realm" }) do
      roster[index], ranks[index] = name, (options.wow.guildRankIndices or {})[index] or 3
      if ranks[index] == 0 then gm = name end
    end
    if not gm then gm = "FixtureGM-Realm"; roster[#roster + 1], ranks[#roster + 1] = gm, 0 end
    preparation.wow = {}
    for key, value in pairs(options.wow) do preparation.wow[key] = value end
    preparation.wow.guildMembers, preparation.wow.guildRankIndices = roster, ranks
    preparation.wow.playerName, preparation.wow.guildLeader = gm, true
    local _, prepared = loader.load(preparation)
    M.configure(prepared)
    local subject = {}
    for key, value in pairs(options) do subject[key] = value end
    subject.savedVariables = prepared.DeepCopy(prepared.GetDB())
    subject.wow = {}
    for key, value in pairs(options.wow) do subject.wow[key] = value end
    subject.wow.guildMembers, subject.wow.guildRankIndices = roster, ranks
    return loader.load(subject)
  end
  local rc, dibs = loader.load(options)
  M.configure(dibs)
  return rc, dibs
end

return setmetatable(M, { __index = loader })
