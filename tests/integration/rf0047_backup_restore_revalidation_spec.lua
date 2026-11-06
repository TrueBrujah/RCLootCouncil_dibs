local loader = require("helpers.load_addon")

-- RF-0047 regression suite.
--
-- RF-0047 - "Backup : la validation d'instantane n'etait pas exercee
-- par le chemin de restauration" (docs/code-audit/INDEX.md#rf-0047).
--
-- The RF-0041 suite asserted only that `Backup.PreviewRestore` refuses a
-- damaged snapshot. It then called `Backup.Restore` with the literal
-- preview id `"none"`, so the restore returned `PREVIEW_NOT_FOUND` and
-- the assertion passed for the wrong reason. The restore's **own**
-- validation was therefore never executed: removing it left the whole
-- suite green (verified by controlled mutation).
--
-- The invariant this suite locks:
--   * `Backup.Restore` re-validates the snapshot it is about to apply,
--     independently of the preview that authorised it;
--   * a snapshot that is damaged **after** the preview was issued is
--     refused before any mutation;
--   * the live accounting state is untouched by the refusal;
--   * the refusal is reported with the validation diagnostic.
--
-- @AUDIT RF-0047 status=FIXED doc=docs/code-audit/INDEX.md#rf-0047

local function setup(options)
  options = options or {}
  local _, dibs = loader.load({ withAce3 = true, savedVariables = options.savedVariables or {}, wow = {
    playerName = "Tester-Realm", guildLeader = options.guildLeader ~= false,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = options.rank or 0, [2] = 1, [3] = 3 },
  } })
  return dibs
end

local function seedLegacyRow(dibs, transactionId, amount)
  local seasonId = dibs.GetCurrentSeasonId()
  local row = {
    transactionId = transactionId, type = "DIB_GRANTED", actionType = "DIB_GRANTED",
    playerName = "Player-Realm", memberKey = "player-realm", amount = amount,
    seasonId = seasonId, reason = "legacy row", source = "legacy", createdAt = 1700000000,
  }
  dibs.GetDB().ledgers["guild-primary"].transactions[transactionId] = row
  local states = dibs.GetDB().ledgers["guild-primary"].playerStates
  states[seasonId] = states[seasonId] or {}
  local key = "player-realm"
  states[seasonId][key] = states[seasonId][key] or { allocation = 0, balance = 0, transactions = {} }
  local state = states[seasonId][key]
  state.balance = (tonumber(state.balance) or 0) + amount
  state.transactions = state.transactions or {}
  state.transactions[#state.transactions + 1] = transactionId
  return row
end

local function accountingState(dibs)
  local seasonId = dibs.GetCurrentSeasonId()
  local ledger = dibs.GetDB().ledgers["guild-primary"]
  local count = 0
  for _ in pairs(ledger.transactions or {}) do count = count + 1 end
  return {
    balance = dibs.Ledger.GetBalance("Player-Realm", seasonId),
    transactionCount = count,
  }
end

local function assertAccountingUnchanged(dibs, before, message)
  local after = accountingState(dibs)
  assert_equal(before.balance, after.balance, message .. ": the balance changed")
  assert_equal(before.transactionCount, after.transactionCount, message .. ": the transaction count changed")
end

describe("RF-0047 Backup restore revalidation", function()
  it("D01 refuses a snapshot that was damaged after its preview was issued", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0047-row", 5)
    local snapshot = assert(dibs.Backup.Create("full", "D01 damaged after preview", "Tester-Realm"))
    -- The preview is issued while the snapshot is still intact.
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    -- The snapshot is then damaged, after the preview authorised it.
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    stored.payload = nil
    local before = accountingState(dibs)
    local applied, reason = dibs.Backup.Restore(preview.previewId, true, "D01", "Tester-Realm")
    assert_nil(applied, "a snapshot damaged after its preview was restored")
    assert_equal("SNAPSHOT_PAYLOAD_MISSING", reason)
    assertAccountingUnchanged(dibs, before, "D01")
  end)

  it("D02 refuses a snapshot whose package was corrupted after its preview", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0047-row-2", 5)
    local snapshot = assert(dibs.Backup.Create("full", "D02 corrupted after preview", "Tester-Realm"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    stored.packageText = stored.packageText:sub(1, #stored.packageText - 8) .. "CORRUPTED"
    local before = accountingState(dibs)
    local applied, reason = dibs.Backup.Restore(preview.previewId, true, "D02", "Tester-Realm")
    assert_nil(applied, "a corrupted snapshot was restored after its preview")
    assert_not_nil(reason)
    assertAccountingUnchanged(dibs, before, "D02")
  end)

  it("D03 refuses a snapshot of another guild that was previewed before the guild changed", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0047-row-3", 5)
    local snapshot = assert(dibs.Backup.Create("full", "D03 guild change", "Tester-Realm"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    stored.guildScope = "another-guild"
    local before = accountingState(dibs)
    local applied, reason = dibs.Backup.Restore(preview.previewId, true, "D03", "Tester-Realm")
    assert_nil(applied, "a cross-guild snapshot was restored after its preview")
    assert_equal("CROSS_GUILD_RESTORE_BLOCKED", reason)
    assertAccountingUnchanged(dibs, before, "D03")
  end)

  it("D04 refuses a snapshot whose payload was tampered with after its preview", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0047-row-4", 5)
    local snapshot = assert(dibs.Backup.Create("full", "D04 tampered after preview", "Tester-Realm"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    local row = stored.payload.ledgers["guild-primary"].transactions["rf0047-row-4"]
    row.amount = 9999
    row.reason = "TAMPERED"
    local before = accountingState(dibs)
    local applied, reason = dibs.Backup.Restore(preview.previewId, true, "D04", "Tester-Realm")
    assert_nil(applied, "a tampered payload was restored after its preview")
    assert_equal("SNAPSHOT_CHECKSUM_MISMATCH", reason)
    assertAccountingUnchanged(dibs, before, "D04")
  end)

  it("D05 still restores an intact snapshot that was previewed", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0047-row-5", 5)
    local snapshot = assert(dibs.Backup.Create("full", "D05 intact", "Tester-Realm"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local applied, reason = dibs.Backup.Restore(preview.previewId, true, "D05", "Tester-Realm")
    assert_not_nil(applied, "an intact snapshot was refused: " .. tostring(reason))
    assert_equal("confirmed", applied.decision)
  end)

  it("D06 refuses a damaged snapshot even when the preview is re-issued", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0047-row-6", 5)
    local snapshot = assert(dibs.Backup.Create("full", "D06 re-preview", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    stored.payload = nil
    local before = accountingState(dibs)
    local preview, previewReason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_nil(preview, "a damaged snapshot was previewed: " .. tostring(previewReason))
    local applied, reason = dibs.Backup.Restore("none", true, "D06", "Tester-Realm")
    assert_nil(applied, "a damaged snapshot was restored")
    assert_not_nil(reason)
    assertAccountingUnchanged(dibs, before, "D06")
  end)
end)
