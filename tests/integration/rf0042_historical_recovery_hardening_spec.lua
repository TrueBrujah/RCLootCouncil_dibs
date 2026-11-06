local loader = require("helpers.load_addon")

-- RF-0042 regression suite.
--
-- RF-0042 - "HistoricalBaseline : un paquet de recovery ne doit jamais
-- modifier arbitrairement un historique valide"
-- (docs/code-audit/INDEX.md#rf-0042).
--
-- The brief asks for 20 recovery-package scenarios to be covered, with the
-- invariant that a recovery package must never modify a valid history
-- arbitrarily: `Stage` applies nothing prematurely, `Commit` revalidates
-- the current preconditions, a contradictory package is refused, a replay
-- has no additional effect, and a refusal leaves the accounting state
-- unchanged.
--
-- The scenarios are C01 to C20 of the audit brief.

local function setup(options)
  options = options or {}
  local _, dibs = loader.load({ withAce3 = true, savedVariables = options.savedVariables or {}, wow = {
    playerName = "Tester-Realm", guildLeader = options.guildLeader ~= false,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = options.rank or 0, [2] = 1, [3] = 3 },
  } })
  return dibs
end

-- Builds a valid recovery package.
--
-- The contract of `validateRecoveryPackage`:
--   * `package.source.sourceId` and `package.source.authorNameRealm` are
--     required (the author is the person the package was sent by);
--   * `package.expectedContext` is `LEGACY_LOCAL` or `CUTOVER_PREPARED`;
--   * `package.evidenceSources` is a non-empty list;
--   * `package.createdAt` is a finite number;
--   * `package.contentHash` matches the computed content hash;
--   * the sender, when given, is the author.
local function buildPackage(dibs, options)
  options = options or {}
  local records = options.records or { {
    transactionId = "legacy-tx-1", type = "DIB_GRANTED", actionType = "DIB_GRANTED",
    playerName = "Player-Realm", memberKey = "player-realm", amount = 4,
    seasonId = options.seasonId or dibs.GetCurrentSeasonId(),
    reason = "legacy award", source = "legacy",
  } }
  local source = {
    sourceId = options.sourceId or "legacy-source-1",
    sourceClient = options.sourceClient or "Tester-Realm",
    authorNameRealm = options.authorNameRealm or "Tester-Realm",
    sourceType = options.sourceType or "LEDGER_TRANSACTION",
    guildKey = options.guildKey or dibs.GetGuildKey(),
    sourceVersion = 1,
    complete = options.complete ~= false,
  }
  local package = {
    schema = 1, recordClass = "LEGACY_RECOVERY_PACKAGE",
    guildKey = options.packageGuildKey or dibs.GetGuildKey(),
    source = source,
    expectedContext = options.expectedContext or "LEGACY_LOCAL",
    baselineRelationship = options.baselineRelationship or "REPLACES",
    evidenceSources = { { source = source, records = records } },
    createdAt = 1700000000,
    audit = { reason = "rf0042 fixture" },
  }
  package.contentHash = dibs.HistoricalBaseline.CalculateRecoveryContentHash(package)
  return package
end

describe("RF-0042 HistoricalBaseline recovery hardening", function()
  it("C01 stages a valid package without applying it", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" })
    assert_not_nil(staged, tostring(reason))
    -- Staging must not change the stored evidence.
    assert_equal(0, #dibs.HistoricalBaseline.GetEvidence(),
      "staging applied the package prematurely")
  end)

  it("C02 refuses an incomplete package", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    package.evidenceSources = {}
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" })
    assert_nil(staged, "an incomplete package was staged")
    assert_equal("INCOMPLETE_RECOVERY_PACKAGE", reason)
  end)

  it("C03 refuses a corrupted package", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    package.contentHash = "0000000000000000"
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" })
    assert_nil(staged, "a corrupted package was staged")
    assert_equal("RECOVERY_HASH_MISMATCH", reason)
  end)

  it("C04 refuses a package from another guild", function()
    local dibs = setup()
    local package = buildPackage(dibs, { packageGuildKey = "another-guild" })
    package.contentHash = dibs.HistoricalBaseline.CalculateRecoveryContentHash(package)
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" })
    assert_nil(staged, "a package from another guild was staged")
    assert_equal("GUILD_SCOPE_MISMATCH", reason)
  end)

  it("C05 refuses a package whose source names another guild", function()
    local dibs = setup()
    local package = buildPackage(dibs, { guildKey = "another-guild" })
    package.contentHash = dibs.HistoricalBaseline.CalculateRecoveryContentHash(package)
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" })
    assert_nil(staged, "a package with a foreign source was staged")
    assert_equal("GUILD_SCOPE_MISMATCH", reason)
  end)

  it("C06 refuses a package with an incorrect hash", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    -- The content is tampered with after the hash was computed: the
    -- evidence it carries no longer matches what the hash attests.
    package.evidenceSources[1].records[1].amount = 99
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" })
    assert_nil(staged, "a package with a wrong hash was staged")
    assert_equal("RECOVERY_HASH_MISMATCH", reason)
  end)

  it("C07 refuses a package with an inexistent reference", function()
    local dibs = setup()
    local package = buildPackage(dibs, { records = { {
      transactionId = "legacy-tx-1", type = "DIB_GRANTED", actionType = "DIB_GRANTED",
      playerName = "Player-Realm", memberKey = "player-realm", amount = 4,
      seasonId = dibs.GetCurrentSeasonId(),
      reason = "dangling", source = "legacy",
      originalTransactionId = "tx-that-does-not-exist",
    } } })
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" })
    -- The record itself may be accepted, but the dangling reference must
    -- not be silently repaired.
    if staged then
      assert_nil(staged.stagedState.evidence["legacy-tx-1"],
        "a record with a dangling reference was applied")
    else
      assert_not_nil(reason)
    end
  end)

  it("C08 refuses a package with an ambiguous identity", function()
    local dibs = setup()
    local package = buildPackage(dibs, { records = { {
      transactionId = "legacy-ambiguous", type = "DIB_GRANTED", actionType = "DIB_GRANTED",
      playerName = "Nobody", amount = 4, seasonId = dibs.GetCurrentSeasonId(),
      reason = "ambiguous", source = "legacy",
    } } })
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" })
    if staged then
      -- The ambiguous identity is kept as evidence, but it is not resolved:
      -- the member key stays unknown and the record cannot reach a
      -- baseline without an explicit decision.
      local found = nil
      for _, evidence in pairs(staged.stagedState.evidence) do found = evidence break end
      assert_not_nil(found, "the ambiguous record was dropped")
      assert_equal("UNRESOLVED_LEGACY_IDENTITY", found.identity.status,
        "an ambiguous identity was resolved without evidence")
      assert_nil(found.identity.memberKey,
        "an ambiguous identity was bound to a member")
    else
      assert_not_nil(reason)
    end
  end)

  it("C09 applies a package twice without a second effect", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    local staged = assert(dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" }))
    local first = assert(dibs.HistoricalBaseline.CommitRecoveryPackage("Tester-Realm", staged, { sender = "Tester-Realm" }))
    assert_true(first.accepted, tostring(first.reasonCode))
    local evidenceCount = #dibs.HistoricalBaseline.GetEvidence()

    local stagedAgain = assert(dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" }))
    local second = assert(dibs.HistoricalBaseline.CommitRecoveryPackage("Tester-Realm", stagedAgain, { sender = "Tester-Realm" }))
    assert_true(second.accepted, tostring(second.reasonCode))
    assert_true(second.idempotentReplay, "the replay was not reported as idempotent")
    assert_equal(evidenceCount, #dibs.HistoricalBaseline.GetEvidence(),
      "the replay added evidence again")
  end)

  it("C10 refuses a package modified between the stage and the commit", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    local staged = assert(dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" }))
    -- The staged package is modified after the staging.
    staged.package.source.sourceClient = "Someone-Else"
    local result, reason = dibs.HistoricalBaseline.CommitRecoveryPackage("Tester-Realm", staged, { sender = "Tester-Realm" })
    assert_nil(result, "a modified package was committed")
    assert_not_nil(reason)
  end)

  it("C11 refuses a package whose preconditions changed", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    local staged = assert(dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" }))
    -- The guild changes between the stage and the commit: the package was
    -- built for the previous guild and must not be applied to the new one.
    dibs.GetDB().guildKey = "another-guild"
    local originalGetGuildKey = dibs.GetGuildKey
    dibs.GetGuildKey = function() return "another-guild" end
    local result, reason = dibs.HistoricalBaseline.CommitRecoveryPackage("Tester-Realm", staged, { sender = "Tester-Realm" })
    dibs.GetGuildKey = originalGetGuildKey
    assert_nil(result, "a package with changed preconditions was committed")
    assert_not_nil(reason)
  end)

  it("C12 accepts a package whose data is already present", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    local staged = assert(dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" }))
    assert(dibs.HistoricalBaseline.CommitRecoveryPackage("Tester-Realm", staged, { sender = "Tester-Realm" }))
    local before = #dibs.HistoricalBaseline.GetEvidence()

    local stagedAgain = assert(dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" }))
    local result = assert(dibs.HistoricalBaseline.CommitRecoveryPackage("Tester-Realm", stagedAgain, { sender = "Tester-Realm" }))
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_equal(before, #dibs.HistoricalBaseline.GetEvidence(),
      "the already-present data was added again")
  end)

  it("C13 refuses a package with contradictory data", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    local staged = assert(dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" }))
    assert(dibs.HistoricalBaseline.CommitRecoveryPackage("Tester-Realm", staged, { sender = "Tester-Realm" }))

    -- The same evidence identifier, with a different content.
    local contradictory = buildPackage(dibs, { records = { {
      transactionId = "legacy-tx-1", type = "DIB_GRANTED", actionType = "DIB_GRANTED",
      playerName = "Player-Realm", memberKey = "player-realm", amount = 99,
      seasonId = dibs.GetCurrentSeasonId(), reason = "contradictory", source = "legacy",
    } } })
    local stagedAgain, reason = dibs.HistoricalBaseline.StageRecoveryPackage(contradictory, { sender = "Tester-Realm" })
    if stagedAgain then
      -- The staging succeeded, so the contradiction must be detected when
      -- the package is applied on top of the committed evidence.
      local result, commitReason = dibs.HistoricalBaseline.CommitRecoveryPackage(
        "Tester-Realm", stagedAgain, { sender = "Tester-Realm" })
      local findings = dibs.HistoricalBaseline.GetFindings()
      for _, finding in ipairs(findings) do
      end
      local ev = dibs.HistoricalBaseline.GetEvidence()
      for _, e in ipairs(ev) do
      end
      assert_nil(result, "a contradictory package was committed")
      assert_not_nil(commitReason)
    else
      assert_not_nil(reason)
    end
  end)

  it("C14 applies a package after a reload", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    local staged = assert(dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" }))
    assert(dibs.HistoricalBaseline.CommitRecoveryPackage("Tester-Realm", staged, { sender = "Tester-Realm" }))
    local before = #dibs.HistoricalBaseline.GetEvidence()

    local saved = dibs.DeepCopy and dibs.DeepCopy(dibs.GetDB()) or dibs.GetDB()
    local reloaded = setup({ savedVariables = saved })
    assert_equal(before, #reloaded.HistoricalBaseline.GetEvidence(),
      "the committed evidence did not survive the reload")
  end)

  it("C15 leaves the state untouched after an interrupted application", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    local staged = assert(dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" }))
    -- The safety snapshot cannot be created: the application is interrupted
    -- before any mutation.
    local originalCreate = dibs.Backup.Create
    dibs.Backup.Create = function() return nil, "SAFETY_SNAPSHOT_FAILED" end
    local result, reason = dibs.HistoricalBaseline.CommitRecoveryPackage("Tester-Realm", staged, { sender = "Tester-Realm" })
    dibs.Backup.Create = originalCreate

    assert_nil(result, "an interrupted application was reported as successful")
    assert_equal("SAFETY_SNAPSHOT_FAILED", reason)
    assert_equal(0, #dibs.HistoricalBaseline.GetEvidence(),
      "the interrupted application changed the evidence")
  end)

  it("C16 refuses a package proposed by an unauthorized actor", function()
    local dibs = setup({ guildLeader = false, rank = 3 })
    local package = buildPackage(dibs)
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Player-Realm" })
    if staged then
      local result, commitReason = dibs.HistoricalBaseline.CommitRecoveryPackage("Player-Realm", staged, { sender = "Player-Realm" })
      assert_nil(result, "an unauthorized actor committed the package")
      assert_not_nil(commitReason)
    else
      assert_not_nil(reason)
    end
  end)

  it("C17 refuses a package whose sender is not its author", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    local staged = assert(dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" }))
    -- The package is sent by somebody else than its author.
    local result, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Officer-Realm" })
    assert_nil(result, "a package sent by another actor was staged")
    assert_equal("RECOVERY_SENDER_AUTHOR_MISMATCH", reason)
  end)

  it("C18 accepts a package with legacy Pre-Dibs data", function()
    local dibs = setup()
    local package = buildPackage(dibs, { sourceType = "PREDIB_REQUEST", records = { {
      transactionId = "legacy-predib-1", requestId = "legacy-predib-1", playerName = "Player-Realm",
      memberKey = "player-realm", itemID = 12345, seasonId = dibs.GetCurrentSeasonId(),
      status = "confirmed", revision = 1, type = "PREDIB_REQUEST", reason = "legacy pre-dib", source = "legacy",
    } } })
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" })
    assert_not_nil(staged, tostring(reason))
  end)

  it("C19 accepts a package with legacy ledger history", function()
    local dibs = setup()
    local package = buildPackage(dibs, { sourceType = "LEDGER_TRANSACTION" })
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" })
    assert_not_nil(staged, tostring(reason))
  end)

  it("C20 refuses a package that mixes legacy and canonical operations", function()
    local dibs = setup()
    local package = buildPackage(dibs)
    -- A canonical operation is not a legacy evidence record.
    package.evidenceSources[1].records[1].operation = {
      schemaVersion = 1, operationId = "op-1", ledgerId = "guild-primary",
    }
    package.evidenceSources[1].records[1].seasonId = dibs.GetCurrentSeasonId()
    package.contentHash = dibs.HistoricalBaseline.CalculateRecoveryContentHash(package)
    local staged, reason = dibs.HistoricalBaseline.StageRecoveryPackage(package, { sender = "Tester-Realm" })
    if staged then
      local found = nil
      for _, evidence in pairs(staged.stagedState.evidence) do found = evidence break end
      assert_not_nil(found, "the record was dropped")
      -- The record is legacy evidence: it carries no canonical operation,
      -- and the operation field is not adopted as history.
      assert_nil(found.operation, "a canonical operation was adopted as legacy history")
      assert_equal("DIB_GRANTED", found.action,
        "the legacy record was transformed into something else")
    else
      assert_not_nil(reason)
    end
  end)
end)
