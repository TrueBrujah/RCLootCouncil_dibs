local loader = require("helpers.load_addon")

describe("Ace3 options integration", function()
  it("registers Dibs-owned settings through AceConfig without changing SavedVariables", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    assert_true(dibs.RCOptions.EnsureRegistered(1))
    local launcherOptions = dibs.Ace3.libs.config.tables.RCLootCouncil_dibs
    assert_not_nil(launcherOptions)
    local launcher = launcherOptions.args.dibsSettings
    assert_equal(nil, launcher.childGroups)
    assert_equal("Open Player UI", launcher.args.openPlayerWindow.name)
    assert_equal("Open Officer UI", launcher.args.openOfficerWindow.name)
    local launcherCount = 0
    for _ in pairs(launcher.args) do launcherCount = launcherCount + 1 end
    assert_equal(2, launcherCount)
    local playerOpened, officerOpened = false, false
    dibs.PlayerUI.Toggle = function(forceShow) playerOpened = forceShow end
    dibs.OfficerUI.Toggle = function(forceShow) officerOpened = forceShow end
    launcher.args.openPlayerWindow.func()
    launcher.args.openOfficerWindow.func()
    assert_true(playerOpened)
    assert_true(officerOpened)
    local options = dibs.RCOptions.GetOptionsTable()
    assert_not_nil(options.args.dibsSettings.args.preDibs)
    assert_not_nil(options.args.dibsSettings.args.preDibs.args.mode)
    assert_not_nil(options.args.dibsSettings.args.settings.args.raidEntryDibPromptsEnabled)
    assert_not_nil(options.args.dibsSettings.args.settings.args.raidReminderMessage)
    assert_not_nil(dibs.GetDB().settings)
    assert_equal(nil, dibs.GetDB().profiles)
  end)

  it("supports the official callable-table LibStub implementation", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({
      wow = { guildLeader = true },
      rclootcouncil = rc,
      withAce3 = true,
      libStubAsCallableTable = true,
    })

    assert_true(dibs.AceGUI.IsAvailable())
    assert_true(dibs.RCOptions.EnsureRegistered(1))
    assert_not_nil(dibs.Ace3.libs.comm)
  end)

  it("leaves the legacy category list untouched on Retail Settings", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    local categories = {
      { parent = "RCLootCouncil", name = "Master Looter" },
      { parent = "RCLootCouncil", name = "Dibs" },
    }
    _G.INTERFACEOPTIONS_ADDONCATEGORIES = categories
    -- Registration ran once during initialization; repeat it after installing
    -- the sentinel list so the guard is exercised directly.
    dibs.RCOptions.registered = nil
    assert_true(dibs.RCOptions.EnsureRegistered(1))
    assert_equal("Master Looter", categories[1].name)
    assert_equal("Dibs", categories[2].name)
  end)

  it("does not leave Player or Officer dialog frames over Blizzard Settings", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    assert_true(dibs.PlayerUI.CreateWindow() ~= nil)
    assert_true(dibs.OfficerUI.CreateWindow() ~= nil)
    assert_false(_G.DibsPlayerFrame:IsShown())
    assert_false(_G.DibsOfficerFrame:IsShown())
  end)

  it("adds the packaged Dibs logo to AceGUI windows", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    local shell = dibs.AceGUI.CreateWindow("Logo test", 500, 400, { "CENTER", 0, 0 })
    assert_not_nil(shell)
    assert_not_nil(shell.frame.dibsLogoTexture)
    assert_equal(dibs.ICON_TEXTURE, shell.frame.dibsLogoTexture._texture)
    assert_false(shell.frame:IsShown())
  end)
end)

describe("Unified Dibs options", function()
  local function setup(wow)
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = wow or { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    assert_true(dibs.RCOptions.EnsureRegistered(1))
    return dibs, dibs.RCOptions.GetOptionsTable().args.dibsSettings.args
  end

  it("keeps Raid Dibs visible and sends to the resolved community stream", function()
    local dibs, groups = setup({ guildLeader = true, raidDibsChannel = true })
    local channel = groups.preDibs.args.preDibAnnouncementChannel
    dibs.PreDibs.SetAnnouncementChannels("RAID_DIBS", "NONE")
    assert_equal("Raid Dibs", channel.values[channel.get()])
    local before = #dibs.PreDibs.GetHistory()
    groups.announcements.args.testpublicChannel.func()
    assert_equal(2044801, _G.__sentChatMessages[1].clubId)
    assert_equal(3, _G.__sentChatMessages[1].streamId)
    assert_equal(before, #dibs.PreDibs.GetHistory())
    assert_true(groups.announcements.args.raidDibsStatus.name():find("stream 3", 1, true) ~= nil)
  end)

  it("retains the channel selection when the community is unavailable", function()
    local dibs, groups = setup()
    local channel = groups.preDibs.args.preDibAnnouncementChannel
    channel.set(nil, "RAID_DIBS")
    assert_equal("RAID_DIBS", dibs.PreDibs.GetAnnouncementSettings().publicChannel)
    assert_equal("Raid Dibs", channel.values[channel.get()])
    groups.announcements.args.testpublicChannel.func()
    assert_equal(0, #_G.__sentChatMessages)
    assert_true(dibs.RCOptions.state.status:find("not joined", 1, true) ~= nil)
  end)

  it("reads changes from either UI through shared settings and shows all views", function()
    local dibs, groups = setup()
    groups.announcements.args.preDibTemplate.set(nil, "%player - %item")
    assert_equal("%player - %item", dibs.PreDibs.GetAnnouncementTemplates().preDib)
    dibs.PreDibs.SetAnnouncementTemplates("Changed in officer window", "Reminder changed")
    assert_equal("Changed in officer window", groups.announcements.args.preDibTemplate.get())
    assert_equal("Reminder changed", groups.settings.args.raidReminderMessage.get())
    groups.developer.args.enabled.set(nil, true)
    assert_true(dibs.DeveloperMode.IsEnabled())
    assert_not_nil(groups.player.args.summary.name())
    assert_not_nil(groups.player.args.history.name())
    assert_not_nil(groups.player.args.openAcquisitions)
    assert_not_nil(groups.officer.args.statistics.name())
    assert_not_nil(groups.announcements.args.preview.name())
    assert_true(groups.player.args.summary.hidden == true)
    assert_true(groups.player.args.history.hidden == true)
    assert_true(groups.officer.args.statistics.hidden == true)
    assert_true(groups.officer.args.disputes.hidden == true)
    assert_true(groups.officer.args.reconciliation.hidden == true)
  end)

  it("preserves the actual raid reminder rejection reason", function()
    local dibs, groups = setup()
    dibs.Permissions.CanSendReminder = function() return false, "NOT_IN_RAID" end
    groups.settings.args.sendRaidReminder.func()
    assert_equal("NOT_IN_RAID", dibs.RCOptions.state.status)
    assert_equal(0, #_G.__sentChatMessages)
  end)

  it("uses the Retail category ID and defers opening in combat", function()
    local dibs = setup()
    local opened
    local previousSettings = _G.Settings
    local previousCombat = _G.InCombatLockdown
    _G.Settings = { OpenToCategory = function(id) opened = id end }
    dibs.RCOptions.categoryId = 4242
    _G.InCombatLockdown = function() return true end
    assert_equal(false, dibs.RCOptions.Open())
    assert_equal(nil, opened)
    assert_true(dibs.RCOptions.pendingOpen)
    _G.InCombatLockdown = function() return false end
    assert_true(dibs.RCOptions.Open())
    assert_equal(4242, opened)
    _G.Settings, _G.InCombatLockdown = previousSettings, previousCombat
  end)

  it("routes public requests through the player action and cancellation ownership", function()
    local dibs, groups = setup()
    local input
    dibs.PlayerUI.SubmitPreDib = function(value) input = value; return nil, "INVALID_ITEM" end
    groups.player.args.item.set(nil, "invalid")
    groups.player.args.submit.func()
    assert_equal("invalid", input)
    assert_equal("INVALID_ITEM", dibs.RCOptions.state.status)
    local owner
    dibs.PreDibs.CancelForPlayer = function(id, player) owner = player; return nil, "NOT_REQUEST_OWNER" end
    groups.player.args.request.set(nil, "someone-elses-request")
    groups.player.args.cancel.func()
    assert_equal(dibs.GetPlayerName(), owner)
    assert_equal("NOT_REQUEST_OWNER", dibs.RCOptions.state.status)
  end)
end)


describe("Dibs options compatibility", function()
  it("lists roster allocation gaps and assigns only missing rank Dibs", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({
      wow = {
        guildLeader = true,
        guildMembers = { "Tester-Realm", "Alice-Realm" },
        guildRankIndices = { [1] = 0, [2] = 3 },
      },
      rclootcouncil = rc,
      withAce3 = true,
    })
    local seasonId = dibs.GetCurrentSeasonId()
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "assignment reconciliation test" }))
    local baseline = assert(dibs.LegacyBaseline.FinalizeBaseline(nil))
    local coordinator = assert(dibs.Identity.CreateSnapshot("Tester-Realm"))
    assert_true(dibs.Governance.Change(nil, { future = { authority = {
      schema = 1, state = "ACTIVE", coordinator = coordinator, ledgerEpoch = 1,
      transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
    } } }))
    assert_true(dibs.Governance.EnableV2(nil, { "Tester-Realm" }))
    local ruleResult = dibs.ProtectedActions.Execute("rank.set", nil, {
      seasonId = seasonId, rankIndex = 3, rankName = "Member", allocation = 2,
    })
    assert_true(ruleResult.ok, tostring(ruleResult.diagnostic))
    dibs.RCOptions.EnsureRegistered(1)
    local assignments = dibs.RCOptions.GetOptionsTable().args.dibsSettings.args.assignments.args
    local summary = assignments.assignmentLog.name()
    assert_true(string.find(summary, "Alice-Realm", 1, true) ~= nil)
    assert_true(string.find(summary, "Difference +2", 1, true) ~= nil)
    assignments.reconciliationReason.set(nil, "Initial rank allocation")

    local before = #dibs.Ledger.GetTransactions(seasonId)
    assignments.reconcileMissing.func()
    local after = #dibs.Ledger.GetTransactions(seasonId)
    assert_equal(before + 1, after)
    assert_equal(2, dibs.Ledger.GetPlayerState("Alice-Realm", seasonId).allocation)

    assignments.reconcileMissing.func()
    assert_equal(after, #dibs.Ledger.GetTransactions(seasonId))
  end)

  it("opens the shared options without RCLootCouncil", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local opened
    dibs.Ace3.libs.dialog.Open = function(_, name) opened = name end
    dibs.HandleSlashCommand("options")
    assert_equal("RCLootCouncil_dibs", opened)
    assert_not_nil(dibs.RCOptions.GetOptionsTable().args.dibsSettings.args.officer)
  end)

  it("uses the RC type policy setter without changing the ledger", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    dibs.RCOptions.EnsureRegistered(1)
    local policy = dibs.RCOptions.GetOptionsTable().args.dibsSettings.args.integration.args.types
    local count = #dibs.Ledger.GetTransactions(dibs.GetCurrentSeasonId())
    local revision = dibs.RCLootCouncil.GetTypePolicyRevision()
    policy.set(nil, "MOUNTS", false)
    assert_equal(false, dibs.RCLootCouncil.IsDibEnabledForType("MOUNTS"))
    assert_equal(false, policy.get(nil, "MOUNTS"))
    assert_true(dibs.RCLootCouncil.GetTypePolicyRevision() > revision)
    assert_equal(count, #dibs.Ledger.GetTransactions(dibs.GetCurrentSeasonId()))
  end)

  it("keeps Catalyst personal and exposes class set tokens separately", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    dibs.RCOptions.EnsureRegistered(1)
    local policy = dibs.RCOptions.GetOptionsTable().args.dibsSettings.args.integration.args.types
    local values = policy.values()

    assert_nil(values.CATALYST)
    assert_not_nil(values.TOKEN_SET)
    assert_false(dibs.RCLootCouncil.IsDibEnabledForType("CATALYST"))
    assert_false(dibs.RCLootCouncil.IsItemDibTypeAllowed(nil, "CATALYST"))
    local changed, reason = dibs.RCLootCouncil.SetDibEnabledForType("CATALYST", true)
    assert_nil(changed)
    assert_equal("PERSONAL_ITEM_TYPE", reason)
    assert_false(policy.get(nil, "CATALYST"))
  end)

  it("documents RCLootCouncil set associations and applies semantic templates", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    rc.Getdb = function()
      return { buttons = {
        ARMOR_TOKEN = {},
        INVTYPE_HEAD = {},
        CATALYST_ITEMS = {},
        RARE_ITEMS = {},
        SPECIAL_EFFECTS_ITEMS = {},
        WEAPON = {},
      } }
    end
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    dibs.RCOptions.EnsureRegistered(1)
    local integration = dibs.RCOptions.GetOptionsTable().args.dibsSettings.args.integration
    local values = integration.args.types.values()
    assert_nil(values.ARMOR_TOKEN)
    assert_nil(values.CATALYST_ITEMS)
    assert_equal("Tier Set tokens (TOKEN_SET)", values.TOKEN_SET)
    assert_equal("HEAD (RCLC slot)", values.INVTYPE_HEAD)
    assert_equal("WEAPON (RCLC slot)", values.WEAPON)
    local guide = integration.args.mapping.args.guide.name()
    assert_true(guide:find("Catalyst Items [resolved]", 1, true) ~= nil)
    assert_true(guide:find("Armor Token -> TOKEN_SET", 1, true) ~= nil)
    assert_true(guide:find("Rare items -> OTHER", 1, true) ~= nil)
    assert_true(guide:find("Items /w special effects -> OTHER", 1, true) ~= nil)
    assert_true(guide:find("Chest, Back", 1, true) ~= nil)
    assert_true(guide:find("Equipment-slot specificity", 1, true) ~= nil)
    assert_true(integration.args.mapping.order > integration.args.templates.order)
    assert_nil(integration.args.status.name():find("\n", 1, true))

    assert_nil(integration.args.setup)
    assert_not_nil(integration.args.templates)
    assert_not_nil(integration.args.templates.args.generate)
    assert_true(integration.args.types.hidden)
    assert_true(integration.args.readiness.hidden)
    assert_true(integration.args.enable.hidden)
    assert_true(integration.args.disable.hidden)
    assert_not_nil(dibs.RCOptions.ApplyInstallationPreset)
    assert_not_nil(dibs.RCOptions.GetSetupAssistantStatus)
    assert_not_nil(dibs.RCOptions.RefreshDibButtonProjection)

    integration.args.types.set(nil, "TOKEN_SET", false)
    assert_false(dibs.RCLootCouncil.IsItemDibTypeAllowed(nil, "Armor Token"))
    integration.args.types.set(nil, "TOKEN_SET", true)
    assert_true(dibs.RCOptions.ApplyInstallationPreset("progression"))
    local policy = integration.args.types
    assert_true(policy.get(nil, "TOKEN"))
    assert_true(policy.get(nil, "TOKEN_SET"))
    assert_false(policy.get(nil, "MOUNTS"))
    assert_false(policy.get(nil, "default"))
  end)

  it("renders each template button as a compact horizontal row", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    local shell = dibs.AceGUI.CreateWindow("Template row test", 800, 500, { "CENTER", 0, 0 })
    local controls = {}
    local options = {
      name = "",
      args = {
        button1 = {
          type = "group", name = "Button 1", dibsLayout = "FLOW_ROW", titleWidthPx = 58,
          args = {
            text = { type = "input", name = "Button", order = 1, widthPx = 160, get = function() return "Need" end },
            color = { type = "color", name = "Color", order = 2, widthPx = 112, get = function() return 1, 1, 1, 1 end },
            response = { type = "input", name = "Response", order = 3, widthPx = 165, get = function() return "Need" end },
            notes = { type = "toggle", name = "Require Notes", order = 4, widthPx = 120, get = function() return false end },
            up = { type = "execute", name = "Up", order = 5, widthPx = 44, func = function() end },
            down = { type = "execute", name = "Down", order = 6, widthPx = 52, func = function() end },
          },
        },
      },
    }

    assert_true(dibs.AceGUI.RenderOptionsGroup(shell, shell.window, options, {
      scroll = false, renderGroupTitle = false, controlMap = controls,
    }))
    assert_equal("Flow", controls.text.parent.layout)
    assert_equal(controls.text.parent, controls.color.parent)
    assert_equal(controls.text.parent, controls.response.parent)
    assert_equal(controls.text.parent, controls.notes.parent)
    assert_equal(160, controls.text.width)
    assert_equal(112, controls.color.width)
    assert_equal(165, controls.response.width)
    assert_equal(120, controls.notes.width)
    assert_equal(46, controls.up.width)
    assert_equal(62, controls.down.width)
  end)

  it("refreshes options after a range value is committed", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    local shell = dibs.AceGUI.CreateWindow("Range refresh test", 800, 500, { "CENTER", 0, 0 })
    local controls, savedValue, refreshed = {}, nil, false
    local options = {
      name = "",
      args = {
        count = {
          type = "range", name = "Count", min = 1, max = 10, step = 1,
          get = function() return 4 end,
          set = function(_, value) savedValue = value end,
        },
      },
    }

    assert_true(dibs.AceGUI.RenderOptionsGroup(shell, shell.window, options, {
      scroll = false, renderGroupTitle = false, controlMap = controls,
      onChanged = function(_, kind)
        refreshed = kind == "range"
      end,
    }))
    assert_not_nil(controls.count.callbacks.OnMouseUp)
    controls.count.callbacks.OnMouseUp(controls.count, "OnMouseUp", 5)
    assert_equal(5, savedValue)
    assert_true(refreshed)
  end)

  it("manages reusable RCLootCouncil templates and per-type assignments", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local templates = dibs.RCOptions.GetButtonTemplateList()
    assert_equal(1, #templates)
    assert_equal("Standard", templates[1].name)
    assert_equal(4, templates[1].count)

    local templateId = dibs.RCOptions.CreateButtonTemplate("Cosmetic responses")
    assert_not_nil(templateId)
    assert_true(dibs.RCOptions.RenameButtonTemplate(templateId, "Cosmetic"))
    assert_true(dibs.RCOptions.SetButtonTemplateCount(templateId, 10))
    assert_true(dibs.RCOptions.SetButtonTemplateButton(templateId, 1, {
      text = "Collection", response = "Transmog", color = { 0.2, 0.4, 0.6, 1 }, requireNotes = true,
    }))
    assert_true(dibs.RCOptions.MoveButtonTemplateButton(templateId, 1, 1))
    assert_true(dibs.RCOptions.SetButtonTemplateAssignment("COSMETIC", templateId))

    local template = dibs.RCOptions.GetButtonTemplate(templateId)
    assert_equal("Cosmetic", template.name)
    assert_equal(10, template.count)
    assert_equal("Collection", template.buttons[2].text)
    assert_equal("Transmog", template.buttons[2].response)
    assert_equal(0.6, template.buttons[2].color[3])
    assert_true(template.buttons[2].requireNotes)
    assert_equal(templateId, dibs.RCOptions.GetButtonTemplateAssignment("COSMETIC"))

    assert_true(dibs.RCOptions.DeleteButtonTemplate(templateId))
    assert_equal("default", dibs.RCOptions.GetButtonTemplateAssignment("COSMETIC"))
    assert_equal("default", dibs.RCOptions.GetSelectedButtonTemplate())
  end)

  it("generates RC button sets from the local Draft without publishing Loot Rules", function()
    local profile = { maxButtons = 10, enabledButtons = { INVTYPE_HEAD = true }, buttons = {}, responses = {} }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.OPT_MORE_BUTTONS_VALUES = {}
    rc.RESPONSE_CODE_GENERATORS = { function() return "RARE" end }
    rc.Getdb = function() return profile end
    rc.ConfigTableChanged = function(self, changedKeys) self.lastConfigChange = changedKeys end
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })

    assert_true(dibs.LootRules.SetDraftValue("COSMETIC", "rclootcouncil", true))
    assert_true(dibs.LootRules.SetDraftValue("COSMETIC", "adventureGuide", false))
    local generated, result = dibs.RCOptions.GenerateButtonTemplatesFromDraft()
    assert_true(generated)
    assert_true(result.appliedSets >= 8)
    assert_not_nil(result.skippedTypes)
    assert_equal("Cosmetic Items", rc.OPT_MORE_BUTTONS_VALUES.COSMETIC)
    assert_equal(2, #rc.RESPONSE_CODE_GENERATORS)
    local cosmeticGenerator = rc.RESPONSE_CODE_GENERATORS[1]
    assert_equal("COSMETIC", cosmeticGenerator(nil, profile, 190101, "INVTYPE_NON_EQUIP_IGNORE", 4, 5))
    assert_nil(cosmeticGenerator(nil, profile, 190102, "INVTYPE_HEAD", 4, 1))
    local cosmeticEnabled = profile.enabledButtons.COSMETIC
    profile.enabledButtons.COSMETIC = false
    assert_nil(cosmeticGenerator(nil, profile, 190101, "INVTYPE_NON_EQUIP_IGNORE", 4, 5))
    profile.enabledButtons.COSMETIC = cosmeticEnabled
    assert_equal("RARE", rc.RESPONSE_CODE_GENERATORS[2]())
    assert_equal("Need", profile.buttons.COSMETIC[1].text)
    assert_nil(profile.buttons.COSMETIC[1].dibsLocked)
    assert_equal("Need", profile.responses.COSMETIC[1].text)
    assert_true(profile.enabledButtons.COSMETIC)
    assert_equal("Dib", profile.buttons.default[1].text)
    assert_true(profile.buttons.default[1].dibsLocked)
    assert_equal("Dib", profile.buttons.TOKEN[1].text)
    assert_equal("Dib", profile.buttons.RARE[1].text)
    assert_equal("Dib", profile.buttons.SPECIAL[1].text)
    assert_equal(5, profile.buttons.INVTYPE_HEAD.numButtons)
    assert_equal("Dib", profile.buttons.INVTYPE_HEAD[1].text)
    assert_nil(dibs.LootRules.GetAuthoritySnapshot())
    assert_true(rc.lastConfigChange.buttons)
    assert_true(rc.lastConfigChange.responses)

    assert_true(dibs.LootRules.SetDraftValue("COSMETIC", "adventureGuide", true))
    assert_true(dibs.RCOptions.GenerateButtonTemplatesFromDraft())
    for index = 1, profile.buttons.COSMETIC.numButtons do
      assert_nil(profile.buttons.COSMETIC[index].dibsLocked)
      assert_false(dibs.RCLootCouncil.IsDibResponse(profile.buttons.COSMETIC[index].text))
      assert_false(dibs.RCLootCouncil.IsDibResponse(profile.responses.COSMETIC[index].text))
    end

    dibs.RCLootCouncil.Initialize()
    assert_equal(2, #rc.RESPONSE_CODE_GENERATORS)
  end)

  it("skips Cosmetic template generation when RCLC lacks classifier extension tables", function()
    local profile = { maxButtons = 10, buttons = {}, responses = {} }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    rc.ConfigTableChanged = function() end
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })

    local supported, reason = dibs.RCLootCouncil.GetCosmeticResponseCodeSupport()
    assert_false(supported)
    assert_equal("RCLC_COSMETIC_TYPE_UNSUPPORTED", reason)
    assert_true(dibs.LootRules.SetDraftValue("COSMETIC", "rclootcouncil", true))

    local generated, result = dibs.RCOptions.GenerateButtonTemplatesFromDraft()
    assert_true(generated)
    assert_true(#result.skippedTypes > 0)
    assert_nil(profile.buttons.COSMETIC)
  end)

  it("omits DIB from a generated set when Draft Adventure Guide is disabled", function()
    local profile = { maxButtons = 10, buttons = {}, responses = {} }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    rc.ConfigTableChanged = function() end
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    assert_true(dibs.LootRules.SetDraftValue("TOKEN", "adventureGuide", false))
    assert_true(dibs.LootRules.SetDraftValue("TOKEN_SET", "adventureGuide", false))

    local generated = dibs.RCOptions.GenerateButtonTemplatesFromDraft()
    assert_true(generated)
    assert_equal(4, profile.buttons.TOKEN.numButtons)
    assert_equal("Need", profile.buttons.TOKEN[1].text)
    assert_equal("Need", profile.responses.TOKEN[1].text)
    assert_equal(4, profile.buttons.ARMOR_TOKEN.numButtons)
    assert_equal("Need", profile.buttons.ARMOR_TOKEN[1].text)
  end)

  it("generates Curio and Tier Set templates into their dedicated RC button sets", function()
    local profile = { maxButtons = 10, buttons = {}, responses = {} }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    rc.ConfigTableChanged = function() end
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    local templateId = dibs.RCOptions.CreateButtonTemplate("Tier set")
    assert_true(dibs.RCOptions.SetButtonTemplateAssignment("TOKEN_SET", templateId))
    assert_true(dibs.LootRules.SetDraftValue("TOKEN", "adventureGuide", false))
    assert_true(dibs.LootRules.SetDraftValue("TOKEN_SET", "adventureGuide", true))

    local generated, result = dibs.RCOptions.GenerateButtonTemplatesFromDraft()
    assert_true(generated, tostring(result))
    assert_true(profile.buttons.TOKEN ~= nil)
    assert_equal(4, profile.buttons.TOKEN.numButtons)
    assert_equal("Need", profile.buttons.TOKEN[1].text)
    assert_equal(true, profile.enabledButtons.TOKEN)
    assert_true(profile.buttons.ARMOR_TOKEN ~= nil)
    assert_equal(5, profile.buttons.ARMOR_TOKEN.numButtons)
    assert_equal("Dib", profile.buttons.ARMOR_TOKEN[1].text)
    assert_equal("Need", profile.buttons.ARMOR_TOKEN[2].text)
    assert_equal(true, profile.enabledButtons.ARMOR_TOKEN)
  end)

  it("keeps RCLootCouncil dry-run controls in Developer Mode", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    dibs.RCOptions.EnsureRegistered(1)
    local readiness = dibs.RCOptions.GetOptionsTable().args.dibsSettings.args.integration.args.readiness.args
    assert_true(readiness.dryRunItem.hidden())
    assert_true(readiness.runDryRun.hidden())
    dibs.DeveloperMode.SetEnabled(true)
    assert_false(readiness.dryRunItem.hidden())
    assert_false(readiness.runDryRun.hidden())
  end)

  it("resolves Curio and Tier Set metadata inside the Catalyst Items group", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    dibs.RCOptions.EnsureRegistered(1)

    local originalGetItemInfoInstant = _G.C_Item.GetItemInfoInstant
    local originalTokenTable = _G.RCTokenTable
    _G.C_Item.GetItemInfoInstant = function()
      return 270909, "Reagent", "Context Token", "INVTYPE_NON_EQUIP_IGNORE", nil, 5, 2
    end
    assert_true(dibs.RCLootCouncil.IsItemDibTypeAllowed(270909, "CATALYST_ITEMS"))
    assert_true(dibs.RCLootCouncil.IsItemDibTypeAllowed(270909, "CATALYST"))

    _G.C_Item.GetItemInfoInstant = function()
      return 270916, "Miscellaneous", "Junk", "INVTYPE_NON_EQUIP_IGNORE", nil, 15, 0
    end
    _G.RCTokenTable = { [270916] = "Head" }
    assert_true(dibs.RCLootCouncil.IsItemDibTypeAllowed(270916, "CATALYST_ITEMS"))
    assert_true(dibs.RCLootCouncil.IsItemDibTypeAllowed(270916, "CATALYST"))

    _G.C_Item.GetItemInfoInstant = originalGetItemInfoInstant
    _G.RCTokenTable = originalTokenTable
  end)

  it("routes ordinary equipment through the configurable Other family", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = loader.makeRCLootCouncil(), withAce3 = true })
    local originalGetItemInfoInstant = _G.C_Item.GetItemInfoInstant
    _G.C_Item.GetItemInfoInstant = function()
      return 190001, "Armor", "Plate", "INVTYPE_HEAD", nil, 4, 4
    end

    dibs.RCLootCouncil.SetDibEnabledForType("OTHER", false)
    assert_false(dibs.RCLootCouncil.IsItemDibTypeAllowed(190001, "INVTYPE_HEAD"))
    dibs.RCLootCouncil.SetDibEnabledForType("OTHER", true)
    assert_true(dibs.RCLootCouncil.IsItemDibTypeAllowed(190001, "INVTYPE_HEAD"))

    _G.C_Item.GetItemInfoInstant = originalGetItemInfoInstant
  end)

  it("keeps an Armor Token in Tier Set policy when its fallback class is Miscellaneous", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = loader.makeRCLootCouncil(), withAce3 = true })
    local originalGetItemInfoInstant = _G.C_Item.GetItemInfoInstant
    local originalTokenTable = _G.RCTokenTable
    _G.C_Item.GetItemInfoInstant = function()
      return 190003, "Miscellaneous", "Junk", "INVTYPE_HEAD", nil, 15, 0
    end
    _G.RCTokenTable = nil

    dibs.RCLootCouncil.SetDibEnabledForType("MOUNTS", true)
    dibs.RCLootCouncil.SetDibEnabledForType("TOKEN_SET", false)
    assert_false(dibs.RCLootCouncil.IsItemDibTypeAllowed(190003, "Armor Token"))

    dibs.RCLootCouncil.SetDibEnabledForType("TOKEN_SET", true)
    dibs.RCLootCouncil.SetDibEnabledForType("MOUNTS", false)
    assert_true(dibs.RCLootCouncil.IsItemDibTypeAllowed(190003, "Armor Token"))

    _G.C_Item.GetItemInfoInstant = originalGetItemInfoInstant
    _G.RCTokenTable = originalTokenTable
  end)

  it("uses Loot Rules to allow or block Cosmetic Items", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = loader.makeRCLootCouncil(), withAce3 = true })
    local originalGetItemInfoInstant = _G.C_Item.GetItemInfoInstant
    _G.C_Item.GetItemInfoInstant = function()
      return 190002, "Cosmetic", "Cosmetic", "INVTYPE_NON_EQUIP_IGNORE", nil, 5, 0
    end

    assert_false(dibs.RCLootCouncil.IsItemDibTypeAllowed(190002, "COSMETIC_ITEMS", { strictWhitelist = true }))
    local changed, reason = dibs.RCLootCouncil.SetDibEnabledForType("COSMETIC", true)
    assert_nil(changed)
    assert_equal("PERSONAL_ITEM_TYPE", reason)
    assert_true(dibs.LootRules.SetDraftValue("COSMETIC", "adventureGuide", true))
    assert_false(dibs.RCLootCouncil.IsItemDibTypeAllowed(190002, "COSMETIC_ITEMS", { strictWhitelist = true }))
    assert_false(dibs.RCLootCouncil.IsDibEnabledForType("COSMETIC"))

    _G.C_Item.GetItemInfoInstant = originalGetItemInfoInstant
  end)

  it("classifies localized Retail cosmetic, companion, mount, and housing items by enum", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local originalGetItemInfoInstant = _G.C_Item.GetItemInfoInstant
    local itemFacts = {
      [190101] = { 190101, "Armure", "Apparence", "INVTYPE_NON_EQUIP_IGNORE", nil, 4, 5 },
      [190102] = { 190102, "Divers", "Familier", "INVTYPE_NON_EQUIP_IGNORE", nil, 15, 2 },
      [190103] = { 190103, "Divers", "Monture", "INVTYPE_NON_EQUIP_IGNORE", nil, 15, 5 },
      [190104] = { 190104, "Logement", "Mobilier", "INVTYPE_NON_EQUIP_IGNORE", nil, 20, 0 },
      [190106] = { 190106, "Divers", "Equipement de monture", "INVTYPE_NON_EQUIP_IGNORE", nil, 15, 6 },
    }
    _G.C_Item.GetItemInfoInstant = function(itemID)
      local facts = itemFacts[tonumber(itemID)]
      if facts then return unpack(facts) end
    end

    assert_equal("COSMETIC", dibs.RCLootCouncil.GetItemSemanticFamily(190101, "INVTYPE_NON_EQUIP_IGNORE"))
    assert_equal("PETS", dibs.RCLootCouncil.GetItemSemanticFamily(190102, "INVTYPE_NON_EQUIP_IGNORE"))
    assert_equal("MOUNTS", dibs.RCLootCouncil.GetItemSemanticFamily(190103, "INVTYPE_NON_EQUIP_IGNORE"))
    assert_equal("DECOR", dibs.RCLootCouncil.GetItemSemanticFamily(190104, "INVTYPE_NON_EQUIP_IGNORE"))
    assert_equal("OTHER", dibs.RCLootCouncil.GetItemSemanticFamily(190106, "INVTYPE_NON_EQUIP_IGNORE"))

    _G.C_Item.GetItemInfoInstant = originalGetItemInfoInstant
  end)

  it("uses active guild Loot Rules instead of a conflicting local legacy policy", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local originalGetItemInfoInstant = _G.C_Item.GetItemInfoInstant
    local originalGetAuthoritySnapshot = dibs.LootRules.GetAuthoritySnapshot
    _G.C_Item.GetItemInfoInstant = function()
      return 190105, "Armure", "Apparence", "INVTYPE_NON_EQUIP_IGNORE", nil, 4, 5
    end
    assert_true(dibs.LootRules.SetDraftValue("COSMETIC", "adventureGuide", false))
    dibs.LootRules.GetAuthoritySnapshot = function()
      return { types = { COSMETIC = { adventureGuide = true } } }, "GUILD_LOOT_RULES_READY"
    end

    assert_false(dibs.RCLootCouncil.IsItemDibTypeAllowed(190105, "INVTYPE_NON_EQUIP_IGNORE", { strictWhitelist = true }))

    dibs.LootRules.GetAuthoritySnapshot = originalGetAuthoritySnapshot
    _G.C_Item.GetItemInfoInstant = originalGetItemInfoInstant
  end)
end)


describe("Officer loot type controls", function()
  it("shares dynamic types and draft changes with RC options without bulk presets", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    dibs.RCLootCouncil.SetDibEnabledForType("TOKEN", false)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("lootTypes")
    local policy = dibs.RCOptions.GetLootTypeOptions().types
    assert_true(policy.values().COSMETIC ~= nil)
    assert_equal(false, frame.lootTypeControls.TOKEN.value)
    assert_nil(frame.lootTypeControls.COSMETIC)
    assert_nil(frame.rcLootTypeControls.COSMETIC)
    frame.lootTypeControls.TOKEN.callbacks.OnValueChanged(nil, nil, true)
    assert_equal(true, policy.get(nil, "TOKEN"))
    policy.set(nil, "MOUNTS", false)
    frame:Refresh()
    assert_equal(false, frame.lootTypeControls.MOUNTS.value)
    assert_equal(nil, frame.enableLootTypes)
    assert_equal(nil, frame.defaultLootTypes)
  end)
end)

describe("Player and officer option visibility", function()
  it("hides officer controls for a player", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {}, enabled = false })
    local _, dibs = loader.load({ wow = { guildLeader = false }, rclootcouncil = rc, withAce3 = true })
    dibs.RCOptions.EnsureRegistered(1)
    dibs.Permissions.IsOfficer = function() return false end
    local groups = dibs.RCOptions.GetOptionsTable().args.dibsSettings.args
    assert_true(groups.officer.hidden())
    assert_true(groups.settings.hidden())
    assert_true(groups.debug.hidden())
    assert_true(groups.player.hidden == nil or groups.player.hidden() == false)
    assert_nil(groups.overview.args.officer)
    assert_not_nil(groups.officer.args.openWindow)
    assert_nil(groups.player.args.preDibs)
  end)

  it("shows officer controls to a guild officer", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    dibs.RCOptions.EnsureRegistered(1)
    local groups = dibs.RCOptions.GetOptionsTable().args.dibsSettings.args
    assert_equal(false, groups.officer.hidden())
    assert_nil(groups.overview.args.officer)
    assert_not_nil(groups.officer.args.preDibs)
    assert_true(groups.officer.args.openWindow.name():find("Open officer window", 1, true) ~= nil)
  end)

  it("keeps every Officer navigation page populated after switching tabs", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    local frame = dibs.OfficerUI.CreateWindow()
    local pages = { "overview", "disputes", "reconciliation", "seasons", "ranks", "settings", "preDibs", "eligibility", "announcements", "developer", "integration", "debug" }
    for _, page in ipairs(pages) do
      frame.SelectTab(page)
      assert_equal(page, frame.selectedRoute)
      assert_equal(page, frame.mountedPage)
      assert_equal(1, #(frame.contentHost.children or {}), "Officer route must mount one page root: " .. page)
      assert_true(#(frame.contentHost.children[1].children or {}) > 0, "Officer page has no content: " .. page)
    end
  end)
end)
