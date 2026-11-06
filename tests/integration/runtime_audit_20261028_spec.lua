local loader = require("helpers.load_addon")

local function setup(player)
  player = player or "Tester-Realm"
  local _, dibs = loader.load({ savedVariables = {}, withAce3 = true, wow = {
    playerName = player, guildLeader = player == "Tester-Realm",
    guildMembers = { "Tester-Realm", "Officer-Realm", "Owner-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
  } })
  return dibs
end

local function remote(dibs, message)
  local envelope = assert(dibs.Sync.BuildEnvelope(message))
  envelope.senderNameRealm, envelope.senderMemberKey = "Owner-Realm", "owner-realm"
  return envelope
end

local function receive(dibs, message, channel)
  return dibs.Sync.OnAddonMessage("DIBS", assert(dibs.Ace3.Serialize(message)), channel or "GUILD", "Owner-Realm")
end

local function count(map)
  local result = 0
  for _ in pairs(map or {}) do result = result + 1 end
  return result
end

local function pack(dibs, package)
  package.checksum = nil
  local unsigned = assert(dibs.ImportExport.Encode(package))
  package.checksum = dibs.ImportExport.Checksum(unsigned:sub(#dibs.ImportExport.PACKAGE_PREFIX + 1))
  return assert(dibs.ImportExport.Encode(package))
end

describe("Runtime audit 2026-10-28: load and evidence controls", function()
  it("exercises the V2 functions actually selected by the TOC", function()
    local dibs = setup()
    for _, name in ipairs({ "Send", "Receive", "OnAddonMessage", "RegisterTransport", "OnRosterChanged", "BuildManifest" }) do
      local source = debug.getinfo(dibs.Sync[name], "S").source
      assert_true(source:find("modules/SyncV2.lua", 1, true) ~= nil, name .. " comes from " .. source)
    end
    assert_true(debug.getinfo(dibs.Sync.ContainsForbiddenLiveLootData, "S").source:find("modules/Sync.lua", 1, true) ~= nil)
    local accepted, reason = dibs.Sync.OnAddonMessage("DIBS", "DIBS1:HELLO", "GUILD", "Owner-Realm")
    assert_false(accepted)
    assert_equal("PROTOCOL_LEGACY_READ_ONLY", reason)
    dibs.Ace3.libs.comm = nil
    local sent, sendReason = dibs.Sync.Send({ type = "HELLO" }, "GUILD")
    assert_false(sent)
    assert_equal("SYNC_UNAVAILABLE", sendReason)
    assert_equal(0, #_G.__sentAddonMessages)
  end)

  it("distinguishes a stale checksum from the foreign-guild check", function()
    local dibs = setup()
    local _, package = dibs.ImportExport.Export("full")
    package.sourceGuild = "audit-foreign-guild"
    local _, staleReason = dibs.ImportExport.Decode(assert(dibs.ImportExport.Encode(package)))
    assert_equal("CHECKSUM_MISMATCH", staleReason)
    local encoded = pack(dibs, package)
    assert_not_nil(dibs.ImportExport.Decode(encoded))
    local preview, reason = dibs.ImportExport.Preview(encoded, "full", "merge")
    assert_nil(preview)
    assert_equal("CROSS_GUILD_FULL_BLOCKED", reason)
  end)

  it("rejects real non-officer ledger writes and forged officer actor identities", function()
    local dibs = setup("Owner-Realm")
    local before = #dibs.Ledger.GetAllTransactions()
    local value, reason = dibs.Ledger.Grant("Owner-Realm", 5, "audit")
    assert_nil(value)
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
    local forged = dibs.ProtectedActions.Execute("ledger.grant", "Officer-Realm", {
      playerName = "Owner-Realm", amount = 5, reason = "audit forged actor",
    })
    assert_false(forged.ok)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)
end)

describe("Runtime audit 2026-10-28: pending regression contracts", function()
  it("initializes core services on PLAYER_LOGIN without the loader's manual Initialize call", function()
    local _, dibs = loader.load({ savedVariables = {}, withAce3 = true, skipInitialize = true,
      wow = { guildLeader = true } })
    assert_nil(dibs.initialized)
    local callback = assert(dibs.Ace3.libs.event.handlers.PLAYER_LOGIN)
    callback("PLAYER_LOGIN")
    assert_true(dibs.initialized == true, "the later EncounterJournal listener replaced the Core PLAYER_LOGIN handler")
  end)

  it("delivers a shared adapter event to every registered consumer", function()
    local dibs = setup()
    local first, second = 0, 0
    dibs.Ace3.RegisterEvent("DIBS_AUDIT_EVENT", function() first = first + 1 end)
    dibs.Ace3.RegisterEvent("DIBS_AUDIT_EVENT", function() second = second + 1 end)
    dibs.Ace3.libs.event.handlers.DIBS_AUDIT_EVENT("DIBS_AUDIT_EVENT")
    assert_equal(1, first, "a later event consumer silently displaced the first listener")
    assert_equal(1, second)
  end)

  it("passes the AceEvent encounter arguments in the order expected by EncounterJournal", function()
    local dibs = setup()
    dibs.Ace3.libs.event.handlers.ENCOUNTER_START("ENCOUNTER_START", 1234, "Audit encounter", 16, 20)
    local active = dibs.EncounterJournal.GetActiveEncounter()
    assert_not_nil(active, "the adapter dropped/misaligned the encounter event")
    assert_equal(1234, active.encounterID)
    dibs.Ace3.libs.event.handlers.ENCOUNTER_END("ENCOUNTER_END", 1234, "Audit encounter", 16, 20, 1)
    assert_nil(dibs.EncounterJournal.GetActiveEncounter())
  end)

  it("ignores unrelated addon load events before core initialization", function()
    local _, dibs = loader.load({ savedVariables = {}, withAce3 = true, skipInitialize = true,
      wow = { guildLeader = true } })
    local attempts = 0
    dibs.EncounterJournal.AddActionIfAvailable = function() attempts = attempts + 1 end
    dibs.Ace3.libs.event.handlers.ADDON_LOADED("ADDON_LOADED", "Audit_Unrelated_Addon")
    assert_equal(0, attempts, "an unrelated addon load retriggered the EncounterJournal bootstrap")
  end)

  it("revalidates the current snapshot payload after a local restore preview", function()
    local dibs = setup()
    local db = dibs.GetDB()
    db.settings.theme = "saved-theme"
    local snapshot = assert(dibs.Backup.Create("local", "audit snapshot checksum"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId))
    db.settings.theme = "live-theme"
    dibs.Backup.Get(snapshot.snapshotId).payload.presentation.theme = "tampered-theme"
    local result = dibs.Backup.Restore(preview.previewId, true, "audit tampered snapshot")
    print("AUDIT local-restore applied=" .. tostring(result ~= nil) .. " theme=" .. tostring(db.settings.theme))
    assert_nil(result, "a checksum-invalid snapshot was restored")
    assert_equal("live-theme", db.settings.theme)
  end)

  it("releases cancelled full-import packages instead of retaining each complete copy", function()
    local dibs = setup()
    local encoded = assert(dibs.ImportExport.Export("full"))
    for index = 1, 3 do
      local preview = assert(dibs.ImportExport.Preview(encoded, "full", "merge"))
      assert_not_nil(dibs.ImportExport.Apply(preview.previewId, false, "audit cancelled import"))
    end
    local retained = count(dibs.GetDB().pendingImports)
    print("AUDIT cancelled-import retained-packages=" .. retained)
    assert_equal(0, retained, "cancelled imports retain their full package payload indefinitely")
  end)

  it("does not retain a pruned snapshot through a cancelled restore preview", function()
    local dibs = setup()
    dibs.GetDB().backupRetention = 1
    local snapshot = assert(dibs.Backup.Create("local", "audit first"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId))
    assert_not_nil(dibs.Backup.Restore(preview.previewId, false, "audit cancel"))
    assert_not_nil(dibs.Backup.Create("local", "audit second"))
    assert_nil(dibs.Backup.Get(snapshot.snapshotId))
    local retained = count(dibs.GetDB().pendingRestores)
    print("AUDIT cancelled-restore listed-snapshots=1 retained-preview-snapshots=" .. retained)
    assert_equal(0, retained, "a cancelled preview still pins a snapshot removed by retention")
  end)

  it("rejects invalid digest entities without retaining an unbounded entity cache", function()
    local dibs = setup()
    for index = 1, 20 do
      local message = remote(dibs, { type = "DIGEST", entityType = "AUDIT_INVALID_" .. index,
        revision = index, contentHash = "audit-hash-" .. index })
      local accepted, reason = receive(dibs, message)
      assert_false(accepted)
      assert_equal("INVALID_DIGEST", reason)
    end
    local peer = dibs.GetDB().sync.v2.peers["owner-realm"]
    local retained = count(peer and peer.entities)
    print("AUDIT invalid-digest retained-entities=" .. retained)
    assert_equal(0, retained, "rejected guild packets persist arbitrary entity keys")
  end)

  it("rejects an oversized outer packet before invoking the deserializer", function()
    local dibs = setup()
    local calls = 0
    dibs.Ace3.Deserialize = function()
      calls = calls + 1
      return nil
    end
    local accepted = dibs.Sync.OnAddonMessage("DIBS", string.rep("x", 1024 * 1024), "GUILD", "Owner-Realm")
    assert_false(accepted)
    print("AUDIT oversized-packet deserialize-calls=" .. calls)
    assert_equal(0, calls, "one-megabyte input reached the deserializer before an application size guard")
  end)

  it("processes a secondary-ledger digest without copying the ledger for every request", function()
    local dibs = setup()
    local db, ledgerId = dibs.GetDB(), "audit-secondary"
    local ledger = { id = ledgerId, name = "Audit secondary", status = "APPROVED",
      transactions = {}, playerStates = {}, awardTransactions = {}, evidenceTransactions = {} }
    for index = 1, 100 do ledger.transactions["tx-" .. index] = { amount = 1, reason = "synthetic" } end
    db.ledgers[ledgerId] = ledger
    local approved = dibs.Governance.IsLedgerApproved
    dibs.Governance.IsLedgerApproved = function(id)
      return id == ledgerId or approved(id)
    end
    local history = assert(dibs.PreDibs.GetHistory(ledgerId))
    for index = 1, 20 do
      history[index] = { requestId = "audit-request-" .. index, ledgerId = ledgerId,
        revision = 1, playerName = "Owner-Realm", status = "confirmed", itemID = 21101,
        seasonId = dibs.GetCurrentSeasonId(), createdAt = index, updatedAt = index }
    end
    local message = remote(dibs, assert(dibs.Sync.BuildManifest(ledgerId)))
    local copies, originalCopy = 0, dibs.DeepCopy
    dibs.DeepCopy = function(value, ...)
      if value == ledger then copies = copies + 1 end
      return originalCopy(value, ...)
    end
    local accepted, reason = receive(dibs, message)
    dibs.DeepCopy = originalCopy
    assert_true(accepted, tostring(reason))
    assert_equal("DIGEST_CURRENT", reason)
    print("AUDIT secondary-digest requests=20 transactions=100 full-ledger-copies=" .. copies)
    assert_true(copies <= 2, "digest performed " .. copies .. " full-ledger copies for 20 current requests")
  end)

  it("excludes recovery subtrees before requesting a full-database copy", function()
    local dibs = setup()
    local db = dibs.GetDB()
    db.backups = { { snapshotId = "audit-snapshot", scope = "full", payload = { rows = {} } } }
    for index = 1, 100 do db.backups[1].payload.rows[index] = { id = index } end
    local copies, originalCopy = 0, dibs.DeepCopy
    dibs.DeepCopy = function(value, ...)
      if value == db then copies = copies + 1 end
      return originalCopy(value, ...)
    end
    local payload = dibs.ImportExport.GetPayload("full")
    dibs.DeepCopy = originalCopy
    assert_nil(payload.backups)
    print("AUDIT full-export full-database-copy-inputs=" .. copies)
    assert_equal(0, copies, "GetPayload copied backups and pending data before discarding them")
  end)

  it("reads health backup metadata without copying all snapshot payloads", function()
    local dibs = setup()
    local db = dibs.GetDB()
    local snapshots = {}
    for index = 1, 3 do
      local snapshot = { snapshotId = "audit-snapshot-" .. index, scope = "full",
        createdAt = index, payload = { rows = {} } }
      for row = 1, 40 do snapshot.payload.rows[row] = { id = row } end
      snapshots[snapshot] = true
      db.backups[index] = snapshot
    end
    local copies, originalCopy = 0, dibs.DeepCopy
    dibs.DeepCopy = function(value, ...)
      if snapshots[value] then copies = copies + 1 end
      return originalCopy(value, ...)
    end
    local report = dibs.HealthUI.Evaluate()
    dibs.DeepCopy = originalCopy
    assert_equal(3, report.backup.count)
    print("AUDIT health-report full-snapshot-copies=" .. copies)
    assert_equal(0, copies, "health metadata query copied every full recovery payload")
  end)

  it("builds the administration roster with the Retail-style absence of io", function()
    local dibs = setup()
    local savedIO = _G.io
    _G.io = nil
    local ok, result = pcall(dibs.OfficerUI.BuildDibsAdministrationRoster, dibs.GetCurrentSeasonId(), "")
    _G.io = savedIO
    assert_true(ok, "administration roster raised without io: " .. tostring(result))
    assert_not_nil(result.rows)
  end)
end)
