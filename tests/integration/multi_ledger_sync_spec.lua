local loader = require("helpers.load_addon")

local roster = { "GameMaster-Realm", "Officer-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = player == "GameMaster-Realm", guildMembers = roster, guildRankIndices = ranks,
  } }))
end

local function remote(dibs, message, sender)
  local envelope = assert(dibs.Sync.BuildEnvelope(message))
  envelope.senderNameRealm, envelope.senderMemberKey = sender, string.lower(sender)
  return envelope
end

describe("Multi-Ledger synchronization", function()
  it("replicates approved ledger catalog to guild peers via LEDGER_CATALOG digest", function()
    local gm = load("GameMaster-Realm")
    local prop = gm.MultiLedger.ProposeLedger("GameMaster-Realm", "Alt Raid")
    assert_true(prop.ok)
    local app = gm.MultiLedger.ApproveLedger("GameMaster-Realm", prop.ledgerId)
    assert_true(app.ok)

    local catalogDigest = gm.Sync.BuildLedgerCatalogDigest()
    assert_not_nil(catalogDigest)
    assert_equal("DIGEST", catalogDigest.type)
    assert_equal("LEDGER_CATALOG", catalogDigest.entityType)
    assert_not_nil(catalogDigest.ledgers[prop.ledgerId])
    assert_equal("APPROVED", catalogDigest.ledgers[prop.ledgerId].status)

    -- Now a normal guild member receives the catalog digest
    local member = load("Player-Realm")
    assert_equal(1, #member.MultiLedger.GetLedgers()) -- only guild-primary initially

    local ok, reason = member.Sync.Receive(remote(member, catalogDigest, "GameMaster-Realm"), "GameMaster-Realm")
    assert_true(ok)
    assert_equal("LEDGER_CATALOG_SYNCED", reason)

    -- Member should now have the approved Alt Raid ledger
    local memberLedgers = member.MultiLedger.GetLedgers()
    assert_equal(2, #memberLedgers)
    local found = nil
    for _, l in ipairs(memberLedgers) do
      if l.id == prop.ledgerId then found = l end
    end
    assert_not_nil(found)
    assert_equal("Alt Raid", found.name)
    assert_equal("APPROVED", found.status)
  end)

  it("rejects LEDGER_CATALOG digest sent by an unauthorized non-admin player", function()
    local member = load("Player-Realm")
    local fakeDigest = {
      type = "DIGEST",
      entityType = "LEDGER_CATALOG",
      revision = 1,
      contentHash = "FAKE",
      ledgers = {
        ["fake-ledger"] = { id = "fake-ledger", name = "Fake", status = "APPROVED" }
      }
    }

    local ok, reason = member.Sync.Receive(remote(member, fakeDigest, "Player-Realm"), "Player-Realm")
    assert_false(ok)
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
    assert_equal(1, #member.MultiLedger.GetLedgers())
  end)

  it("accepts an idempotent GM deletion tombstone for an archived ledger", function()
    local gm = load("GameMaster-Realm")
    local prop = gm.MultiLedger.ProposeLedger("GameMaster-Realm", "Retired Team")
    assert_true(prop.ok)
    assert_true(gm.MultiLedger.ApproveLedger("GameMaster-Realm", prop.ledgerId).ok)
    assert_true(gm.MultiLedger.ArchiveLedger("GameMaster-Realm", prop.ledgerId).ok)

    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local member = load("Player-Realm", saved)
    local message = remote(member, {
      type = "LEDGER_DELETE",
      ledgerId = prop.ledgerId,
      deletedBy = "GameMaster-Realm",
      timestamp = 1700000000,
    }, "GameMaster-Realm")
    local ok, reason = member.Sync.Receive(message, "GameMaster-Realm")
    assert_true(ok)
    assert_equal("LEDGER_DELETED", reason)
    assert_nil(member.GetDB().ledgers[prop.ledgerId])
    assert_not_nil(member.GetDB().ledgerDeletionTombstones[prop.ledgerId])
  end)

  it("applies a verified GM tombstone when the peer still has an approved ledger", function()
    local gm = load("GameMaster-Realm")
    local prop = gm.MultiLedger.ProposeLedger("GameMaster-Realm", "Out-of-date Peer")
    assert_true(prop.ok)
    assert_true(gm.MultiLedger.ApproveLedger("GameMaster-Realm", prop.ledgerId).ok)

    local member = load("Player-Realm", gm.DeepCopy(_G.RCLootCouncil_dibsDB))
    assert_equal("APPROVED", member.GetDB().ledgers[prop.ledgerId].status)
    local message = remote(member, {
      type = "LEDGER_DELETE",
      ledgerId = prop.ledgerId,
      deletedBy = "GameMaster-Realm",
      timestamp = 1700000001,
    }, "GameMaster-Realm")

    local ok, reason = member.Sync.Receive(message, "GameMaster-Realm")
    assert_true(ok)
    assert_equal("LEDGER_DELETED", reason)
    assert_nil(member.GetDB().ledgers[prop.ledgerId])
    assert_not_nil(member.GetDB().ledgerDeletionTombstones[prop.ledgerId])
  end)

  it("records a verified GM tombstone for an unknown ledger and blocks stale recreation", function()
    local member = load("Player-Realm")
    local ledgerId = "LDR-deleted-before-sync"
    local message = remote(member, {
      type = "LEDGER_DELETE",
      ledgerId = ledgerId,
      deletedBy = "GameMaster-Realm",
      timestamp = 1700000002,
    }, "GameMaster-Realm")

    local ok, reason = member.Sync.Receive(message, "GameMaster-Realm")
    assert_true(ok)
    assert_equal("LEDGER_DELETED", reason)
    assert_nil(member.GetDB().ledgers[ledgerId])
    assert_not_nil(member.GetDB().ledgerDeletionTombstones[ledgerId])

    local staleCatalog = remote(member, {
      type = "DIGEST",
      entityType = "LEDGER_CATALOG",
      revision = 1,
      contentHash = "STALE-CATALOG",
      ledgers = {
        [ledgerId] = {
          id = ledgerId,
          name = "Deleted Before Sync",
          status = "APPROVED",
          epoch = 1,
          revision = 0,
          rootHash = "NONE",
        },
      },
    }, "GameMaster-Realm")
    local catalogOk, catalogReason = member.Sync.Receive(staleCatalog, "GameMaster-Realm")
    assert_true(catalogOk)
    assert_equal("LEDGER_CATALOG_SYNCED", catalogReason)
    assert_nil(member.GetDB().ledgers[ledgerId])
  end)
end)
