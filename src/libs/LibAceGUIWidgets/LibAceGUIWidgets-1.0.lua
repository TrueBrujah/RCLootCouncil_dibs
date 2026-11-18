-- LibAceGUIWidgets-1.0
-- Shared AceGUI-3.0 widget types + styling for the TOG suite. Registers custom
-- AceGUI widget types so any addon can `AceGUI:Create(...)` them for a consistent
-- look, instead of each addon re-implementing the same frames.
--
-- Widget types registered here:
--   "ClearFrame"  — movable/resizable main window with a DialogBox title bar
--                   (a close-button-less, status-bar-less variant of AceGUI Frame)
--   "GroupFrame"  — borderless movable/resizable container
--   "TLabel"      — label + optional icon, with multi-line tooltip support
--
-- Addon-agnostic: the widgets carry no addon state. The only themeable hook the
-- widgets themselves use is the tooltip owner (TLabel); accent / class colors are
-- provided here for the widgets added in later files (RowList). Configure once:
--   local W = LibStub("LibAceGUIWidgets-1.0")
--   W:Configure{ accent = "ffFF8000", tooltipOwner = function(f) ... end, scale = 1.25 }
--
-- ONE UI SCALE (MINOR 29): `W:SetScale(1.5)` enlarges every font, icon and row this library draws,
-- together, for the visually impaired. Fonts go through `W:ScaledFont(base)`, geometry through
-- `W:ScaledSize(px)`, and every widget here re-lays itself on `W:OnScaleChanged`. See the section
-- below the accent helpers for the contract. Not `frame:SetScale` -- that grows a window off the
-- screen and makes saved sizes and resize minimums mean different things at different scales.
--
-- Ported from FastGuildInvite's Libs\GUI.lua, decoupled from FGI state. Each
-- widget block uses a POSITIVE version guard (not the `return`-exits-the-chunk
-- pattern the original used) so the three types always register independently.

-- INLINE luacheck directives, deliberately duplicating this repo's `.luacheckrc`.
--
-- luacheck resolves `.luacheckrc` from the CURRENT WORKING DIRECTORY, not from the file being checked. This
-- library is consumed by ~20 addons and is routinely linted from a CONSUMER's repo root — where the config
-- that gets picked up is that addon's, listing that addon's globals, and every WoW global this file uses
-- reads as undefined. The repo config alone is therefore only correct when someone happens to be standing
-- in this directory. An inline directive travels with the file and is right from anywhere.
--
-- 212 = unused argument: AceGUI and Blizzard's script handlers hand these signatures in, so an unused
-- `self`/`frame`/`width` is the contract being honoured rather than a mistake.
-- luacheck: read globals LibStub hooksecurefunc geterrorhandler debugstack
-- luacheck: read globals CreateFrame CreateFont UIParent GetScreenHeight GetScreenWidth GetTime C_Timer
-- luacheck: read globals PlaySound SOUNDKIT BackdropTemplateMixin InCombatLockdown RegisterStateDriver
-- luacheck: read globals GameTooltip GameTooltip_SetDefaultAnchor GetCurrentKeyBoardFocus
-- luacheck: read globals C_AddOns GetAddOnMetadata
-- luacheck: read globals UIDropDownMenu_CreateInfo UIDropDownMenu_Initialize UIDropDownMenu_SetWidth
-- luacheck: read globals UIDropDownMenu_SetText UIDropDownMenu_AddButton UIDropDownMenu_JustifyText
-- luacheck: read globals ToggleDropDownMenu CloseDropDownMenus L_UIDropDownMenu_AddButton
-- luacheck: read globals GameFontNormal GameFontNormalSmall GameFontHighlight GameFontHighlightSmall
-- luacheck: read globals GameFontDisable GameFontDisableSmall ChatFontNormal NORMAL_FONT_COLOR HIGHLIGHT_FONT_COLOR
-- luacheck: read globals RAID_CLASS_COLORS ITEM_QUALITY_COLORS
-- luacheck: read globals strsplit strjoin strtrim wipe tContains
-- luacheck: globals LibAceGUIWidgetsDB SLASH_LIBACEGUIWIDGETS1 SlashCmdList
-- luacheck: read globals CLOSE OKAY CANCEL ACCEPT SEARCH NONE
-- luacheck: ignore 212 213 411 412 431 432

local MAJOR, MINOR = "LibAceGUIWidgets-1.0", 50
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	-- THE SATELLITES' VERSION GUARD (MINOR 45, Peer Review thread f6a85948). The satellite files load
	-- straight after this one in the same TOC and assign their methods onto the shared table, so without
	-- this an OLDER copy's satellites, loading after a newer copy, would overwrite the newer methods.
	-- Each satellite returns early while `_staleCopy` is set; the next copy's core resets it. An EQUAL
	-- copy is not stale and its satellites re-run, exactly as before. Copies older than 45 do not set
	-- or read this, so one of those loading last still overwrites (CHANGELOG: KNOWN COST).
	local current, currentMinor = LibStub:GetLibrary(MAJOR, true)
	if current then current._staleCopy = (currentMinor or 0) > MINOR end
	return
end
lib._staleCopy = false

-- ---------------------------------------------------------------------------
-- Configuration / theme (consumer-set; every field optional)
-- ---------------------------------------------------------------------------
--
-- THIS TABLE IS SESSION-GLOBAL, NOT PER-CONSUMER, AND THAT IS DELIBERATE (documented at MINOR 33,
-- DIBSREQ-LAGW-012). There is ONE LibAceGUIWidgets in a session -- that is what LibStub is for -- so
-- there is one `config`, and a consumer calling `Configure` re-themes every OTHER consumer's widgets
-- too. A per-consumer accent was requested and DECLINED, because it contradicts the reason this
-- library exists: it is the shared toolkit for one author's suite, so that the suite SHARES ONE
-- LOOK. Per-consumer accents would give a player Dibs in orange next to ClassicCalendar in gold, in
-- windows meant to look like one product -- and the request itself came from a consumer whose accent
-- (`C.COLOR`) its own source calls "family brand orange": the SUITE's colour, not that addon's.
--
-- SO THE CORRECT NUMBER OF CONSUMERS CALLING `Configure{ accent = ... }` IS AT MOST ONE, and the
-- honest problem with the old behaviour was never the sharing -- it was that a SECOND caller would
-- silently win by load order, which is a property of the player's installation and of no addon's
-- code. Two players with the same addons would see different colours and nothing would say why.
-- That is the silent-wrong-answer shape this library reports rather than tolerates (as
-- `_reportEmptyRender` and the double-owned-window refusal do), so `SetAccent` now says so once.
--
-- THE DEFAULT IS THE SUITE ORANGE (MINOR 36, TOGProfessionMaster inbox 8f931ba9). It was gold
-- ("ffFFD100") until then, which is Blizzard's NORMAL_FONT_COLOR and nobody's brand -- so every
-- consumer that did not call Configure drew gold where the suite draws orange, and the one-setter
-- rule above meant it could not fix that locally without becoming the second setter. The operator's
-- words: "have the library change it's color to our orange, not sure why it's gold." ONE literal,
-- read by the table, GetAccent and AccentRGB, so the default cannot drift between them.
local DEFAULT_ACCENT = "ffFF8000"
lib.DEFAULT_ACCENT = DEFAULT_ACCENT
lib.config = lib.config or {
	tooltipOwner = nil,        -- function(frame): anchor GameTooltip; nil = lib:_DefaultAnchor
	accent       = DEFAULT_ACCENT, -- brand accent hex "ffRRGGBB" (used by RowList etc.)
	classColors  = nil,        -- optional { WARRIOR = "ffc79c6e", ... }; nil = WoW RAID_CLASS_COLORS
	classDisplay = nil,        -- optional function(classFile) -> coloured+localized class string
	                           -- (RowList col.classDisplay)
	refontHook   = nil,        -- optional function(fontstring, fontObject): re-font a cell after non-Latin text
	scale        = 1.0,        -- the UI scale (MINOR 29); set through SetScale / Configure, never by hand
	debug        = nil,        -- MINOR 39: true, or function() -> bool, to print diagnostics to chat
}
-- AN UPGRADE KEEPS THE OLDER COPY'S TABLE (the `or` above), and that table holds the old gold
-- DEFAULT -- so without this a session where an addon with a pre-36 copy loaded first would stay gold
-- after this copy took over. Only the untouched default moves: `_accentSetter` (MINOR 33+) records an
-- explicit call, and a consumer that asked for gold keeps gold.
if lib.config.accent == "ffFFD100" and not lib._accentSetter then lib.config.accent = DEFAULT_ACCENT end

-- Merge a partial config in. Consumers call this once at init.
--
-- `scale` is the one field that does not land by assignment: it goes through `SetScale`, which
-- clamps it and tells every widget, because a value written straight into the table would leave
-- the fonts and the row heights at the old size until something else happened to move them.
--
-- `accent` is the second such field as of MINOR 33, and for the same class of reason: it goes
-- through `SetAccent`, which is where the "two addons set different accents" report lives. Written
-- straight into the table it would bypass that entirely -- and `Configure` is how every consumer
-- actually sets the accent (Dibs' two call sites are both `Configure`, neither is `SetAccent`), so
-- a check only `SetAccent` performed would be a check nothing reaches.
function lib:Configure(t)
	if type(t) ~= "table" then return end
	for k, v in pairs(t) do
		if k ~= "scale" and k ~= "accent" then self.config[k] = v end
	end
	if t.accent ~= nil then self:SetAccent(t.accent) end
	if t.scale ~= nil then self:SetScale(t.scale) end
end

function lib:SetTooltipOwner(fn) self.config.tooltipOwner = fn end
function lib:GetTooltipOwner()   return self.config.tooltipOwner end

-- ---------------------------------------------------------------------------
-- Diagnostics -- what this library reported, in a form a spec can assert on (MINOR 33)
-- ---------------------------------------------------------------------------
--
-- A PRINTED LINE IS A DEVELOPER'S DIAGNOSTIC DELIVERED TO A PLAYER, and the player cannot act on it:
-- every one of these faults is in the CONSUMING ADDON's code, not in anything the player configured.
-- So a print alone is noise where it lands and invisible where it would help -- no consumer's
-- offline suite can assert on a chat line. Peer review made that point against the duplicate-column
-- -key report (thread 0eca0c8b) and it is right about all three of them.
--
-- So every report goes to BOTH: one line for the operator watching their chat, and one entry here
-- for the consumer's spec, which can assert `#W:Diagnostics() == 0` after building its windows and
-- fail the day one of these starts happening. The print is the symptom; this is the record.
--
-- ONE FUNCTION BECAUSE THREE APPEARED IN A DAY. The empty-render line (MINOR 33), the duplicate
-- column key and the accent clash were each written separately, each with its own `_warnedX` flag
-- and its own copy of the `[LibAceGUIWidgets] ` prefix -- which is the same duplication class this
-- MINOR spent its self-audit removing from the gold literal and the disabled-hover rule, forming
-- while the audit was being written. ONCE-NESS STAYS AT THE CALL SITE, deliberately: the accent
-- clash is once per session, a duplicate key is once per key, and the empty-render line is once per
-- LIST (a second list with no room is a second fault worth hearing about). Those are three different
-- correct answers and a shared flag would have to pick one.
lib.diagnostics = lib.diagnostics or {}

--- Everything this library has reported this session, oldest first. Each entry is a table with
--- `kind` ("duplicateColumnKey" | "accentClash" | "emptyRender"), the `message` that was printed,
--- and the fields belonging to that kind. THE LIVE TABLE, not a copy -- `ClearDiagnostics` is the
--- sanctioned reset, and a consumer's spec wanting a clean slate per example calls it in `before_each`.
function lib:Diagnostics() return self.diagnostics end

--- Empty the record. Does NOT re-arm the once-per-X guards at the call sites: clearing the log does
--- not make an already-reported fault newly interesting, and a spec that wants the report again
--- builds a new list (or, for the accent, clears `_accentSetter`). Keeping those separate is what
--- stops `ClearDiagnostics` from quietly becoming a way to make the library shout.
function lib:ClearDiagnostics()
	for i = #self.diagnostics, 1, -1 do self.diagnostics[i] = nil end
	return self.diagnostics
end

--- True when chat diagnostics are switched on. `config.debug` is a boolean or a function returning
--- one, so a consumer can bind it to its own live debug setting (`Configure{ debug = function() return
--- MyAddon.db.debug end }`) instead of re-calling Configure every time the player toggles it.
---
--- OFF BY DEFAULT (MINOR 39). Every chat line this library prints is a developer's diagnostic about a
--- consumer's code, and the operator saw the empty-render line land in a player's chat between two
--- guild messages. The record in `Diagnostics()` is unconditional; only the chat line is gated.
function lib:IsDebug()
	-- The player's `/lagw debug on|off` wins over any consumer's setting, both ways (see SetDebug).
	if self._debugOverride ~= nil then return self._debugOverride end
	local d = self.config.debug
	if type(d) == "function" then
		local ok, on = pcall(d)
		return ok and on and true or false
	end
	return d and true or false
end

--- The one chat line the library prints, behind the debug switch.
function lib:_Say(message)
	if self:IsDebug() then print("[LibAceGUIWidgets] " .. message) end
end

--- The PLAYER's switch (MINOR 39, the operator: "you should add a / command to turn it on/off as
--- well"). `true`/`false` force chat diagnostics on or off whatever a consumer's `config.debug` says;
--- `nil` hands the decision back to the consumers. Kept apart from `config.debug` so a consumer
--- re-calling Configure cannot silently undo what the player typed. Saved in `LibAceGUIWidgetsDB`
--- (the standalone addon's SavedVariables; an embedded-only copy keeps it for the session).
function lib:SetDebug(on)
	if on ~= nil then on = on and true or false end
	self._debugOverride = on
	if type(LibAceGUIWidgetsDB) ~= "table" then LibAceGUIWidgetsDB = {} end
	LibAceGUIWidgetsDB.debug = on
end

--- `/lagw debug [on|off|reset]`. No argument toggles. Answers in chat either way: the player asked.
function lib:_Slash(msg)
	local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(%S*)")
	if cmd == "debug" then
		if arg == "on" then self:SetDebug(true)
		elseif arg == "off" then self:SetDebug(false)
		elseif arg == "reset" then self:SetDebug(nil)
		else self:SetDebug(not self:IsDebug()) end
		local src = self._debugOverride == nil and " (set by addons)" or ""
		print("[LibAceGUIWidgets] debug is " .. (self:IsDebug() and "on" or "off") .. src .. ".")
	elseif cmd == "scale" then
		-- `/lagw scale [shared|separate]` (MINOR 50). No argument toggles.
		if arg == "shared" or arg == "on" then self:SetScaleShared(true)
		elseif arg == "separate" or arg == "off" then self:SetScaleShared(false)
		else self:SetScaleShared(not self:IsScaleShared()) end
		print("[LibAceGUIWidgets] " .. (self:IsScaleShared()
			and "one text and widget size for every addon, now " .. self:GetScale() .. "."
			or "each addon keeps its own text and widget size (from your next login or reload)."))
	else
		print("[LibAceGUIWidgets] /lagw debug [on|off|reset] -- show this library's diagnostics in chat.")
		print("[LibAceGUIWidgets] /lagw scale [shared|separate] -- one text and widget size for every addon,"
			.. " or each its own.")
	end
end

-- ONE registration for the session, whichever copy loads first; the handler finds the CURRENT copy
-- through LibStub, so a newer MINOR loaded later still answers.
if SlashCmdList and not SlashCmdList.LIBACEGUIWIDGETS then
	SLASH_LIBACEGUIWIDGETS1 = "/lagw"
	SlashCmdList.LIBACEGUIWIDGETS = function(msg) LibStub(MAJOR):_Slash(msg) end
end

--- Record one diagnostic and, in debug, print it. `extra` is the kind's own fields; it is the table
--- that gets stored, so callers pass a fresh one.
function lib:_Report(kind, message, extra)
	local entry = extra or {}
	entry.kind, entry.message = kind, message
	self.diagnostics[#self.diagnostics + 1] = entry
	self:_Say(message)
	return entry
end

--- Set the session's accent. See the note on `lib.config`: this is GLOBAL, and at most one consumer
--- in a session should call it.
---
--- IT REPORTS A SECOND, DIFFERENT SETTER, ONCE (MINOR 33, DIBSREQ-LAGW-012). Not the first call,
--- which is the intended one, and not a repeat of the SAME colour -- a consumer re-asserting its
--- accent on every window open is fine and must stay silent. Only a genuine disagreement, which is
--- the case that would otherwise be decided by ADDON LOAD ORDER: a property of the player's
--- installation, not of anybody's code, so two players with the same addons see different colours
--- and neither author's choice is honoured. Nothing errors, nothing looks wrong, and the result is
--- simply not what anyone picked -- which is why it has to speak rather than cope.
---
--- `_accentSetter` is the colour the last explicit call asked for, NOT `config.accent`, so a compare
--- cannot be fooled by the default or by something writing the table directly.
function lib:SetAccent(hex)
	if self._accentSetter and hex ~= self._accentSetter and not self._warnedAccentClash then
		self._warnedAccentClash = true
		self:_Report("accentClash",
			("Two addons set different accents this session (%s, then %s). "):
				format(tostring(self._accentSetter), tostring(hex))
			.. "The accent is shared by every addon using this library, so the LAST one loaded wins "
			.. "and which that is depends on the player's addon list. Only one addon in a suite "
			.. "should call Configure{ accent = ... }.",
			{ previous = self._accentSetter, replacement = hex })
	end
	self._accentSetter = hex
	self.config.accent = hex
end

function lib:GetAccent()         return self.config.accent or DEFAULT_ACCENT end

-- Resolve a class file token ("WARRIOR") to an "ffRRGGBB" hex: the consumer's
-- classColors override if given, else WoW's RAID_CLASS_COLORS, else white.
function lib:ClassColor(classFile)
	local cc = self.config.classColors
	if cc and cc[classFile] then return cc[classFile] end
	local raid = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile]
	if raid and raid.colorStr then return raid.colorStr end
	return "ffffffff"
end

-- ---------------------------------------------------------------------------
-- Shared helpers (used by the widgets here, by RowList, and by consumers)
-- ---------------------------------------------------------------------------

-- Anchor GameTooltip to `frame` without ever overlapping it. A consumer-set tooltipOwner wins; otherwise the
-- default is FGI's auto-flipping placement: anchor ABOVE (ANCHOR_TOPRIGHT) when there's room over the frame,
-- else BELOW (ANCHOR_BOTTOMLEFT) when the frame sits so near the top of the screen that an above-anchored
-- tooltip would clip off-screen. Corner anchors (not ANCHOR_TOP) so the tooltip sits beside/below the control
-- instead of centered over it. `tooltipHeight` (optional px) tunes the room-above gate; we can't measure the
-- tooltip before SetOwner, so a caller hint is the cleanest signal (defaults to 250).
-- The built-in placement on its own, so a consumer owner function that RAISES falls back to it rather
-- than leaving the tooltip unanchored (Peer Review 8a4be5e5). A method, not a file-scope local: the
-- main chunk sits near Lua's local-variable limit (Tests/localheadroom_spec.lua).
function lib:_DefaultAnchor(frame, tooltipHeight)
	local top = frame and frame.GetTop and frame:GetTop()
	local screenH = (GetScreenHeight and GetScreenHeight()) or 0
	local budget = tooltipHeight or 250
	local anchor = (top and (screenH - top) > budget) and "ANCHOR_TOPRIGHT" or "ANCHOR_BOTTOMLEFT"
	GameTooltip:SetOwner(frame, anchor)
end

function lib:AnchorTooltip(frame, tooltipHeight)
	local owner = self.config.tooltipOwner
	-- lib._safeCall, not the safeCall local: that local is declared further down this file, so a bare
	-- name here would compile as a nil global. It is assigned at load, before any tooltip can show.
	if not (owner and lib._safeCall(owner, frame)) then self:_DefaultAnchor(frame, tooltipHeight) end
	-- MINOR 42: every tooltip anchored through here clears a TOOLTIP-strata panel it was hovered in
	-- (see raiseTipLevel). Here rather than at each call site, so the item rows, the RowList icons and
	-- hyperlinks and the ClearFrame info button get it without carrying a copy each.
	self:_RaiseTipLevel(frame)
end

-- THE one way a tooltip this library drew is put away (MINOR 34): hide it, then hand the anchor back
-- to the client's default. `Hide` does not clear the owner that `AnchorTooltip` set, so the next
-- addon that calls `GameTooltip:Show()` without a SetOwner of its own drew at OUR frame -- Questbook
-- found it on the bottom-row icons (inbox 7271976e), where its hand-rolled row had always handed the
-- anchor back. Every leave handler in this library goes through here so none can be the one that
-- does not. `GameTooltip_SetDefaultAnchor` is defined in every flavour tree on this box
-- (Blizzard_SharedXML/SharedTooltipTemplates.lua:87), and the Classic trees ALSO define one at
-- Blizzard_GameTooltip/Classic/GameTooltip.lua:109; which wins at runtime is not verified, and both
-- take (tooltip, parent). Feature-detected all the same.
--
-- `frame` (optional, MINOR 34): the frame whose leave this is. When the library drew that frame's
-- tooltip through `ShowTooltip`, it recorded who the tooltip was actually handed to -- the frame
-- itself, or wherever a consumer's `tooltipOwner` anchored it -- and this returns without touching
-- the tooltip unless that owner still holds it. So a leave never hides or re-anchors a tooltip
-- another frame or addon has taken since (peer review L1). The guard is on the RECORDED owner, not
-- the hovered frame: guarding on the hovered frame would leave a tooltip a consumer anchored
-- elsewhere stuck on screen. With no frame, or a frame the library did not draw for, it hides as
-- before.
function lib:HideTooltip(frame)
	local held = type(frame) == "table" and frame._lagwTipHeldBy or nil
	if held and GameTooltip.IsOwned and not GameTooltip:IsOwned(held) then return end
	GameTooltip:Hide()
	if GameTooltip_SetDefaultAnchor and UIParent then GameTooltip_SetDefaultAnchor(GameTooltip, UIParent) end
end

-- ---------------------------------------------------------------------------
-- Is the player mid-interaction with a window? (MINOR 36, TOGProfessionMaster inbox 8f507ee7)
-- ---------------------------------------------------------------------------
-- A consumer that redraws on events must not rebuild a tab while the player has one of its menus open
-- or is typing in one of its boxes -- the rebuild throws the menu and the caret away. Only this library
-- knows whether one of ITS menus is open, so the question is asked here.

-- `frame` or one of its ancestors is `root`. A walk UP the anchor's parents, which is a handful of
-- steps -- never a walk down the window's tree.
local function isWithin(frame, root)
	local depth = 0
	while type(frame) == "table" and depth < 64 do
		if frame == root then return true end
		frame = frame.GetParent and frame:GetParent() or nil
		depth = depth + 1
	end
	return false
end

local function frameOf(frameOrWidget)
	if type(frameOrWidget) ~= "table" then return nil end
	return frameOrWidget.frame or frameOrWidget
end

-- Keyboard focus on the edit boxes THIS LIBRARY builds, kept by their own focus scripts. The client's
-- `GetCurrentKeyBoardFocus` answers for every box and is used when present, but it has no call site in
-- this box's Classic Era or Classic source trees, so it is not relied on alone (not verified in game).
function lib:_trackFocus(eb)
	if not eb or eb._lagwFocusTracked or not eb.HookScript then return end
	eb._lagwFocusTracked = true
	eb:HookScript("OnEditFocusGained", function(box) lib._focusedBox = box end)
	eb:HookScript("OnEditFocusLost", function(box) if lib._focusedBox == box then lib._focusedBox = nil end end)
end

--- True when a menu this library opened (OpenMenu, ToggleMenu, a CreateDropdownBox, a RowList header)
--- is showing and its anchor is `frameOrWidget` or inside it. Submenus are the same stack, so they
--- count. Another addon's open menu answers false.
function lib:IsMenuOpenFor(frameOrWidget)
	local root = self._menus and self._menus[1]
	if not (root and root:IsShown() and self._menuAnchor) then return false end
	local target = frameOf(frameOrWidget)
	return target ~= nil and isWithin(self._menuAnchor, target)
end

--- True when the keyboard focus is an edit box inside `frameOrWidget`.
function lib:IsInputFocusedIn(frameOrWidget)
	local target = frameOf(frameOrWidget)
	if not target then return false end
	local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() or self._focusedBox
	-- The tracked box is only a record of the last gain; a box hidden while focused may never report the
	-- loss, so ask the box itself before believing it.
	if focus and focus == self._focusedBox and focus.HasFocus and not focus:HasFocus() then focus = nil end
	return focus ~= nil and isWithin(focus, target)
end

--- Call `fn()` once, the next time a library menu anchored inside `owner` closes -- including when
--- another menu replaces it. For a redraw deferred while the menu was open. One callback per owner:
--- a second call replaces it, `fn = nil` removes it. Returns whether a callback is now registered.
function lib:OnMenuClosed(owner, fn)
	local target = frameOf(owner)
	if not target then return false end
	self._menuClosedFns = self._menuClosedFns or {}
	self._menuClosedFns[target] = type(fn) == "function" and fn or nil
	return self._menuClosedFns[target] ~= nil
end

-- Hand an error to the client's error handler without stopping the caller's loop. The WoW-API
-- annotations declare the handler with no parameters, but it takes the message; that report is the
-- annotation's, suppressed here once rather than at every call site.
local function reportError(err)
	local handler = geterrorhandler and geterrorhandler()
	---@diagnostic disable-next-line: redundant-parameter
	if handler then handler(err) end
end

-- xpcall's message handler: runs BEFORE the stack unwinds, so the frames of the callback that raised
-- travel with the message (pcall alone returns the bare message). debugstack is feature-detected
-- rather than assumed on every flavour.
local function withStack(e)
	return debugstack and (tostring(e) .. "\n" .. debugstack(2)) or e
end

-- The one way this library dispatches a consumer callback: run it protected, report a failure with its
-- stack, and let the caller carry on. Lua 5.1's xpcall passes no arguments, hence the closure.
-- Returns whether it succeeded AND, on success, the callback's first return -- so a getter, a
-- predicate or a tooltip-text function goes through this same helper rather than a hand-written
-- closure per site (Peer Review e19885f0, finding 2). It hands back `ok` rather than taking a default
-- because the sites differ on what a failure means: most fall back to a default
-- (`local ok, v = safeCall(fn); if not ok then v = default end`), but Checkbox_Refresh must leave the
-- box exactly as it was, and a default cannot say "no change".
local function safeCall(fn, ...)
	local n, args = select("#", ...), { ... }
	local ok, res = xpcall(function() return fn(unpack(args, 1, n)) end, withStack)
	if not ok then reportError(res) return false end
	return true, res
end
-- Satellites (Resize, SideTabs, ...) dispatch through the same helper; a local cannot cross a file
-- boundary.
lib._safeCall = safeCall

-- The menu owned by `anchor` has just closed: run, and forget, every OnMenuClosed callback whose
-- owner contains it. Collected first, so a callback that opens another menu cannot disturb the loop.
function lib:_menuClosed(anchor)
	local fns = self._menuClosedFns
	if not (fns and anchor) then return end
	local due = {}
	for owner, fn in pairs(fns) do
		if isWithin(anchor, owner) then due[#due + 1] = fn; fns[owner] = nil end
	end
	for _, fn in ipairs(due) do safeCall(fn) end
end

--- Place a floating `popup` against `source` (MINOR 36, TOGProfessionMaster inbox c8d6892f): under it,
--- left edges aligned, or over it when the popup would run off the bottom of the screen; slid left
--- when it would run off the right edge and never past the left one. Re-evaluated on every call, so
--- call it each time the popup opens -- a scrolled row has moved. The popup is also clamped to the
--- screen, the client's own backstop for a popup taller than the room on either side.
---
--- Everything is measured in UIParent units (each frame's rect times its effective scale over
--- UIParent's), so a scaled window or popup is placed right. `opts.gap` is scale-1.0 px (default 2).
--- Returns "below" or "above", or nil when either frame cannot be measured yet.
function lib:AnchorPopup(popup, source, opts)
	if type(popup) ~= "table" or type(source) ~= "table" then return nil end
	local uiScale = UIParent:GetEffectiveScale()
	local sS = source:GetEffectiveScale() / uiScale
	local pS = popup:GetEffectiveScale() / uiScale
	local sLeft, sBottom = source:GetLeft(), source:GetBottom()
	if not (sLeft and sBottom) then return nil end
	sLeft, sBottom = sLeft * sS, sBottom * sS
	local pw, ph = (popup:GetWidth() or 0) * pS, (popup:GetHeight() or 0) * pS
	local gap = self:ScaledSize((opts and tonumber(opts.gap)) or 2)
	local screenW = UIParent:GetWidth()

	local dx = 0
	if sLeft + pw > screenW then dx = screenW - (sLeft + pw) end
	if sLeft + dx < 0 then dx = -sLeft end

	popup:ClearAllPoints()
	if popup.SetClampedToScreen then popup:SetClampedToScreen(true) end
	if sBottom - gap - ph >= 0 then
		popup:SetPoint("TOPLEFT", source, "BOTTOMLEFT", dx / pS, -gap / pS)
		return "below"
	end
	popup:SetPoint("BOTTOMLEFT", source, "TOPLEFT", dx / pS, gap / pS)
	return "above"
end

-- Wrap text in the configured accent color. Safe to embed in fontstrings,
-- tooltips, and chat output.
function lib:Brand(text)
	return "|c" .. self:GetAccent() .. tostring(text or "") .. "|r"
end

-- The configured "ffRRGGBB" accent as r,g,b floats (0-1), for texture vertex colours and SetTextColor. The
-- leading alpha byte is ignored; a malformed accent falls back to the default orange (1, 0.5, 0).
--
-- PUBLIC as of MINOR 28. It was a file-local, which meant the satellite files could not reach it: the
-- DatePicker needed the accent as floats and the only alternatives were a second hex-to-float
-- conversion in that file (one concept, two spellings -- the drift class this suite's peer review
-- files against itself) or reaching into the core through an undocumented field. Consumers may use it
-- too; it is the same value `BrandTabGroup` tints the tab band with.
-- "ffRRGGBB" (or "RRGGBB") -> r, g, b floats, each channel falling back to the default orange's. One
-- parser, used by AccentRGB and by FlashScreen's `color` (MINOR 36).
local function hexRGB(hex)
	hex = tostring(hex or DEFAULT_ACCENT):gsub("[^%x]", "")
	if #hex >= 8 then hex = hex:sub(3) end   -- drop the alpha byte of an "ffRRGGBB" value
	hex = hex:sub(1, 6)
	return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
	       (tonumber(hex:sub(3, 4), 16) or 128) / 255,
	       (tonumber(hex:sub(5, 6), 16) or 0)   / 255
end

function lib:AccentRGB()
	return hexRGB(self:GetAccent())
end

-- ---------------------------------------------------------------------------
-- UI scale -- ONE factor for the visually impaired, honoured by everything drawn here (MINOR 29)
-- ---------------------------------------------------------------------------
-- Requested by TOGBankClassic (inbox 05264c5f, 2026-09-15), whose operator asked for "a visibility
-- feature that makes the font/icons/rows larger on a slider for the visually impaired" and ruled
-- that it lives here, so every consumer gets it at once and carries only the slider.
--
--   W:SetScale(1.5)                  -- clamped to [W.SCALE_MIN, W.SCALE_MAX]; 1.0 is the default
--   W:GetScale()
--   W:Configure{ scale = 1.5 }       -- the same thing, for a consumer that configures in one call
--   W:ScaledSize(16)                 -- 16 x scale, rounded to a whole pixel: geometry you draw yourself
--   W:ScaledFont("GameFontNormal")   -- a font OBJECT at the base's size x scale, path and flags kept
--   W:SetScaledSize(frame, 20, 20)   -- SetSize(20 x scale) now, and again on every change
--   W:OnScaleChanged(owner, fn)      -- fn(newScale, oldScale) after every change; one fn per owner
--
-- SHARED ONLY WHEN THE PLAYER SAYS SO (MINOR 50; MINOR 49 made it the default, and the operator
-- reversed that: "they need to be seperate by default"). Each consumer saves its own size and applies
-- it at load, as before MINOR 49. `/lagw scale shared` (`W:SetScaleShared(true)`) makes the library
-- save one size in `LibAceGUIWidgetsDB.scale`: SetScale writes it and the bootstrap restores it at the
-- library's own ADDON_LOADED, and `W:HasSavedScale()` answers true so a consumer skips its own value
-- at load. `/lagw scale separate` forgets it. An embedded-only copy (no standalone addon loaded) has no
-- SavedVariables, so sharing lasts for the session only.
--
-- SCALED FONTS, NOT frame:SetScale. `ScaledFont(base)` derives one font object per base font --
-- `LAGWScaled_<base>` -- and RE-SIZES IT IN PLACE when the scale moves, so a FontString pointed at it
-- follows without anybody re-fonting it. That is why the cache is per BASE and not per (base, scale):
-- a per-(base, scale) cache would hand out a different object after a change and leave every
-- FontString on the old one. The object is derived from `base:GetFont()` (path, size, flags), so
-- the size is readable offline and a font-face addon that re-fonts the base is honoured on the next
-- change. `frame:SetScale` on a window was ruled out by the request and is ruled out here: it grows
-- the window off the screen, breaks pixel-fitted column widths, and makes the resize minimums and
-- PersistWindow's saved sizes mean different things at different scales.
--
-- WHAT IS SCALED, in one sentence per rule so a consumer can predict it:
--   * every font this library draws, through ScaledFont;
--   * every SIZE this library chooses (row and header heights, icon sizes, box heights, dialog and
--     menu geometry, the resize MINIMUMS and maximums) -- and a size a consumer passes in (`rowHeight`,
--     `width`/`height` on MakeLabel / CreateSearchBox / CreateDropdownBox, `col.width`, `minW`) is
--     treated as a SCALE-1.0 value and multiplied, so nothing written for 1.0 needs a change;
--   * NOT a position a consumer passes (`x`/`y` on MakeLabel, an anchor offset): the consumer owns
--     its layout and redraws its own regions on the signal with ScaledSize;
--   * NOT the size of a WINDOW: the user sizes windows and PersistWindow saves real pixels. A window
--     under its (now larger) minimum is raised to it when the scale changes, nothing else moves;
--   * NOT GameTooltip: it is the client's one shared frame, and a font set on one of its lines sticks
--     to that line slot for every later tooltip (see the symbol-font note below). Left alone.
--
-- THE SIGNAL. `OnScaleChanged(owner, fn)` keeps ONE listener per owner, so a re-registration
-- replaces rather than stacks (the AttachTooltip lesson); `fn = nil` removes it. Listeners fire
-- AFTER the fonts have been re-sized, so one that measures text sees the new metrics. Each runs
-- under pcall with the error handed to the client's handler: a consumer's raise must not stop the
-- library's own widgets from re-laying. The table is weak-keyed and the library's own listeners are
-- module-level functions that take the owner as a THIRD argument rather than closures over it, so a
-- RowList or a handle nothing references any more is collected rather than kept alive by its own
-- listener (Lua 5.1 has no ephemerons: a weak key whose value closes over it is never collected).
lib.SCALE_MIN, lib.SCALE_MAX, lib.SCALE_DEFAULT = 0.8, 2.0, 1.0

lib._scaleListeners = lib._scaleListeners or setmetatable({}, { __mode = "k" })
lib._scaledFonts    = lib._scaledFonts or {}   -- base name -> { font = <Font>, base = name, src = <Font> }

local function clampScale(v)
	v = tonumber(v)
	if not v then return lib.SCALE_DEFAULT end
	if v < lib.SCALE_MIN then return lib.SCALE_MIN end
	if v > lib.SCALE_MAX then return lib.SCALE_MAX end
	return v
end

function lib:GetScale()
	return self.config.scale or lib.SCALE_DEFAULT
end

-- True once the library holds a saved scale for this client (MINOR 49): the standalone addon's
-- SavedVariables were restored at its ADDON_LOADED and carry one. While false, a consumer may apply
-- its own saved value at load, and SetScale saves it here for every later login.
-- Only while the PLAYER has turned sharing on (`/lagw scale shared`, MINOR 50): by default each addon
-- keeps and applies its own size, as before MINOR 49 (the operator, 2026-11-05: "they need to be
-- seperate by default").
function lib:HasSavedScale()
	return self:IsScaleShared() and self._scaleRestored == true
		and type(LibAceGUIWidgetsDB) == "table" and LibAceGUIWidgetsDB.scale ~= nil
end

-- True when the player chose one size for every addon (`/lagw scale shared`). Off by default.
function lib:IsScaleShared()
	return self._scaleShared == true
end

-- The PLAYER's switch, saved in LibAceGUIWidgetsDB like `/lagw debug`. Turning it on saves the size
-- in force now as the shared one; turning it off forgets the shared size, so each addon's own saved
-- size applies again from the next login.
function lib:SetScaleShared(on)
	on = on and true or false
	self._scaleShared = on
	if type(LibAceGUIWidgetsDB) ~= "table" then LibAceGUIWidgetsDB = {} end
	LibAceGUIWidgetsDB.scaleShared = on or nil
	LibAceGUIWidgetsDB.scale = on and self:GetScale() or nil
	return on
end

-- px x scale, rounded to a whole pixel (a half rounds up). 0 stays 0 at every scale.
function lib:ScaledSize(px)
	return math.floor((tonumber(px) or 0) * self:GetScale() + 0.5)
end

-- The base font object and its cache key. Accepts a global font NAME ("GameFontNormalSmall") or a
-- font OBJECT (W.SymbolFont, or one a consumer made with CreateFont).
local function fontObjectOf(base)
	if type(base) == "string" then return _G[base], base end
	if type(base) == "table" and type(base.GetFont) == "function" then
		local name = base.GetName and base:GetName()
		return base, (type(name) == "string" and name ~= "") and name or tostring(base)
	end
	return nil
end

-- (Re)derive one cached font from its base at the current scale. The base is resolved by NAME on
-- every derive, so a font-face addon replacing the global, or the offline harness reinstalling it,
-- is picked up rather than the object captured at first use.
local function deriveScaledFont(self, entry)
	local base = (type(entry.base) == "string" and _G[entry.base]) or entry.src
	local font = entry.font
	if not (base and base.GetFont) then return end
	local path, size, flags = base:GetFont()
	if not path then return end
	-- CopyFontObject carries colour, shadow and justification in the client; SetFont then overrides
	-- the size. The explicit colour copy below is for a client (or the offline model) whose
	-- CopyFontObject does less than that -- setting it twice is harmless.
	if font.CopyFontObject then font:CopyFontObject(base) end
	font:SetFont(path, (tonumber(size) or 12) * self:GetScale(), flags or "")
	if base.GetTextColor and font.SetTextColor then font:SetTextColor(base:GetTextColor()) end
	if base.GetShadowColor and font.SetShadowColor then font:SetShadowColor(base:GetShadowColor()) end
	if base.GetShadowOffset and font.SetShadowOffset then font:SetShadowOffset(base:GetShadowOffset()) end
end

-- The scaled font object for `base` (a name or an object): the base's font at size x scale, one
-- object per base, re-sized in place on every scale change. nil for a base that does not exist --
-- nil rather than the base, so a typo in a font name is visible at the call site and not as text
-- that quietly refuses to grow. A client with no CreateFont (none this library ships to) gets the
-- base back: text at 1.0 beats no text.
function lib:ScaledFont(base)
	local src, key = fontObjectOf(base)
	if not (src and key) then return nil end
	local entry = self._scaledFonts[key]
	if not entry then
		local name = "LAGWScaled_" .. key
		local font = _G[name]                                    -- a MINOR upgrade re-running this file
		if not font and CreateFont then font = CreateFont(name) end
		if not font then return src end
		entry = { font = font, base = key, src = src }
		self._scaledFonts[key] = entry
		deriveScaledFont(self, entry)
	end
	return entry.font
end

-- Register (or replace, or with fn = nil remove) the listener for `owner`. Returns fn.
function lib:OnScaleChanged(owner, fn)
	if owner == nil or (fn ~= nil and type(fn) ~= "function") then return nil end
	self._scaleListeners[owner] = fn
	return fn
end

-- Set the scale. Clamps, re-sizes every derived font, then tells every listener. Returns the scale
-- actually applied. A no-op (no re-derive, no signal) when the value did not move.
function lib:SetScale(factor)
	local new, old = clampScale(factor), self:GetScale()
	self.config.scale = new
	if self:IsScaleShared() then
		if type(LibAceGUIWidgetsDB) ~= "table" then LibAceGUIWidgetsDB = {} end
		LibAceGUIWidgetsDB.scale = new
	end
	if new == old then return new end
	for _, entry in pairs(self._scaledFonts) do deriveScaledFont(self, entry) end
	-- Snapshot first: a listener may register or drop another, and adding a key during `pairs` is
	-- undefined in Lua 5.1.
	local owners, fns = {}, {}
	for owner, fn in pairs(self._scaleListeners) do
		owners[#owners + 1], fns[#fns + 1] = owner, fn
	end
	for i = 1, #fns do safeCall(fns[i], new, old, owners[i]) end
	return new
end

-- Keep `frame` at (w, h) x scale: applied now and again on every change. Either dimension may be
-- nil to leave it alone. The record on the frame is the listener's owner, not the frame, so a
-- consumer's own OnScaleChanged(frame, ...) is not displaced.
local function ScaledSize_OnScaleChanged(_, _, rec)
	local f = rec.frame
	if rec.w then f:SetWidth(lib:ScaledSize(rec.w)) end
	if rec.h then f:SetHeight(lib:ScaledSize(rec.h)) end
end

function lib:SetScaledSize(frame, w, h)
	if type(frame) ~= "table" or type(frame.SetWidth) ~= "function" then return frame end
	local rec = frame._lagwScaledSize
	if not rec then
		rec = { frame = frame }
		frame._lagwScaledSize = rec
		self._scaleListeners[rec] = ScaledSize_OnScaleChanged
	end
	rec.w, rec.h = tonumber(w), tonumber(h)
	ScaledSize_OnScaleChanged(nil, nil, rec)
	return frame
end

-- A UIPanelButtonTemplate button carries three font slots; scale all three so a caption grows with
-- the rest. Guarded because the offline model and a bare Button may lack the setters.
local function scaleButtonFonts(self, btn)
	if btn.SetNormalFontObject    then btn:SetNormalFontObject(self:ScaledFont("GameFontNormal")) end
	if btn.SetHighlightFontObject then btn:SetHighlightFontObject(self:ScaledFont("GameFontHighlight")) end
	if btn.SetDisabledFontObject  then btn:SetDisabledFontObject(self:ScaledFont("GameFontDisable")) end
end
lib._scaleButtonFonts = scaleButtonFonts   -- for the satellite files

-- ---------------------------------------------------------------------------
-- Symbol font -- a font the LIBRARY ships, for glyphs the client's fonts cannot draw (MINOR 28)
-- ---------------------------------------------------------------------------
-- The client's fonts have no arrows, check marks, crosses or warning signs: a U+2192 in a tooltip
-- renders as an empty box on Classic Era. Requested by TOGBankClassic (inbox b7f9981a, 2026-09-13)
-- after exactly that, with the operator's ruling -- "those fonts should be in the widgets library, so
-- every addon can use them, no reason to get them per addon" -- so per-addon font bundling is ruled out
-- for the suite; a glyph is either drawn through this font or replaced with ASCII.
--
-- The font is DejaVu Sans 2.37, `Fonts/DejaVuSans.ttf`, its licence beside it (Bitstream Vera terms
-- plus public-domain DejaVu additions: redistribution is permitted with the notice, which ships). Read
-- from the file's own name table and cmap before it was shipped, not assumed from its path: every code
-- point `lib:Symbol` names below maps to a glyph in it.
--
--   local fs = frame:CreateFontString(nil, "OVERLAY")
--   fs:SetFontObject(W.SymbolFont)            -- 12px; W.SymbolFontSmall is 11px
--   fs:SetText(W:Symbol("check") .. " Synced")
--   -- or, for a FontString you already size yourself:
--   fs:SetFont(W:SymbolFontPath(), 14, "")
--
-- WHAT IT CAN AND CANNOT DO, confirmed rather than taken from the request. A FontString the consumer
-- OWNS -- a RowList cell, a label, a status line -- takes the font wholesale. A GameTooltip line is one
-- of the tooltip's own FontStrings (`GameTooltipTextLeftN`) carrying the tooltip font: `SetFont` on it
-- is legal, but the change sticks to that line SLOT for every later tooltip until something resets it,
-- so it is not a per-line font and this library does not do it. Chat text goes through the chat frame's
-- one font (`ChatFrame1:SetFont` changes every line). So a tooltip or chat line keeps ASCII whatever
-- font ships, unless the consumer draws that text on FontStrings of its own.
lib.SYMBOL_FONT = "Interface\\AddOns\\RCLootCouncil_dibs\\libs\\LibAceGUIWidgets\\Fonts\\DejaVuSans.ttf"

function lib:SymbolFontPath() return lib.SYMBOL_FONT end

-- Named symbols, so a consumer writes `W:Symbol("arrow_right")` instead of a UTF-8 escape by hand.
-- Every entry is a code point the shipped font maps (checked from its cmap, 2026-09-13).
local SYMBOLS = {
	arrow_right = "\226\134\146",   -- U+2192
	arrow_left  = "\226\134\144",   -- U+2190
	arrow_up    = "\226\134\145",   -- U+2191
	arrow_down  = "\226\134\147",   -- U+2193
	check       = "\226\156\147",   -- U+2713
	check_heavy = "\226\156\148",   -- U+2714
	cross       = "\226\156\151",   -- U+2717
	cross_heavy = "\226\156\152",   -- U+2718
	warning     = "\226\154\160",   -- U+26A0
	le          = "\226\137\164",   -- U+2264
	ge          = "\226\137\165",   -- U+2265
	plusminus   = "\194\177",       -- U+00B1
	bullet      = "\226\128\162",   -- U+2022
	star        = "\226\152\133",   -- U+2605
	star_hollow = "\226\152\134",   -- U+2606
	play        = "\226\150\182",   -- U+25B6
	refresh     = "\226\134\187",   -- U+21BB
}
lib.SYMBOLS = SYMBOLS

-- The UTF-8 string for a named symbol, or nil for a name this library does not carry -- nil rather
-- than an empty string, so a consumer can `W:Symbol("check") or "[OK]"` for an older copy or a typo.
function lib:Symbol(name)
	return SYMBOLS[name]
end

-- Two font objects, built once per session under global names (a font object is a named global in
-- the client; `CreateFont` on a name that exists would be a second object under the same name, so an
-- existing one is reused -- which is what a MINOR upgrade re-running this file hits). 12 and 11 are
-- GameFontNormal's and GameFontNormalSmall's sizes on every flavour this library ships to; no outline,
-- so the glyphs read as text beside the client's own.
local function symbolFont(name, size)
	local font = _G[name]
	if not font and CreateFont then font = CreateFont(name) end
	if font then font:SetFont(lib.SYMBOL_FONT, size, "") end
	return font
end
lib.SymbolFont      = symbolFont("LAGWSymbolFont", 12)
lib.SymbolFontSmall = symbolFont("LAGWSymbolFontSmall", 11)

-- Brand an AceGUI-3.0 "TabGroup" with the suite tab look: a soft ACCENT GLOW behind the SELECTED tab (the
-- stock selected state only greys/disables the tab, which is hard to spot) plus an accent MOUSE-OVER glow on
-- the others — the FastGuildInvite tab feel. Call once, right after AceGUI:Create("TabGroup"); idempotent.
-- It's pure styling: it hooks the widget's own BuildTabs (where tabs are created lazily and recycled) to
-- decorate each tab, and SelectTab to move the selected glow — never changing which tab is selected or any
-- callback. Safe on any TabGroup; a no-op on a non-TabGroup table.
local TAB_GLOW = "Interface\\QuestFrame\\UI-QuestTitleHighlight"   -- a soft horizontal highlight band, tinted to accent
--- The REGION to anchor a tab's accent band to — its font string, or the tab itself as a fallback.
---
--- Deliberately never trusts `tab.text`: Blizzard's `PanelTemplates_SetDisabledTabState` (which AceGUI runs on
--- the SELECTED tab, that being how it greys the active one) assigns `tab.text = tab:GetText()` — a **string**.
--- Anchoring to a string makes SetPoint treat it as a global frame NAME, which resolves to nothing, so the
--- band silently failed to anchor on precisely the one tab that shows it. That is why the glow looked like it
--- did nothing at all rather than looking half-broken. AceGUI's real font string is `tab.Text` (capital T).
--- Anything without SetPoint is rejected, so a future field of the wrong type can't reintroduce this.
function lib.TabLabelRegion(tab)
	local t = tab and tab.Text
	if type(t) == "table" and type(t.SetPoint) == "function" then return t end
	return tab
end

-- The tab's three font slots at the current scale. AceGUI sets the stock GameFont*Small on each
-- tab at CreateTab, and `PanelTemplates_SelectTab` / `_SetDisabledTabState` RE-SET the disabled
-- slot on every selection -- so this runs from the post-SelectTab refresh as well as at decorate,
-- choosing the disabled face by the tab's state exactly as AceGUI does.
local function scaleTabFonts(self, tab)
	if not tab.SetNormalFontObject then return end
	tab:SetNormalFontObject(self:ScaledFont("GameFontNormalSmall"))
	tab:SetHighlightFontObject(self:ScaledFont("GameFontHighlightSmall"))
	tab:SetDisabledFontObject(self:ScaledFont(tab.disabled and "GameFontDisableSmall" or "GameFontHighlightSmall"))
end

-- On a scale change the fonts have already grown in place; the tab WIDTHS have not, because AceGUI
-- sizes each tab from its text at BuildTabs. Rebuild, which re-measures, and the SelectTab/BuildTabs
-- hooks below re-run the decoration.
local function TabGroup_OnScaleChanged(_, _, tg)
	if tg.tablist and tg.BuildTabs then tg:BuildTabs() end
end

function lib:BrandTabGroup(tg)
	if type(tg) ~= "table" or type(tg.tabs) ~= "table" or tg._brandedTabs then return tg end
	tg._brandedTabs = true
	local r, g, b = self:AccentRGB()
	-- Scale the fonts BEFORE AceGUI measures the text: BuildTabs calls CreateTab and then SetText,
	-- and SetText is what sizes the tab from the font in effect. A post-hook on BuildTabs would
	-- scale the font after the width had been taken from the stock one, and the label would sit in
	-- a tab fitted for smaller text until the next rebuild.
	if type(tg.CreateTab) == "function" then
		local createTab = tg.CreateTab
		tg.CreateTab = function(widget, id)
			local tab = createTab(widget, id)
			if tab then scaleTabFonts(lib, tab) end
			return tab
		end
	end
	for _, tab in ipairs(tg.tabs) do scaleTabFonts(self, tab) end   -- tabs that already exist
	self:OnScaleChanged(tg, TabGroup_OnScaleChanged)
	local function decorate(tab)
		if tab._brandGlow or type(tab.CreateTexture) ~= "function" then return end
		-- Selected glow: a persistent accent halo BEHIND the tab graphic, shown only while that tab is selected.
		-- A soft accent highlight BAND behind the label (bright centre, fading to the ends — like a selected menu
		-- row). Anchor it to the tab's LABEL, not the frame: the band then auto-fits each differently-sized tab
		-- and always sits behind the text, never over the tab's border / end caps (the SELECTED tab's graphic is
		-- also shifted down vs its frame, which a frame-anchored band overlapped). Shown only while selected.
		local txt = lib.TabLabelRegion(tab)
		-- ARTWORK, not BACKGROUND. AceGUI builds each tab's own Left/Middle/Right graphic in the BORDER layer,
		-- and BACKGROUND draws UNDERNEATH that — so a band placed there is hidden behind an opaque tab and the
		-- glow simply never appeared, on any client. ARTWORK sits above the tab graphic and still below the
		-- button's own font string, which is where the band belongs.
		local sel = tab:CreateTexture(nil, "ARTWORK")
		sel:SetTexture(TAB_GLOW)
		if sel.SetBlendMode then sel:SetBlendMode("ADD") end
		sel:SetVertexColor(r, g, b, 0.85)
		sel:SetHeight(lib:ScaledSize(11))       -- fits the tab's ~12px flat inner strip, centred on the label
		-- The label's anchor box already spans the tab's flat inner width, so inset the band INWARD from it (a
		-- positive left / negative right offset) to stay clear of the rounded end caps — padding it OUTWARD ran
		-- it over the edges.
		sel:SetPoint("LEFT", txt, "LEFT", 3, 0)
		sel:SetPoint("RIGHT", txt, "RIGHT", -3, 0)
		sel:Hide()
		tab._brandGlow = sel
		-- Mouse-over glow: an accent-tinted highlight (replaces the stock character-tab highlight). WoW shows it
		-- on hover automatically; a selected tab is Disable()d, so it never fights the selected halo.
		if tab.SetHighlightTexture then
			tab:SetHighlightTexture(TAB_GLOW, "ADD")
			local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
			if hl then
				hl:SetVertexColor(r, g, b, 0.45)
				hl:ClearAllPoints()
				hl:SetHeight(lib:ScaledSize(11))
				hl:SetPoint("LEFT", txt, "LEFT", 3, 0)
				hl:SetPoint("RIGHT", txt, "RIGHT", -3, 0)
				tab._brandHighlight = hl
			end
		end
	end
	local function refresh()
		local bandH = lib:ScaledSize(11)
		for _, tab in ipairs(tg.tabs) do
			decorate(tab)
			scaleTabFonts(lib, tab)   -- SelectTab just reset the disabled slot to the stock font
			if tab._brandGlow then
				tab._brandGlow:SetHeight(bandH)
				tab._brandGlow:SetShown(tab.selected == true)
			end
			if tab._brandHighlight then tab._brandHighlight:SetHeight(bandH) end
		end
	end
	if hooksecurefunc then
		hooksecurefunc(tg, "BuildTabs", refresh)
		hooksecurefunc(tg, "SelectTab", refresh)
	end
	refresh()
	return tg
end

-- The addon's DISPLAY version for a status bar / about line — the SAME thing FastGuildInvite shows: the TOC
-- "Version", with the BigWigs git-tag prefix stripped ("Dibs-v0.1.7" → "0.1.7", and a leading "v"). It is the
-- ADDON version, NOT the game client version: an unpackaged dev checkout shows the raw "LibAceGUIWidgets-v0.12.0"
-- token (the packager replaces it with the real version for players). No game-version fallback, no "dev"
-- substitution. Returns the string ("?" if the addon has no Version metadata at all).
function lib:ResolveVersion(addonName)
	local v
	if C_AddOns and C_AddOns.GetAddOnMetadata then v = C_AddOns.GetAddOnMetadata(addonName, "Version")
	elseif GetAddOnMetadata then v = GetAddOnMetadata(addonName, "Version") end
	if type(v) == "string" and v ~= "" then
		return (v:gsub("^" .. tostring(addonName) .. "%-[vV]", ""):gsub("^[vV]", ""))
	end
	return "?"
end

-- VersionCheck-1.0 integration — OPTIONAL dependency. VersionCheck is the suite's "a guildmate is running a
-- newer build" awareness (a one-time update nudge); it is fully self-driving once Enable()d. Wiring it here
-- means every consuming addon gets the integration from one call instead of hand-rolling the LibStub lookup
-- + Enable each (the pattern was copied across FGI, Dibs, …). It is a SOFT dep: if VersionCheck isn't loaded
-- these are no-ops, so an addon that ships without it simply has no update reminder.
--
-- lib:EnableVersionCheck(nameOrHost[, version]) — register a host addon with VersionCheck.
--   nameOrHost : the addon name string, OR a host object { GetName = function()->name, Version = "x.y.z" }.
--   version    : optional explicit RAW addon version to report/compare. IMPORTANT: pass the raw TOC version
--                (the "LibAceGUIWidgets-v0.12.0" sentinel in a dev checkout), NOT lib:ResolveVersion's DISPLAY value
--                — VersionCheck needs the sentinel to recognise a dev build and suppress the popup. Omit to
--                let VersionCheck read GetAddOnMetadata(name,"Version") itself.
-- Returns the VersionCheck handle (so the caller can :TriggerVersionCheck() later), or nil if VC isn't present.
-- ONLY A HIT IS CACHED, and that is a fix rather than a micro-optimisation. This used to be
-- `if self._vc == nil then self._vc = LibStub(...) or false end` -- and `false ~= nil`, so the
-- FIRST call decided the answer for the whole session, for every consumer of the library. Load
-- order is what makes that fatal: `_vc` lives on the shared lib table, VersionCheck is a separate
-- addon, and any consumer that calls this from its own ADDON_LOADED before VersionCheck's file has
-- run caches the miss permanently -- so a LATER consumer that does depend on VersionCheck gets nil
-- back from a library that has stopped looking. Re-resolving on a miss costs one LibStub table
-- index, which is nothing next to a whole suite silently losing its update nudge.
function lib:EnableVersionCheck(nameOrHost, version)
	local VC = self._vc
	if not VC then
		VC = LibStub and LibStub("VersionCheck-1.0", true) or nil
		if VC then self._vc = VC end
	end
	if not (VC and VC.Enable) then return nil end
	local host = nameOrHost
	if type(nameOrHost) == "string" then
		local name = nameOrHost
		host = { GetName = function() return name end }
		if version ~= nil then host.Version = version end
	elseif type(nameOrHost) == "table" and version ~= nil and nameOrHost.Version == nil then
		nameOrHost.Version = version
	end
	VC:Enable(host)
	return VC
end

-- Manually re-run the guild version check (e.g. from a settings button). Safe no-op if VC isn't loaded or
-- EnableVersionCheck was never called. Returns true if the check was triggered.
function lib:TriggerVersionCheck()
	local VC = self._vc
	if VC and VC.TriggerVersionCheck then VC:TriggerVersionCheck(); return true end
	return false
end

-- What GameTooltip will actually accept as a line of text, or nil.
--
-- `if title and title ~= ""` was the old guard and it is not a type check: a table, a boolean or a
-- function all pass it, and `GameTooltip:SetText` is a C function that then raises
-- `bad argument #1 to 'SetText'` -- INSIDE an OnEnter handler, where the consumer sees a red error
-- every time the cursor crosses the control and has nothing in the traceback pointing at their own
-- call site. A widget library must not convert a caller's wrong argument into an error storm on
-- hover; the line is skipped instead, which is visible (no tooltip) without being fatal.
-- Blizzard's NORMAL_FONT_COLOR, the gold every stock header, label and GameFontNormal caption in
-- the client is drawn in.
--
-- THIS IS DELIBERATELY NOT `lib:AccentRGB()`, and the distinction is the whole reason it has a name.
-- The configured accent defaulted to "ffFFD100" -- (1, 0.8196, 0), the same gold to the eye -- until
-- MINOR 36 made the default the suite orange, so the two now differ from the start. They must stay
-- apart: a tooltip
-- header and a GameFontNormal button caption have to keep looking like every OTHER tooltip header
-- and button caption in the player's UI, not like the addon that drew them. The accent is for what
-- the library draws AS the library (the RowList's header underline, its selection tint, the tab
-- glow); this is for what it draws as the CLIENT. Anything that "folds these together" to remove a
-- duplicate literal re-introduces exactly the bug this comment exists to prevent.
--
-- The red is the one a consumer's hand-rolled "why is this disabled" line already used, kept so a
-- player who has seen one refusal recognises the next.
local NORMAL_FONT_GOLD = { 1, 0.82, 0 }
local TIP_REASON_RED   = { 1, 0.3, 0.3 }

local function tooltipText(v)
	local t = type(v)
	if t == "string" then return v ~= "" and v or nil end
	if t == "number" then return tostring(v) end
	return nil
end

-- Attach a GameTooltip OnEnter/OnLeave to `frame`.
--
-- IDEMPOTENT, and that is a fix rather than a preference. `HookScript` is ADDITIVE -- it appends a
-- handler and never replaces one -- so the old version installed a fresh pair of closures on every
-- call, each capturing its own `title`/`body`. A consumer that re-attaches to refresh the text (a
-- tooltip that reports a value the same control changes has to be re-read AFTER the change) ended up
-- with one handler per bump: ten bumps, then one hover, fires eleven handlers. That is where an
-- `11x` error count comes from, and it also means the FIRST call's stale text is still being drawn.
--
-- Now the text lives on the frame and the hooks are installed once, so a later call UPDATES what is
-- shown instead of stacking another handler. The refresh use case gets better, not worse.
-- THE one way this library draws a title/body tooltip on GameTooltip: anchor, white title, wrapped
-- body, show. Returns whether anything was shown. AttachTooltip, the menu rows and the settings gear
-- all draw through this -- they used to carry the same four lines by copy, which agreed only because
-- each was pasted from the last (peer review 2026-09-17 (ii), 2026-09-20). `tooltipText` runs here,
-- so every caller gets the same type guard: a non-string title is skipped, never handed to SetText.
--
-- `opts` (MINOR 33, all optional) extends the same draw rather than forking it: `titleColor` is an
-- {r,g,b} for the title (default white, so every existing caller is unchanged), and `reason` is a
-- line drawn LAST, in red -- what a disabled control would do, then why it cannot be pressed. A
-- tooltip carrying only a reason still draws, which is the case that matters: a greyed button with
-- no other text is exactly when a player wants to know why.
-- `opts.minWidth` (MINOR 36, TOGProfessionMaster inbox c8d6892f): a floor on the tooltip's width for
-- THIS showing, so several paragraphs of help do not become a tall narrow column. GameTooltip is shared
-- with the whole UI and nothing clears SetMinimumWidth by itself, so the value from before is saved --
-- both halves, `width, forced`, as GetMinimumWidth returns them (FrameAPITooltipDocumentation.lua) --
-- and put back when the tooltip hides and before the next showing. Feature-detected.
-- The tooltip's FRAME LEVEL is borrowed the same way (MINOR 42, ClassicCalendar inbox d8a239c7). The
-- library's floating panels -- OpenMenu's levels, the DatePicker -- sit at strata TOOLTIP, level 100+
-- (CreateFloatingFrame). GameTooltip is declared frameStrata="TOOLTIP" with no frameLevel
-- (wow-ui-source-classic_era Blizzard_GameTooltip/Classic/GameTooltip.xml:13), so in the SAME strata
-- the menu's higher level won and a row's tooltip drew underneath the menu it described. When the
-- hovered frame (or any ancestor) is in TOOLTIP strata, the tooltip is lifted TIP_LEVEL_MARGIN above
-- the highest such level -- enough to clear the row's own children and the next submenu down, which
-- is 10 levels deeper per depth -- and its own level is put back on hide, like the width.
--
-- TIP_LEVEL_MAX: SetFrameLevel accepts 0-10000 since 7.0.3 (warcraft.wiki.gg API_Frame_SetFrameLevel,
-- read 2026-10-13; the generated doc gives no range). SetFrameLevel is IsProtectedFunction
-- (SimpleFrameAPIDocumentation.lua:1115-1117, Classic Era) and the wiki says since 11.1.7 insecure code
-- cannot call it on a PROTECTED object in combat. GameTooltip is not declared protected -- neither
-- its own XML (Blizzard_GameTooltip/Classic/GameTooltip.xml:13) nor GameTooltipTemplate
-- (Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22) carries protected="true"; that is the
-- argument. Blizzard's BuffFrame.lua:930 raising GameTooltip's level the same way only shows the call
-- is ordinary on GameTooltip -- it is secure code, so it says nothing about insecure code in combat.
-- The templates those inherit, and
-- GameTooltip:IsProtected() in a live client, are not verified.
local TIP_LEVEL_MARGIN, TIP_LEVEL_MAX = 50, 10000

local function restoreTip()
	local saved = lib._tipMinSaved
	if saved then
		lib._tipMinSaved = nil
		if GameTooltip.SetMinimumWidth then GameTooltip:SetMinimumWidth(saved[1] or 0, saved[2]) end
	end
	local level = lib._tipLevelSaved
	if level then
		lib._tipLevelSaved = nil
		GameTooltip:SetFrameLevel(level)
	end
end

-- Hooked once per tooltip OBJECT, not once per session: an offline harness rebuilds GameTooltip
-- between specs, and a flag would leave the new one without the restore.
local function hookTipRestore()
	if lib._tipHideHooked ~= GameTooltip then
		lib._tipHideHooked = GameTooltip
		GameTooltip:HookScript("OnHide", restoreTip)
	end
end

local function raiseTipWidth(minWidth)
	if not (minWidth and GameTooltip.SetMinimumWidth and GameTooltip.GetMinimumWidth) then return end
	if not lib._tipMinSaved then
		lib._tipMinSaved = { GameTooltip:GetMinimumWidth() }
		hookTipRestore()
	end
	GameTooltip:SetMinimumWidth(lib:ScaledSize(minWidth))
end

-- The highest frame level among `anchor` and its ancestors that are in TOOLTIP strata, or nil when
-- none is. Walks the parents rather than trusting the anchor alone, so a region or a child whose own
-- strata reads differently still finds the floating panel it lives in.
local function tooltipStrataLevel(anchor)
	local top, f = nil, anchor
	while type(f) == "table" and f.GetFrameStrata do
		if f:GetFrameStrata() == "TOOLTIP" and f.GetFrameLevel then
			local l = tonumber(f:GetFrameLevel())
			if l and (not top or l > top) then top = l end
		end
		f = f.GetParent and f:GetParent() or nil
	end
	return top
end

local function raiseTipLevel(anchor)
	if not (GameTooltip.GetFrameLevel and GameTooltip.SetFrameLevel) then return end
	local top = tooltipStrataLevel(anchor)
	if not top then return end
	local want = math.min(top + TIP_LEVEL_MARGIN, TIP_LEVEL_MAX)
	local cur = GameTooltip:GetFrameLevel() or 0
	if cur >= want then return end
	if not lib._tipLevelSaved then
		lib._tipLevelSaved = cur
		hookTipRestore()
	end
	GameTooltip:SetFrameLevel(want)
end

-- For the anchoring paths that do not come through showTooltip: AnchorTooltip above, a TLabel's
-- Control_OnEnter, and RowList's own tooltipOwner branch. Idempotent -- a second call finds the
-- tooltip already high enough and returns.
function lib:_RaiseTipLevel(anchor)
	raiseTipLevel(anchor)
end

local function showTooltip(anchor, title, body, opts)
	local t, b = tooltipText(title), tooltipText(body)
	local reason = opts and tooltipText(opts.reason) or nil
	restoreTip()   -- whatever the last showing raised, before this one decides
	if not (t or b or reason) then return false end
	raiseTipWidth(opts and tonumber(opts.minWidth))
	-- `opts.owner(frame)` (MINOR 34) anchors this ONE tooltip instead of AnchorTooltip, so a RowList
	-- with its own `tooltipOwner` never reaches the session-global one (FGI inbox df5ec079).
	-- An owner that raises falls back to the built-in placement, never to AnchorTooltip, which would
	-- consult that same session-global owner.
	if opts and opts.owner then
		if not safeCall(opts.owner, anchor) then lib:_DefaultAnchor(anchor) end
	else
		lib:AnchorTooltip(anchor)
	end
	-- After anchoring, so nothing the anchoring does can undo it. AnchorTooltip has already raised; this
	-- is for the `opts.owner` branch, and is a no-op after AnchorTooltip.
	raiseTipLevel(anchor)
	-- Whatever the anchoring actually handed the tooltip to -- the hovered frame, or wherever a
	-- consumer's owner function put it. `HideTooltip(anchor)` checks this, so a leave never hides a
	-- tooltip somebody else has taken since (peer review L1).
	if type(anchor) == "table" and GameTooltip.GetOwner then anchor._lagwTipHeldBy = GameTooltip:GetOwner() end
	local tc = opts and opts.titleColor
	if t then GameTooltip:SetText(t, tc and tc[1] or 1, tc and tc[2] or 1, tc and tc[3] or 1) end
	if b then GameTooltip:AddLine(b, nil, nil, nil, true) end
	if reason then GameTooltip:AddLine(reason, TIP_REASON_RED[1], TIP_REASON_RED[2], TIP_REASON_RED[3], true) end
	GameTooltip:Show()
	return true
end

-- PUBLIC as of MINOR 34, so the satellite files draw through the same function: RowList's `button`
-- column shows its `cellTip` here rather than carrying a fifth copy of the four lines above.
-- `W:ShowTooltip(anchor, title, body[, opts])` -> whether anything was shown; pair with `W:HideTooltip()`.
function lib:ShowTooltip(anchor, title, body, opts)
	return showTooltip(anchor, title, body, opts)
end

-- Let `frame` keep firing OnEnter / OnLeave while it is DISABLED.
--
-- ONE FUNCTION BECAUSE IT IS ONE RULE. Both places this library gives a frame a hover tooltip have
-- to apply it -- `AttachTooltip`, which HookScripts onto a caller's frame, and
-- `CreateExplainedButton`, which owns its own OnEnter with SetScript and so cannot go through
-- AttachTooltip. Written out twice (as it was when MINOR 33 first shipped it) the two are joined by
-- nothing but a comment, and the next condition the rule acquires -- a flavour gate, an opt-out, a
-- guard for a frame type that mishandles the flag -- lands on one of them. Peer review filed that as
-- F2 against this library's own MINOR 33 and it is fixed here.
--
-- A DISABLED Button receives no OnEnter / OnLeave at all unless this is set (MINOR 33,
-- DIBSREQ-LAGW-011). VERIFIED IN THE CLASSIC ERA TREE rather than taken on report: the method is
-- declared at `SimpleButtonAPIDocumentation.lua:379` (one non-nilable bool), and Blizzard set it
-- at exactly this pattern in three places -- `UIButtonMixin:SetDisabledTooltip`
-- (UIButtonTemplate.lua:149) turns it on ONLY when a disabled tooltip exists;
-- `CharacterSelectNavBarMixin:TrySetUpStoreButton` (:201) calls `Disable()`, sets it, then installs
-- an OnEnter that shows a tooltip when the button is NOT enabled; and `MainMenuFrameMixin:AddButton`
-- (MainMenuFrameTemplates.lua:24) sets it before `SetEnabled(not isDisabled)` and only then binds
-- the disabled-text OnEnter. That is the rule this call exists for. Without it, a
-- tooltip attached here goes silent the moment its consumer greys the control -- which is exactly
-- when the tooltip explaining WHY it is greyed is wanted. The tooltip is this library's and the
-- disable is the consumer's, so the rule that joins them belongs here, once, rather than being
-- re-discovered at every call site that ever disables a control. Feature-gated because only
-- Button and its subtypes have it; an EditBox or a plain Frame is left alone and does not raise.
--
-- KNOWN SIDE EFFECT: every OTHER OnEnter/OnLeave on that button now fires while it is disabled
-- too, since the flag belongs to the frame, not to this hook. A consumer highlight that assumed
-- a disabled button would never be hovered will now run. That is the client's semantics for the
-- flag, and the reason Blizzard sets it only on buttons that explain themselves.
local function allowHoverWhileDisabled(frame)
	if frame.SetMotionScriptsWhileDisabled then frame:SetMotionScriptsWhileDisabled(true) end
end

-- `opts.owner(frame)` (MINOR 34, optional): anchor this frame's tooltip with it instead of
-- AnchorTooltip. Re-set on every call, like the text, so a pooled frame cannot keep a stale owner.
function lib:AttachTooltip(frame, title, body, opts)
	if not frame then return end
	frame._lagwTipTitle, frame._lagwTipBody = title, body
	frame._lagwTipOwner = opts and opts.owner or nil
	frame._lagwTipMinW = opts and opts.minWidth or nil   -- MINOR 36
	if frame._lagwTipHooked then return end
	frame._lagwTipHooked = true

	allowHoverWhileDisabled(frame)

	frame:HookScript("OnEnter", function(f)
		local o
		if f._lagwTipOwner or f._lagwTipMinW then o = { owner = f._lagwTipOwner, minWidth = f._lagwTipMinW } end
		showTooltip(f, f._lagwTipTitle, f._lagwTipBody, o)
	end)
	frame:HookScript("OnLeave", function(f) lib:HideTooltip(f) end)
end

-- ---------------------------------------------------------------------------
-- Pool-safe additions to an AceGUI widget -- all undone on Release (MINOR 36)
-- ---------------------------------------------------------------------------
-- AceGUI pools the widget AND its frames for every addon in the session. On Release it empties
-- `widget.events` and `widget.userdata`, but it never touches a raw script set on a frame, a flag set
-- on a frame, or a raw frame a consumer parented into `widget.content`. All three ride the pooled frame
-- into the NEXT addon's window: a stale tooltip on someone else's button, a click handler that calls
-- into the wrong addon, a row of our list drawn inside their group. TOGProfessionMaster hand-rolled
-- six variants of the undo (inbox efe864ec, afb62bf8); every consumer can hit the bug.
--
-- ONE MECHANISM FOR ALL OF IT: `OnWidgetRelease` chains onto the widget's OnRelease METHOD, the way
-- PersistWindow does (MINOR 35). It does NOT use the widget's `OnRelease` CALLBACK, because
-- `widget.events` holds one callback per event and that slot belongs to the consumer.

--- Run `fn(widget)` when AceGUI releases `widget`, once, then forget it. `key` names the hook, so a
--- second call with the same key REPLACES it instead of stacking another (nil key = the function
--- itself); `fn = false` removes it. Hooks run newest first, each protected so one error cannot skip
--- the others, and all run BEFORE the widget type's own OnRelease. Returns true when registered.
---
--- A consumer that later REPLACES `widget.OnRelease` without calling the previous one breaks this
--- chain, exactly as it would break AceGUI's own OnRelease. Wrapping is fine; replacing is not.
function lib:OnWidgetRelease(widget, key, fn)
	if type(widget) ~= "table" or (fn ~= false and type(fn) ~= "function") then return false end
	if key == nil then key = fn end
	local rec = rawget(widget, "_lagwRelease")
	if fn == false then
		if rec and rec.fns[key] then rec.fns[key] = nil end
		return true
	end
	if not rec then
		rec = { order = {}, fns = {}, has = {} }
		widget._lagwRelease = rec
		-- The wrapper removes itself when it runs, like PersistWindow's, so nothing stacks on the
		-- pooled widget. `orig` is resolved now: AceGUI:Release reads `widget.OnRelease` at call time.
		local origRaw, orig = rawget(widget, "OnRelease"), widget.OnRelease
		local wrapper
		wrapper = function(w, ...)
			if rawget(w, "OnRelease") == wrapper then w.OnRelease = origRaw end
			if rawget(w, "_lagwRelease") == rec then w._lagwRelease = nil end
			for i = #rec.order, 1, -1 do
				local f = rec.fns[rec.order[i]]
				if f then safeCall(f, w) end
			end
			if orig then return orig(w, ...) end
		end
		widget.OnRelease = wrapper
	end
	-- `has`, not `fns[key]`: a key removed with `false` and added again keeps its one slot in `order`.
	if not rec.has[key] then
		rec.has[key] = true
		rec.order[#rec.order + 1] = key
	end
	rec.fns[key] = fn
	return true
end

-- The undo record: every raw script, mouse flag and motion flag this library changed on a widget's
-- frames, holding the value from BEFORE the first change. Created with its release hook on first use.
local function undoRecord(widget)
	local u = rawget(widget, "_lagwUndo")
	if not u then
		u = { scripts = {}, mouse = {}, motion = {} }
		widget._lagwUndo = u
		lib:OnWidgetRelease(widget, "lagw:undo", function(w) lib:RestoreWidgetFrameScripts(w) end)
	end
	return u
end

-- Save `frame`'s current `event` script as the one to restore, ONCE: a second change keeps the
-- ORIGINAL, never the first change. Returns that original (nil when there was none).
local function saveScript(widget, frame, event)
	local u = undoRecord(widget)
	local saved = u.scripts[frame]
	if not saved then saved = {}; u.scripts[frame] = saved end
	if saved[event] == nil then saved[event] = frame:GetScript(event) or false end
	return saved[event] or nil
end

local function resolveTarget(widget, target)
	if target == nil then return widget.frame end
	if type(target) == "string" then return widget[target] end
	return target
end

--- Set raw scripts on `widget.frame` -- or on `target`, a field name ("editbox", "content") or a
--- frame -- for events the widget has no SetCallback dispatch for, and put back EXACTLY what was
--- there before when AceGUI releases the widget. The restored script is the prior one, not nil, so a
--- constructor-installed dispatcher survives and the next owner's SetCallback still fires.
---
--- `scripts` maps event -> function; `false` restores that event's original now. Calling again for
--- the same event replaces the handler and still restores the ORIGINAL. Returns the frame, or nil.
function lib:WidgetFrameScripts(widget, scripts, target)
	if type(widget) ~= "table" or type(scripts) ~= "table" then return nil end
	local frame = resolveTarget(widget, target)
	if type(frame) ~= "table" or not frame.SetScript then return nil end
	for event, fn in pairs(scripts) do
		local orig = saveScript(widget, frame, event)
		if fn == false then frame:SetScript(event, orig) else frame:SetScript(event, fn) end
	end
	return frame
end

--- Put back every script, mouse flag and motion flag this library changed on `widget`'s frames, now.
--- Runs for you on Release; call it to undo early on a widget that stays in use.
function lib:RestoreWidgetFrameScripts(widget)
	if type(widget) ~= "table" then return end
	local u = rawget(widget, "_lagwUndo")
	if not u then return end
	widget._lagwUndo = nil
	for frame, saved in pairs(u.scripts) do
		for event, orig in pairs(saved) do frame:SetScript(event, orig or nil) end
	end
	for frame, was in pairs(u.mouse) do frame:EnableMouse(was) end
	for frame, was in pairs(u.motion) do frame:SetMotionScriptsWhileDisabled(was) end
	widget._lagwTip = nil
	-- Nothing left to undo; drop the hook so a widget that stays in use carries none.
	self:OnWidgetRelease(widget, "lagw:undo", false)
end

--- Raw frames the consumer parents into `widget` (usually into `widget.content`). On Release each
--- is hidden, has its points cleared and is re-parented to UIParent, so it never rides the pooled
--- frame into another addon's window. The frames are NOT destroyed: the consumer's pool keeps them for
--- the next attach. `frames` is one frame or an array of them; attaching one twice is harmless.
function lib:AttachRawFrames(widget, frames)
	if type(widget) ~= "table" or type(frames) ~= "table" then return end
	local rec = rawget(widget, "_lagwRaw")
	if not rec then
		rec = { list = {}, set = {} }
		widget._lagwRaw = rec
		self:OnWidgetRelease(widget, "lagw:raw", function(w) lib:DetachRawFrames(w) end)
	end
	local list = frames.SetParent and { frames } or frames
	for _, f in ipairs(list) do
		if type(f) == "table" and not rec.set[f] then
			rec.set[f] = true
			rec.list[#rec.list + 1] = f
		end
	end
end

--- Detach every frame `AttachRawFrames` recorded on `widget`, now. Runs for you on Release.
function lib:DetachRawFrames(widget)
	if type(widget) ~= "table" then return end
	local rec = rawget(widget, "_lagwRaw")
	if not rec then return end
	widget._lagwRaw = nil
	for _, f in ipairs(rec.list) do
		if f.Hide then f:Hide() end
		if f.ClearAllPoints then f:ClearAllPoints() end
		if f.SetParent then f:SetParent(UIParent) end
	end
	self:OnWidgetRelease(widget, "lagw:raw", false)
end

-- The widget's own interactive children, besides `widget.frame`, that a tooltip must also answer on:
-- AceGUI's EditBox box, the Dropdown and Button arrow/face, the Slider bar. The LABEL area of an
-- EditBox or Dropdown is `widget.frame` itself, which is why the frame is always a target.
-- `editBox` (capital B) is AceGUI's MultiLineEditBox, whose text area was silent without it.
local WIDGET_TIP_PARTS = { "editbox", "editBox", "button", "slider" }

--- A title/body tooltip on an AceGUI WIDGET, fully undone when the widget is released (MINOR 36,
--- TOGProfessionMaster inbox efe864ec). `AttachTooltip(widget.frame, ...)` is NOT pool-safe: its
--- HookScript cannot be removed, and its text and motion flag stay on the frame for the next owner.
---
--- Answers on `widget.frame` (the label area included; its mouse is enabled if it was not) and on the
--- widget's interactive children. Each frame's existing OnEnter/OnLeave -- the constructor's dispatcher
--- -- still runs first, so a consumer's SetCallback("OnEnter") keeps working. Draws through
--- ShowTooltip (`opts.owner`, `opts.reason`, `opts.titleColor`) and leaves through HideTooltip. Keeps a
--- disabled button's hover, as AttachTooltip does. A second call UPDATES the text and opts.
---
--- On Release every script, the mouse flag and the motion flag go back to their prior values.
function lib:AttachWidgetTooltip(widget, title, body, opts)
	if type(widget) ~= "table" or type(widget.frame) ~= "table" then return end
	local tip = rawget(widget, "_lagwTip")
	if tip then
		tip.title, tip.body, tip.opts = title, body, opts
		return
	end
	tip = { title = title, body = body, opts = opts }
	widget._lagwTip = tip
	local u = undoRecord(widget)

	local targets, seen = { widget.frame }, { [widget.frame] = true }
	for _, k in ipairs(WIDGET_TIP_PARTS) do
		local f = rawget(widget, k)
		if type(f) == "table" and f.SetScript and not seen[f] then
			seen[f] = true
			targets[#targets + 1] = f
		end
	end

	for _, f in ipairs(targets) do
		if f.IsMouseEnabled and not f:IsMouseEnabled() then
			if u.mouse[f] == nil then u.mouse[f] = false end
			f:EnableMouse(true)
		end
		if f.SetMotionScriptsWhileDisabled then
			if u.motion[f] == nil then
				u.motion[f] = f.GetMotionScriptsWhileDisabled and f:GetMotionScriptsWhileDisabled() or false
			end
			f:SetMotionScriptsWhileDisabled(true)
		end
		local origEnter = saveScript(widget, f, "OnEnter")
		local origLeave = saveScript(widget, f, "OnLeave")
		f:SetScript("OnEnter", function(fr, ...)
			if origEnter then origEnter(fr, ...) end
			local t = rawget(widget, "_lagwTip")
			if not t then return end
			local o = t.opts
			showTooltip(fr, t.title, t.body,
				o and { owner = o.owner, reason = o.reason, titleColor = o.titleColor, minWidth = o.minWidth } or nil)
		end)
		f:SetScript("OnLeave", function(fr, ...)
			if origLeave then origLeave(fr, ...) end
			lib:HideTooltip(fr)
		end)
	end
end

-- Clamp a frame's (or AceGUI widget's) minimum size, wrapping modern
-- SetResizeBounds with a legacy SetMinResize fallback.
--
-- `minW`/`minH` are SCALE-1.0 values and are multiplied (MINOR 29): a window's floor is what its
-- rows need, and the rows just got bigger. That multiply is right for a floor made of things this
-- library scales -- rows, icons, its own fonts. A floor that is partly FIXED art (the client's stock
-- AceGUI controls scale only their text; a consumer's own pixel insets scale nothing) is under its
-- content below 1.0 when multiplied whole. A caller with such a floor divides that part out first:
-- TOGBankClassic hands over `minW * math.max(1, s) / s`, so the floor grows above 1.0 and holds at
-- its pixel value below it (their peer-review note on inbox b29617a5, 2026-09-17). A pre-divided
-- number is right only at the scale it was computed at, which is why PersistWindow (MINOR 31) also
-- takes the floor as a FUNCTION of the scale and re-evaluates it on every change.
function lib:ApplyMinResize(frameOrWidget, minW, minH)
	local raw = (frameOrWidget and frameOrWidget.frame) or frameOrWidget
	if not raw then return end
	minW, minH = self:ScaledSize(minW or 0), self:ScaledSize(minH or 0)
	if raw.SetResizeBounds then
		raw:SetResizeBounds(minW, minH)
	elseif raw.SetMinResize then
		raw:SetMinResize(minW, minH)
	end
end

-- ---------------------------------------------------------------------------
-- Resize framework -- MOVED to LibAceGUIWidgets-Resize.lua (2026-09-17)
-- ---------------------------------------------------------------------------
-- `lib:MakeResizable`, `lib:GetResizeHandle`, `lib:ApplyResizeBounds` and the ResizeHandle methods
-- are defined in the satellite, which the TOC and the harness manifest both load immediately after
-- this file. Nothing here changed but its address; read that file for the framework's own docs.
--
-- WHAT THIS FILE STILL NEEDS FROM IT, and why the call sites look the way they do: `ClearFrame` and
-- `GroupFrame` call `lib:MakeResizable` and re-hook `lib.ResizeOnSizeChanged` from their
-- CONSTRUCTORS -- run time, long after both files have loaded, so the load order is safe. The hook
-- is published on the library table precisely because it was a file-local here and a local cannot
-- cross a file boundary.
--
-- If the satellite is missing, `lib:MakeResizable` is nil and the first ClearFrame construction
-- raises on the `assert` at its call site. That is the intended loud failure -- do not add a guard
-- that lets a library with no resize framework build windows that silently cannot be resized.

-- ---------------------------------------------------------------------------
-- Window persistence -- position and size, from a table the CONSUMER owns (MINOR 28)
-- ---------------------------------------------------------------------------
-- Make an AceGUI window widget (a ClearFrame, or AceGUI's own Frame -- anything with SetStatusTable)
-- remember its position AND size across open/close and /reload, from a table the consumer owns: its
-- SavedVariables slot, an AceDB char/profile sub-table, whatever. The library never touches
-- SavedVariables itself and keeps NO copy of the coordinates: the consumer's table is handed straight
-- to `SetStatusTable`, so AceGUI's own drag / resize writes land in the consumer's save, and a consumer
-- that clears `top`/`left` from that table and calls `ApplyStatus` (a "recenter") sees exactly that.
--
--   W:PersistWindow(window, MyDB.char.windows.mailbox, {
--       width = 560, height = 480,       -- applied when the table has no size yet
--       minWidth = 420, minHeight = 300, -- the floor: resize bounds AND a raise of a saved size
--       -- or, for a floor that is partly fixed art (MINOR 31), a function of the scale:
--       -- minWidth = function(s) return 420 * math.max(1, s) / s end
--   })
--
-- Requested by TOGBankClassic (inbox 3ba9f0f7, 2026-09-13): they had spelled `SetStatusTable(pos.<key>)`
-- five different ways across five windows, and the fifth -- the mailbox -- had none, which is how it
-- opened at 560x480 mid-screen on every open (their MAILBOX-PERSIST-001). Every AceGUI-window addon in
-- the fleet carries the same five lines.
--
-- THE FLOOR APPLIES TO THE SAVED SIZE, NOT ONLY TO THE DRAG. AceGUI applies a status table as-is, so a
-- saved 300x200 under a 420x300 floor comes back as a window narrower than its own minimum, and a
-- window that cannot be dragged wider than it already is has no way out. A saved size under the floor
-- is raised to it before the table is applied.
--
-- `saved == nil` means "no save": a fresh table with the defaults is applied and returned, so a caller
-- can treat the return value uniformly. Returns nil, and does nothing, for a widget with no
-- SetStatusTable -- a raw frame wants `MakeResizable` with its `status` option instead.
--
-- THE SAVED SIZE IS REAL PIXELS AND IS NEVER SCALED (MINOR 29): the user sized the window, and a
-- saved 640x480 is 640x480 at every scale, so a scale change cannot make a window jump. Only the
-- FLOOR (`minWidth`/`minHeight`, scale-1.0 values like every minimum here) is multiplied, so a saved
-- size under the enlarged floor is raised to it -- the floor being what the enlarged rows need.
-- `width`/`height` (the defaults for an empty table) are pixels too, for the same reason.
--
-- AND THE FLOOR FOLLOWS A LIVE SCALE CHANGE FOR EVERY WIDGET KIND (MINOR 31). Until now only a window
-- with a resize handle (a ClearFrame) re-applied its floor when the scale moved, because the handle
-- carries its own scale listener; AceGUI's own Frame -- the kind the 3ba9f0f7 request was written for
-- -- took the no-handle branch and registered nothing, so at 200% it kept its 100% bounds and size with
-- twice the text inside until the next reload (TOGBankClassic peer review b29617a5, traced from a
-- player's report). Now a record on the widget re-runs the same raise-and-bounds on every change, on
-- both branches: with a handle the handle's listener re-applies the bounds and the record's raise is
-- the same raise it would do (idempotent whichever runs first); without one the record re-applies the
-- bounds itself. The status table is raised with the frame, so the window a scale change grew is the
-- window the next open restores -- a size only saved on the next drag was a MINOR-29 known cost.
-- A second PersistWindow on the same widget re-points the record; weak-keyed like every listener.
--
-- WHICH FLOORS THE MULTIPLY IS RIGHT FOR: see ApplyMinResize above. A floor that is partly fixed art
-- is passed as a FUNCTION, `minWidth = function(scale) return <a scale-1.0 value> end`, evaluated at
-- the call and again on every scale change -- a pre-divided NUMBER is right only at the scale it was
-- computed at, and a consumer re-calling PersistWindow from its own scale listener would race this
-- one (whichever ran first, the stale floor could raise the window past the fresh one, and nothing
-- shrinks). The function form has no such race: both listeners read the same fresh value.
local function floorValue(v)
	-- A floor function that raises is reported and resolves to nil. Its axis then gets the window's OWN
	-- minimum, the one recorded before the first PersistWindow (lib._OwnFloor) -- never a floor it
	-- resolved to earlier, a previous PersistWindow's floor or a previous profile's: on a resize handle
	-- through lib._HandleFloor, without one as the record's kept bound. (A frame with no bound to record
	-- keeps its current one.) An axis with NO floor asked keeps what the handle or the frame already has.
	if type(v) == "function" then
		local ok, r = safeCall(v, lib:GetScale())
		v = ok and r or nil
	end
	return tonumber(v)
end

-- Whether a floor was ASKED for, from the resolved values and the raw options: a floor function that
-- raised resolves to nil but must still register the scale listener, or it is never tried again
-- (Peer Review NEW-6 / R2 on dfd1e1a5). PersistWindow and SetWindowProfile both gate on this. A method,
-- not a file-scope local: the main chunk sits near Lua's local-variable limit (Tests/localheadroom_spec.lua).
function lib._FloorAsked(minW, minH, rawW, rawH)
	return (minW or minH or type(rawW) == "function" or type(rawH) == "function") and true or false
end

-- ONE OWNER OF A WINDOW'S POSITION. PersistWindow owns it through the AceGUI status table; DockWindow
-- owns it through an anchor to the target. Both on one window fight -- each SetPoint undoes the other's
-- on the next show, drop or scale change -- and before MINOR 32 nothing enforced the exclusion the
-- docstrings described. Named three times by peer review (2026-09-15, 09-17 twice); this is the guard.
-- The SECOND call refuses and says so once per window, naming the call to drop, rather than silently
-- taking over: a consumer that hits this has a real conflict, and a message that names both calls is
-- the whole fix. The raw frame is the identity, because PersistWindow takes the AceGUI widget and
-- DockWindow takes `widget.frame`, and a consumer could hand the same window to both.
local function otherOwner(frame, theirsPresent, mineCall, theirsCall)
	if type(frame) ~= "table" or not theirsPresent then return false end
	local key = "_lagwOwnerWarned" .. mineCall
	if not frame[key] then
		frame[key] = true
		lib:_Say(mineCall .. " refused: this window's position is already owned by " ..
			theirsCall .. ". One window uses one of them; drop the other call.")
	end
	return true
end

-- The screen's width and height in `frame`'s own units: UIParent's size in UIParent units, through the
-- two effective scales. A window scaled to 0.5 has twice as many of its own units across the screen.
-- (MINOR 36, with ClampWindow and SetWindowScale further down.)
local function screenInFrameUnits(frame)
	local us = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
	local fs = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
	return (UIParent:GetWidth() or 0) * us / fs, (UIParent:GetHeight() or 0) * us / fs
end

-- Put `frame` at left/top, in its own units, with AceGUI's own TOP/BOTTOM + LEFT/LEFT anchor pair, so
-- the status table a ClearFrame or AceGUI Frame writes reads the same numbers back.
local function placeTopLeft(frame, left, top)
	frame:ClearAllPoints()
	frame:SetPoint("TOP", UIParent, "BOTTOM", 0, top)
	frame:SetPoint("LEFT", UIParent, "LEFT", left, 0)
end

-- A window's own scale (MINOR 36). Separate from W:SetScale, the session-wide size multiplier for fonts
-- and geometry (0.8 - 2.0, an accessibility floor); this is one window's frame:SetScale, which may go
-- below it. The library's scale still multiplies inside the window. Here, above PersistWindow, because
-- PersistWindow re-applies a saved one.
local WINDOW_SCALE_MIN, WINDOW_SCALE_MAX = 0.5, 1.5

local function applyWindowScale(widget, factor)
	local frame = widget.frame
	local old = frame:GetScale() or 1
	if not rawget(widget, "_lagwScaleHooked") then
		widget._lagwScaleHooked = true
		lib:OnWidgetRelease(widget, "lagwWindowScale", function(w)
			w._lagwScaleHooked = nil
			w.frame:SetScale(1)
		end)
	end
	-- Anchor offsets are in the frame's own units, so every anchor is re-applied as it was -- the same
	-- point, the same relative frame and point -- with its offsets times old/new, which keeps each anchored
	-- point at the same SCREEN spot. Re-applying the window's OWN anchors, rather than re-placing it
	-- TOP/LEFT on UIParent, is what keeps a DockWindow or a consumer-anchored window attached to what it
	-- was attached to (Peer Review, audit thread 231f14e7 item 4). GetPoint's returns are handed back to
	-- SetPoint unchanged: the docs give both `relativeTo` the same type (Classic Era
	-- SimpleScriptRegionResizingAPIDocumentation.lua:76 and :131), and Blizzard's FrameCloneManager.lua:98
	-- makes the same round trip.
	local left, top = frame:GetLeft(), frame:GetTop()
	local points = {}
	for i = 1, (frame.GetNumPoints and frame:GetNumPoints()) or 0 do points[i] = { frame:GetPoint(i) } end
	frame:SetScale(factor)
	if old ~= factor and #points > 0 then
		local k = old / factor
		frame:ClearAllPoints()
		for _, p in ipairs(points) do
			frame:SetPoint(p[1], p[2], p[3], (p[4] or 0) * k, (p[5] or 0) * k)
		end
		if left and top and type(widget.status) == "table" then
			widget.status.left, widget.status.top = left * k, top * k
		end
	end
end

local function Persist_OnScaleChanged(new, old, rec)
	local widget = rec.widget
	local frame = widget.frame
	if type(frame) ~= "table" or type(frame.GetWidth) ~= "function" then return end
	local minW, minH = floorValue(rec.minW), floorValue(rec.minH)
	local handle = lib:GetResizeHandle(widget)
	if handle then
		-- A function floor has a new value now, written to the handle; an axis whose floor raised gets the
		-- window's own minimum (lib._HandleFloor). The handle's own listener re-applies handle.minW and
		-- grows the window to it, so while this record follows the scale it stands in for that listener
		-- and runs it AFTER the write (lib._FollowScale): SetScale walks listeners in no fixed order, and
		-- run first it grew the window to a stale floor that nothing shrinks (Peer Review F1, reply
		-- 15d09da2 on 322e50a0). Re-taken here in case a later MakeResizable re-registered it.
		lib._FollowScale(rec, Persist_OnScaleChanged, handle)
		local fW, fH = lib._HandleFloor(rec, handle, minW, minH)
		handle:SetBounds(fW, fH, handle.maxW, handle.maxH)
		if rec.handleFn and lib._HandleLive(handle) then rec.handleFn(new, old, handle) end
	else
		lib:ApplyResizeBounds(widget, minW or rec.keptW, minH or rec.keptH)
	end
	local floorW, floorH = minW and lib:ScaledSize(minW), minH and lib:ScaledSize(minH)
	if floorW and (frame:GetWidth()  or 0) < floorW then frame:SetWidth(floorW)  end
	if floorH and (frame:GetHeight() or 0) < floorH then frame:SetHeight(floorH) end
	local status = rec.status
	if type(status) == "table" then
		if floorW and tonumber(status.width)  and tonumber(status.width)  < floorW then status.width  = floorW end
		if floorH and tonumber(status.height) and tonumber(status.height) < floorH then status.height = floorH end
	end
end

function lib:PersistWindow(widget, saved, opts)
	if type(widget) ~= "table" or type(widget.SetStatusTable) ~= "function" then return nil end
	local frame = widget.frame
	if otherOwner(frame, type(frame) == "table" and frame._lagwDock, "PersistWindow", "DockWindow") then return nil end
	opts = opts or {}
	local status = type(saved) == "table" and saved or {}
	local minW, minH = floorValue(opts.minWidth), floorValue(opts.minHeight)
	local floorW, floorH = minW and self:ScaledSize(minW), minH and self:ScaledSize(minH)

	-- Fill, then raise. `tonumber` rather than a nil check so a corrupted string in a saved table
	-- ("560px") does not survive into SetWidth.
	if not tonumber(status.width)  then status.width  = tonumber(opts.width)  or 700 end
	if not tonumber(status.height) then status.height = tonumber(opts.height) or 500 end
	if floorW and tonumber(status.width)  < floorW then status.width  = floorW end
	if floorH and tonumber(status.height) < floorH then status.height = floorH end

	-- A window scale saved by SetWindowScale (MINOR 36) goes on BEFORE the position: the saved left/top
	-- were written in the window's own units at that scale.
	local ws = tonumber(status.windowScale)
	if ws and type(frame) == "table" and frame.SetScale then
		applyWindowScale(widget, math.max(WINDOW_SCALE_MIN, math.min(WINDOW_SCALE_MAX, ws)))
	end

	widget:SetStatusTable(status)

	-- The record the scale listener re-runs from. Re-pointed rather than rebuilt on a second call, so
	-- the listener table holds one entry per widget however many times it is persisted.
	local rec = widget._lagwPersist
	if not rec then
		rec = { widget = widget }
		widget._lagwPersist = rec
		-- What ForgetWindow hands back (MINOR 35): the bounds as they were BEFORE this record touched
		-- them, captured once so a second PersistWindow does not record its own floor as "original".
		local handle = self:GetResizeHandle(widget)
		if handle then
			rec.origHandle = { handle.minW, handle.minH }
		elseif type(frame) == "table" then
			if frame.GetResizeBounds then rec.origFrame = { frame:GetResizeBounds() }
			elseif frame.GetMinResize then rec.origFrame = { frame:GetMinResize() } end
			-- The frame answers PIXELS; SetWindowProfile divides by this to get the scale-1.0 minimum back.
			rec.origScale = self:GetScale()
		end
		-- And forget on Release, so no consumer has to remember to: the instance's OnRelease is wrapped
		-- once and removes ITSELF when it runs, so a consumer that cleared `_lagwPersist` by hand (as
		-- TOGBank's pre-35 stand-in does) still leaves no wrapper behind to stack on the pooled widget.
		-- AceGUI:Release reads `widget.OnRelease` at call time.
		local origRaw, orig = rawget(widget, "OnRelease"), widget.OnRelease
		local wrapper
		wrapper = function(w, ...)
			if rawget(w, "OnRelease") == wrapper then w.OnRelease = origRaw end
			lib:ForgetWindow(w)
			if orig then return orig(w, ...) end
		end
		widget.OnRelease = wrapper
		rec.wrapper, rec.origOnRelease = wrapper, origRaw
	end
	-- The RAW options, so a function floor is re-evaluated at each change rather than frozen here.
	rec.status, rec.minW, rec.minH, rec.keptW, rec.keptH = status, opts.minWidth, opts.minHeight, nil, nil

	-- The bounds. A ClearFrame already carries a resize handle with its own bounds; re-point that
	-- rather than setting the frame's bounds underneath it, so `handle.minW` and the frame agree.
	local handle = self:GetResizeHandle(widget)
	if lib._FloorAsked(minW, minH, opts.minWidth, opts.minHeight) then
		if handle then
			local fW, fH = lib._HandleFloor(rec, handle, minW, minH)
			handle:SetBounds(fW, fH, handle.maxW, handle.maxH)
		else
			-- One floor given, not both: keep the frame's other bound rather than resetting it to 0,
			-- which `ApplyResizeBounds(w, 420, nil)` would do (`minH or 0`). Found by the session's own
			-- audit, not by a consumer -- every caller so far passes both.
			-- The frame answers PIXELS and ApplyResizeBounds multiplies, so the kept bound is divided
			-- back to a scale-1.0 value first or it would be scaled twice. The kept value is remembered
			-- on the record so a later scale change re-applies the same pair, not a re-read of a bound
			-- the earlier change already scaled.
			-- Per axis, the same rule as lib._HandleFloor: where a floor was ASKED (the raw option is set),
			-- the kept bound is the window's OWN minimum recorded before the first PersistWindow, so a floor
			-- that raises -- now or on a later scale change -- never reads as the frame's current bound,
			-- which on a second PersistWindow is the first call's floor (Peer Review F2, reply 15d09da2 on
			-- 322e50a0). Where none was asked, the frame's current bound is kept, as before (persist_spec).
			local curW, curH = 0, 0
			if type(frame) == "table" then
				if frame.GetResizeBounds then curW, curH = frame:GetResizeBounds()
				elseif frame.GetMinResize then curW, curH = frame:GetMinResize() end
			end
			local s = self:GetScale()
			rec.keptW, rec.keptH = (curW or 0) / s, (curH or 0) / s
			if rec.origFrame then
				local ownW, ownH = lib._OwnFloor(rec)
				if rec.minW ~= nil then rec.keptW = ownW end
				if rec.minH ~= nil then rec.keptH = ownH end
			end
			self:ApplyResizeBounds(widget, minW or rec.keptW, minH or rec.keptH)
		end
		lib._FollowScale(rec, Persist_OnScaleChanged, handle)
	else
		lib._FollowScale(rec, nil, handle)   -- no floor asked for this time: nothing to re-apply
	end
	-- A save from a larger screen or a smaller UI scale may no longer fit (MINOR 36, inbox 72e8dd4b).
	self:ClampWindow(widget)
	return status
end

-- Save the frame's size under the active size profile's key, when that profile is resizable. A locked
-- profile saves nothing. Shared by SetWindowProfile's switch-away and ForgetWindow, so the two agree.
local function saveResizableProfile(rec, frame)
	if rec.profile == nil or not rec.profileResizable then return end
	if type(rec.status) ~= "table" or type(frame) ~= "table" or type(frame.GetWidth) ~= "function" then return end
	rec.status.profiles = type(rec.status.profiles) == "table" and rec.status.profiles or {}
	rec.status.profiles[rec.profile] = { width = frame:GetWidth(), height = frame:GetHeight() }
end

-- The window's OWN minimum, scale-1.0, as it was before PersistWindow touched it: what a size profile's
-- axis with no floor falls back to. The handle keeps scale-1.0 numbers; the frame answered pixels at
-- rec.origScale, so those are divided back. Nothing recorded (a widget with neither) is 0.
-- A method, not a file-scope local: the main chunk sits near Lua's local-variable limit
-- (Tests/localheadroom_spec.lua).
function lib._OwnFloor(rec)
	if rec.origHandle then return rec.origHandle[1] or 0, rec.origHandle[2] or 0 end
	local o, s = rec.origFrame, rec.origScale or 1
	if o then return (o[1] or 0) / s, (o[2] or 0) / s end
	return 0, 0
end

-- The bounds a resize handle gets from a record, per axis: the floor where it resolved; the window's own
-- minimum (lib._OwnFloor) where a floor was ASKED for (rec.minW / rec.minH, the raw option) but resolved to
-- nil -- a function that raised -- so its last resolved value is never left on the handle (Peer Review F1,
-- reply 15d09da2 on 322e50a0); and handle.minW / minH only where no floor was asked, so a bound the
-- consumer set on the handle survives. Callers set rec.minW / rec.minH to the raw options first.
function lib._HandleFloor(rec, handle, minW, minH)
	local ownW, ownH = lib._OwnFloor(rec)
	if minW == nil then
		if rec.minW ~= nil then minW = ownW else minW = handle.minW end
	end
	if minH == nil then
		if rec.minH ~= nil then minH = ownH else minH = handle.minH end
	end
	return minW, minH
end

-- Whether a resize handle is still live: Destroy clears its driver's OnUpdate and its scale listener, and
-- MakeResizable sets both back.
function lib._HandleLive(handle)
	local d = handle and handle.driver
	return (d and d.GetScript and d:GetScript("OnUpdate")) and true or false
end

-- Register (fn) or drop (nil) a record's scale listener. On the handle path the record stands in for the
-- handle's OWN listener while it follows the scale -- taken out of the table and kept on rec.handleFn, run
-- by Persist_OnScaleChanged after it has written the handle's bounds -- because SetScale walks listeners
-- in no fixed order and the handle's, run first, grew the window to a floor the record was about to drop
-- (Peer Review F1, reply 15d09da2 on 322e50a0). Dropping the record hands it back, unless the handle was
-- Destroy()ed since (which unregisters it on purpose) or something re-registered one meanwhile.
function lib._FollowScale(rec, fn, handle)
	local L = lib._scaleListeners
	L[rec] = fn
	if fn and handle then
		if L[handle] then rec.handleFn, L[handle] = L[handle], nil end
	elseif rec.handleFn then
		if handle and L[handle] == nil and lib._HandleLive(handle) then L[handle] = rec.handleFn end
		rec.handleFn = nil
	end
end

-- Undo PersistWindow on `widget` (MINOR 35): drop its record and scale listener, and put the resize
-- bounds back to what they were before the first PersistWindow. Returns true when there was a record.
--
-- AceGUI pools the widget AND its frame for every addon in the session, and the record, its listener
-- and the re-pointed bounds all live on them -- so without this a released window's next scale change
-- raised whatever window the pool handed that frame to next (TOGBankClassic inbox 3d96003a: a released
-- Guild Bank window grew from 900 to 1568 wide on SetScale(2)).
--
-- CALLED FOR YOU ON RELEASE: PersistWindow wraps the widget's OnRelease, so `widget:Release()` forgets
-- it. Calling this first is harmless, and is the way to stop persisting a window that stays open.
--
-- THE RESIZE HANDLE IS RESTORED, NOT DESTROYED. ClearFrame and GroupFrame build theirs once, in the
-- constructor, so a destroyed handle leaves the pooled frame with no grips for its next owner. Its floor
-- goes back to the pre-persist value and its own scale listener, which the record stood in for while it
-- followed the scale (lib._FollowScale), is handed back, because following the scale with that floor is
-- how every ClearFrame behaves. A handle a consumer added with MakeResizable is that
-- consumer's to Destroy.
function lib:ForgetWindow(widget)
	if type(widget) ~= "table" then return false end
	local rec = rawget(widget, "_lagwPersist")
	if not rec then return false end
	-- A resizable size profile keeps the size the window closed at (MINOR 36, TOGProfessionMaster inbox
	-- 7481d3a5). Its size was only saved on a switch AWAY, so a window dragged and then closed on that
	-- profile reopened at the size of the last switch. Before the record goes, while the frame still has
	-- the player's size -- the Release wrapper runs this ahead of the widget's own OnRelease.
	saveResizableProfile(rec, widget.frame)
	widget._lagwPersist = nil
	local handle = self:GetResizeHandle(widget)
	lib._FollowScale(rec, nil, handle)   -- and the handle gets its own scale listener back
	-- Only while the wrapper is still the one installed: never overwrite an OnRelease set since.
	if rec.wrapper and rawget(widget, "OnRelease") == rec.wrapper then
		widget.OnRelease = rec.origOnRelease
	end
	if handle and rec.origHandle then
		handle:SetBounds(rec.origHandle[1], rec.origHandle[2], handle.maxW, handle.maxH)
	elseif rec.origFrame and not handle then   -- a handle added after the persist owns the bounds now
		-- Pixels, read from the frame before the record scaled anything: applied raw, never re-scaled.
		local frame, o = widget.frame, rec.origFrame
		if type(frame) == "table" then
			if frame.SetResizeBounds then frame:SetResizeBounds(o[1] or 0, o[2] or 0, o[3], o[4])
			elseif frame.SetMinResize then frame:SetMinResize(o[1] or 0, o[2] or 0) end
		end
	end
	-- A locked size profile (MINOR 36) turned resizing off; the next owner of the pooled frame gets it back
	-- as it was before the first profile.
	if rec.resizeOrig then
		local o = rec.resizeOrig
		if handle then handle:SetEnabled(o.handle ~= false)
		elseif widget.EnableResize then widget:EnableResize(true) end
		local frame = widget.frame
		if type(frame) == "table" and frame.SetResizable and o.frame ~= nil then frame:SetResizable(o.frame) end
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Keeping a window on screen, size profiles, background opacity, window scale (MINOR 36)
-- ---------------------------------------------------------------------------
-- TOGProfessionMaster inbox 72e8dd4b, ae090bd5 and e5e1586a, 2026-09-26: three things their main window
-- does by hand (GUI/MainWindow.lua, from their survey), each of which has to be undone on Release for the
-- same reason PersistWindow's record is -- AceGUI pools the frame for the next addon.

--- `W:ClampWindow(widget)` (MINOR 36): cap a window's size to the screen and move it fully onto it, after
--- a resolution or UI-scale change left a saved size or position that no longer fits. Only what is off
--- the screen changes; the floor is never undercut unless the screen itself is smaller than it. The
--- widget's status table (`widget.status`) is updated to match, so the next open restores the fixed
--- place. PersistWindow and SetWindowProfile call it on every restore. Returns whether anything moved.
function lib:ClampWindow(widget)
	local frame = type(widget) == "table" and (widget.frame or widget)
	if type(frame) ~= "table" or type(frame.GetLeft) ~= "function" then return false end
	local sw, sh = screenInFrameUnits(frame)
	if sw <= 0 or sh <= 0 then return false end
	local status = type(widget.status) == "table" and widget.status or nil
	local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
	local changed = false
	if w > sw then w = sw; frame:SetWidth(w); changed = true end
	if h > sh then h = sh; frame:SetHeight(h); changed = true end
	if changed and status then status.width, status.height = w, h end
	local left, top = frame:GetLeft(), frame:GetTop()
	if left and top then
		local nl = math.max(0, math.min(left, sw - w))
		local nt = math.min(sh, math.max(top, h))
		if nl ~= left or nt ~= top then
			placeTopLeft(frame, nl, nt)
			if status then status.left, status.top = nl, nt end
			changed = true
		end
	end
	return changed
end

--- `W:SetWindowProfile(widget, key, { width, height, resizable, minWidth, minHeight })` (MINOR 36): one
--- PERSISTED window that switches between named size profiles -- TOGProfessionMaster's main window, where
--- some tabs are a fixed size and the browsing tabs share a size the player chose.
---
---   * A LOCKED profile (`resizable` false) snaps to `width` x `height` and turns resizing off: the grips
---     hide and a drag is refused (the frame is made non-resizable).
---   * A RESIZABLE profile restores ITS OWN saved size from `saved.profiles[key]`, else `width`/`height`,
---     raised to its floor; `minWidth`/`minHeight` are its floor (scale-1.0, a number or a function of
---     the scale, exactly as PersistWindow's) and follow the scale.
---   * Leaving a resizable profile saves the frame's size under its key, and so does releasing the window
---     (ForgetWindow) while it is active. A locked profile's size is never
---     saved anywhere but the ordinary `width`/`height` of the table, so it cannot leak into a resizable
---     profile's save.
---   * Position is shared by every profile; the window is clamped to the screen after each switch.
---
--- Needs PersistWindow first (the profiles live in its table). Returns false, doing nothing, otherwise.
--- ForgetWindow, and so Release, turns resizing back to how it was before the first profile.
function lib:SetWindowProfile(widget, key, prof)
	local rec = type(widget) == "table" and rawget(widget, "_lagwPersist")
	if not rec or key == nil or type(prof) ~= "table" then return false end
	local frame, status = widget.frame, rec.status
	status.profiles = type(status.profiles) == "table" and status.profiles or {}
	local handle = self:GetResizeHandle(widget)

	saveResizableProfile(rec, frame)
	local resizable = prof.resizable and true or false
	rec.profile, rec.profileResizable = key, resizable

	if not rec.resizeOrig then
		rec.resizeOrig = {
			handle = handle and handle.enabled,
			frame = frame.IsResizable and frame:IsResizable() or nil,
		}
	end
	if handle then handle:SetEnabled(resizable)
	elseif widget.EnableResize then widget:EnableResize(resizable) end
	if frame.SetResizable then frame:SetResizable(resizable) end

	local w, h
	if resizable then
		local saved = status.profiles[key]
		w = saved and tonumber(saved.width) or tonumber(prof.width) or frame:GetWidth()
		h = saved and tonumber(saved.height) or tonumber(prof.height) or frame:GetHeight()
		-- The profile's floor becomes the record's, so the scale listener re-applies THIS profile's.
		rec.minW, rec.minH, rec.keptW, rec.keptH = prof.minWidth, prof.minHeight, nil, nil
		local minW, minH = floorValue(prof.minWidth), floorValue(prof.minHeight)
		-- Bounds go on EVERY resizable switch, per axis (Peer Review NEW-5 on 3028f298): the profile's floor
		-- where it resolves, else the window's own minimum. Applying them only when the profile had a floor
		-- left a floorless profile on the previous profile's floor -- the player could not drag narrower
		-- than BROWSE's 600, and the handle's scale listener grew the window to it.
		local ownW, ownH = lib._OwnFloor(rec)
		local fW, fH = minW or ownW, minH or ownH
		if handle then
			handle:SetBounds(fW, fH, handle.maxW, handle.maxH)
		else
			self:ApplyResizeBounds(widget, fW, fH)
			rec.keptW, rec.keptH = ownW, ownH   -- what the scale listener re-applies for an axis with no floor
		end
		if w < self:ScaledSize(fW) then w = self:ScaledSize(fW) end
		if h < self:ScaledSize(fH) then h = self:ScaledSize(fH) end
		-- With a handle, only a profile floor (resolved or raising) needs this record's listener: the
		-- handle's own listener follows the window's own minimum. Without one, the bounds were applied
		-- above through ApplyResizeBounds, which multiplies, so every resizable profile registers and its
		-- kept axes follow the scale -- one rule whether the profile has a floor or not (Peer Review R3 on
		-- dfd1e1a5; a floorless profile used to keep the switch-time scale's bound).
		local follow = not handle or lib._FloorAsked(minW, minH, prof.minWidth, prof.minHeight)
		lib._FollowScale(rec, follow and Persist_OnScaleChanged or nil, handle)
	else
		w = tonumber(prof.width) or frame:GetWidth()
		h = tonumber(prof.height) or frame:GetHeight()
		rec.minW, rec.minH = nil, nil
		lib._FollowScale(rec, nil, handle)   -- a fixed size has no floor to follow
	end
	status.width, status.height = w, h
	widget:SetWidth(w)
	widget:SetHeight(h)
	if widget.DoLayout then widget:DoLayout() end
	self:ClampWindow(widget)
	return true
end

--- The profile key SetWindowProfile last applied, or nil.
function lib:GetWindowProfile(widget)
	local rec = type(widget) == "table" and rawget(widget, "_lagwPersist")
	return rec and rec.profile or nil
end

-- Background opacity. The frames a widget paints its BACKGROUND on: the window's own backdrop, and the
-- `border` / `treeframe` backdrops AceGUI's TabGroup, InlineGroup and TreeGroup draw their panes with.
-- Text, icons, buttons and the frame's SetAlpha are never touched. Each widget remembers the stock colour
-- of the frames IT owns and puts them back on ITS own Release, because a pane can be released (a tab
-- switch) while the window stays open, and it goes back to the pool then.
local function restoreOpacity(w)
	local st = rawget(w, "_lagwOpacity")
	if not st then return end
	w._lagwOpacity, w._lagwWindowAlpha = nil, nil
	for f, c in pairs(st) do f:SetBackdropColor(c[1], c[2], c[3], c[4]) end
end

local function fadeFrames(owner, alpha, ...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if type(f) == "table" and f.GetBackdropColor and f.SetBackdropColor then
			local st = rawget(owner, "_lagwOpacity")
			if not st then
				st = {}
				owner._lagwOpacity = st
				lib:OnWidgetRelease(owner, "lagwOpacity", restoreOpacity)
			end
			local c = st[f]
			if not c then
				c = { f:GetBackdropColor() }
				st[f] = c
			end
			f:SetBackdropColor(c[1], c[2], c[3], (c[4] or 1) * alpha)
		end
	end
end

local function fadeTree(w, alpha, isWindow)
	-- The pane a container draws is usually the frame its `content` sits in: InlineGroup keeps that frame
	-- only as a local (AceGUIContainer-InlineGroup.lua, `border`), so `content:GetParent()` is the one way
	-- to reach it. A frame without a backdrop is skipped, and one listed twice is faded once from stock.
	local pane = type(w.content) == "table" and w.content.GetParent and w.content:GetParent() or nil
	fadeFrames(w, alpha, isWindow and w.frame or nil, w.border, w.treeframe, pane)
	for _, child in ipairs(w.children or {}) do fadeTree(child, alpha, false) end
end

--- `W:SetWindowOpacity(widget, alpha)` (MINOR 36): fade a window's BACKGROUND fills to `alpha` (0..1) --
--- its backdrop and the pane backdrops of every TabGroup, InlineGroup and TreeGroup inside it now --
--- while text, icons, buttons and borders stay fully opaque. Idempotent; 1 is the stock colours. A
--- pane drawn LATER (a tab selected after the call) is not reached: call it again after drawing a tab,
--- with `W:GetWindowOpacity(widget)`. Every faded frame is put back exactly on its widget's Release.
function lib:SetWindowOpacity(widget, alpha)
	if type(widget) ~= "table" or type(widget.frame) ~= "table" then return false end
	alpha = math.max(0, math.min(1, tonumber(alpha) or 1))
	fadeTree(widget, alpha, true)
	widget._lagwWindowAlpha = alpha
	return true
end

function lib:GetWindowOpacity(widget)
	return type(widget) == "table" and rawget(widget, "_lagwWindowAlpha") or 1
end

--- `W:SetWindowScale(widget, factor)` (MINOR 36): scale ONE window, clamped to 0.5 - 1.5. Its top-left
--- stays where it is on screen and the window is then clamped onto the screen. Saved as `windowScale` in
--- the PersistWindow table when there is one, and re-applied by PersistWindow before the position, so
--- a saved position is read in the units it was written in. Back to 1 on Release. Resize floors are in
--- the window's own units, so they shrink and grow with it, like everything inside. Returns the factor.
function lib:SetWindowScale(widget, factor)
	if type(widget) ~= "table" or type(widget.frame) ~= "table" or not widget.frame.SetScale then return nil end
	factor = math.max(WINDOW_SCALE_MIN, math.min(WINDOW_SCALE_MAX, tonumber(factor) or 1))
	applyWindowScale(widget, factor)
	local rec = rawget(widget, "_lagwPersist")
	if rec and type(rec.status) == "table" then rec.status.windowScale = factor end
	self:ClampWindow(widget)
	return factor
end

function lib:GetWindowScale(widget)
	local frame = type(widget) == "table" and widget.frame
	return type(frame) == "table" and frame.GetScale and frame:GetScale() or 1
end

-- ---------------------------------------------------------------------------
-- Docking -- a window that sits against another frame's edge (MINOR 30)
-- ---------------------------------------------------------------------------
-- ClassicCalendar inbox 4d698ce3, item 6, generalised from their World Buff window
-- (WorldBuff.lua:402-525), and every rule here is theirs:
--
--   local h = W:DockWindow(myWindow, {
--       to = CalendarFrame, point = "TOPLEFT", relPoint = "TOPRIGHT", x = 0, y = -16,
--       snapDistance = 40,          -- scale-1.0 reach for a drop to dock, in the window's units
--       status = MyDB.worldBuffWindow,   -- the CONSUMER's table: docked (bool|nil), left, top
--   })
--
--   * DOCKED IS THE DEFAULT: only `status.docked == false` means undocked, so an install with no value
--     starts docked.
--   * Docked means ANCHORED to the target, so the window follows it with no bookkeeping.
--   * The target hiding pins a docked window where it already is on screen; the target showing
--     re-docks a shown window.
--   * A DROP decides docking only while the target is open -- near its edge docks, anywhere else
--     undocks and saves left/top. With the target closed there is no edge, so a drag only saves a
--     position and leaves the preference alone. "Near" is along the whole edge (a side dock accepts
--     any height from the target's bottom to its top, plus the reach), in screen units, because the
--     two frames need not share a scale.
--   * The drop and the show are heard through HookScript on OnDragStop and OnShow, which only survive if
--     the consumer set its own OnDragStop / OnShow BEFORE this call: a later SetScript replaces the hook,
--     and the window then silently stops docking on a drop or re-docking on a show. A ClearFrame's
--     frame (moved by its title bar, not a drag) is heard on that title bar's OnMouseUp as well
--     (MINOR 41). A window moved some other way calls `h:Moved()`; one whose OnShow must be set later
--     calls `h:Apply()` from it.
--   * LETTING GO (MINOR 38): `h:Undock()` or `W:UndockWindow(frame)` removes the window from its
--     target, pinning it where it is on screen and leaving `status.docked` alone. A target that is an
--     AceGUI widget's frame is POOLED -- released, then handed to the next addon's AceGUI:Create -- so
--     the handle lets go of it by itself when that widget is released; a consumer need not. Any other
--     frame that will be reused for something else must be let go of by hand first.
--
-- A raw frame, not an AceGUI widget: PersistWindow owns an AceGUI window's position through its status
-- table, and two owners of one position would fight -- so a window PersistWindow already owns is
-- REFUSED here (nil, one printed line naming both calls), and the reverse in PersistWindow (MINOR 32).
-- Returns the handle, or nil when `frame` or `opts.to` is not a frame. Idempotent per window: a second
-- call re-points the same handle.
local DockHandle = {}
DockHandle.__index = DockHandle

local function pointXY(f, point)
	local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
	if not (l and r and t and b) then return nil end
	local x = point:find("LEFT") and l or point:find("RIGHT") and r or (l + r) / 2
	local y = point:find("TOP") and t or point:find("BOTTOM") and b or (t + b) / 2
	return x, y
end

function DockHandle:IsDockEnabled() return self.status.docked ~= false end

function DockHandle:IsDocked()
	if not self.target then return false end
	local _, rel = self.frame:GetPoint(1)
	return rel ~= nil and rel == self.target
end

-- Anchor to the target. True only if it did: docking is off, the target is closed, or there is no
-- target (let go of by Undock), otherwise.
function DockHandle:Dock()
	if not self.target or not self:IsDockEnabled() or not self.target:IsShown() then return false end
	self.frame:ClearAllPoints()
	self.frame:SetPoint(self.point, self.target, self.relPoint, self.x, self.y)
	return true
end

-- The saved free position, or the centre of the screen.
function DockHandle:Restore()
	local f, s = self.frame, self.status
	f:ClearAllPoints()
	if tonumber(s.left) and tonumber(s.top) then
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", tonumber(s.left), tonumber(s.top))
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

function DockHandle:Apply()
	if not self:Dock() then self:Restore() end
end

-- Is the window's docking point close enough to where docking would put it? Both frames' coordinates
-- go through their own effective scale first.
function DockHandle:IsNearTarget()
	local f, t = self.frame, self.target
	if not t or not t:IsShown() then return false end
	local fx, fy = pointXY(f, self.point)
	local tx, ty = pointXY(t, self.relPoint)
	local tl, tr, tt, tb = t:GetLeft(), t:GetRight(), t:GetTop(), t:GetBottom()
	if not (fx and tx and tl) then return false end
	local fs, ts = f:GetEffectiveScale(), t:GetEffectiveScale()
	fx, fy = fx * fs, fy * fs
	tx, ty = (tx + self.x) * ts, (ty + self.y) * ts
	tl, tr, tt, tb = tl * ts, tr * ts, tt * ts, tb * ts
	local reach = self.snapDistance * fs
	if self.relPoint:find("LEFT") or self.relPoint:find("RIGHT") then
		return math.abs(fx - tx) <= reach and fy <= tt + reach and fy >= tb - reach
	end
	return math.abs(fy - ty) <= reach and fx >= tl - reach and fx <= tr + reach
end

-- The end of a move. See the header for the rule.
function DockHandle:Moved()
	if self.target and self.target:IsShown() then
		if self:IsNearTarget() then
			self.status.docked = true
			self:Dock()
			return
		end
		self.status.docked = false
	end
	local left, top = self.frame:GetLeft(), self.frame:GetTop()
	if left and top then self.status.left, self.status.top = left, top end
end

function DockHandle:SetDockEnabled(enabled)
	self.status.docked = enabled and true or false
	if self.frame:IsShown() then self:Apply() end
end

-- Pin a docked window where it is on screen, so it survives its target going away.
local function Dock_Pin(h)
	local left, top = h.frame:GetLeft(), h.frame:GetTop()
	if left and top then
		h.frame:ClearAllPoints()
		h.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	else
		h:Restore()
	end
end

--- Let go of the target (MINOR 38, TOGTools inbox 2472500e). The handle leaves the target's list, so
--- that frame showing or hiding no longer moves this window; a docked window is pinned where it is on
--- screen; `status.docked` is NOT changed, so a later `DockWindow(frame, { to = newTarget })` docks it
--- again by the same preference. Until then the window behaves as undocked. Idempotent. Returns true
--- when it let go of a target.
function DockHandle:Undock()
	local target = self.target
	if not target then return false end
	if self.frame:IsShown() and self:IsDocked() then Dock_Pin(self) end
	if target._lagwDockers then target._lagwDockers[self] = nil end
	if self._releaseWidget then
		lib:OnWidgetRelease(self._releaseWidget, self, false)
		self._releaseWidget = nil
	end
	self.target = nil
	return true
end

local function Dock_TargetShown(target)
	for h in pairs(target._lagwDockers) do
		if h.target == target and h.frame:IsShown() then h:Dock() end
	end
end

local function Dock_TargetHidden(target)
	for h in pairs(target._lagwDockers) do
		if h.target == target and h.frame:IsShown() and h:IsDocked() then Dock_Pin(h) end
	end
end

function lib:DockWindow(frame, opts)
	opts = opts or {}
	local target = opts.to
	if type(frame) ~= "table" or not frame.SetPoint or not frame.HookScript then return nil end
	if type(target) ~= "table" or not target.HookScript then return nil end
	-- PersistWindow records on the WIDGET, and the widget's frame points back at it (AceGUI sets
	-- `frame.obj`), so the persist record is looked up through that.
	local widget = frame.obj
	if otherOwner(frame, type(widget) == "table" and widget._lagwPersist, "DockWindow", "PersistWindow") then
		return nil
	end

	local h = frame._lagwDock
	if not h then
		h = setmetatable({ frame = frame, status = {} }, DockHandle)
		frame._lagwDock = h
		-- A hook cannot be removed, so each one acts only while this handle still owns the frame: a
		-- released window (below) is handed to the next addon with these hooks inert.
		local function owns() return rawget(frame, "_lagwDock") == h end
		frame:HookScript("OnShow", function() if owns() then h:Apply() end end)
		frame:HookScript("OnDragStop", function() if owns() then h:Moved() end end)
		-- A ClearFrame is not dragged: its title bar calls StartMoving / StopMovingOrSizing from its own
		-- OnMouseDown / OnMouseUp, so OnDragStop never fires for it (MINOR 41, PersonalShopper inbox
		-- bd091818). The drop is heard on the title bar's mouse-up instead, after its own handler has
		-- stopped the move. Any widget whose `title` is a mover child of this frame is treated the same.
		local mover = type(widget) == "table" and widget.title
		if type(mover) == "table" and mover.HookScript and mover.GetParent and mover:GetParent() == frame then
			mover:HookScript("OnMouseUp", function() if owns() then h:Moved() end end)
		end
	end
	-- Re-pointed at a new target: leave the old one's list, so its show/hide stops reaching this window.
	if h.target and h.target ~= target then h:Undock() end
	h.target   = target
	h.point    = opts.point or "TOPLEFT"
	h.relPoint = opts.relPoint or "TOPRIGHT"
	h.x, h.y   = opts.x or 0, opts.y or 0
	h.snapDistance = tonumber(opts.snapDistance) or 40
	if type(opts.status) == "table" then h.status = opts.status end

	-- One pair of hooks per TARGET, however many windows dock to it. Weak keys: a handle lives as long
	-- as its window does.
	if not target._lagwDockers then
		target._lagwDockers = setmetatable({}, { __mode = "k" })
		target:HookScript("OnShow", Dock_TargetShown)
		target:HookScript("OnHide", Dock_TargetHidden)
	end
	target._lagwDockers[h] = true

	-- A POOLED TARGET LETS GO BY ITSELF. An AceGUI frame (it carries `.obj`, the widget) goes back to
	-- the pool on Release and the next addon's AceGUI:Create gets it; left in its list, this window
	-- would re-dock onto THEIR window the moment they show it (TOGTools inbox 2472500e). So the handle
	-- lets go on that widget's release, keyed by the handle so a re-dock replaces rather than stacks.
	local targetWidget = target.obj
	if type(targetWidget) == "table" and targetWidget.frame == target then
		h._releaseWidget = targetWidget
		self:OnWidgetRelease(targetWidget, h, function() h:Undock() end)
	end

	-- A POOLED WINDOW GIVES UP THE FRAME (MINOR 41). The same pool hands the docked window's own frame
	-- to the next AceGUI:Create; still owned here, it would dock their window to our target on show,
	-- and PersistWindow would refuse it as ours. On release the handle lets go of its target and of
	-- the frame, which turns its hooks inert.
	if type(widget) == "table" and widget.frame == frame then
		self:OnWidgetRelease(widget, "DockWindow", function()
			h:Undock()
			if rawget(frame, "_lagwDock") == h then frame._lagwDock = nil end
		end)
	end

	if frame:IsShown() then h:Apply() end
	return h
end

--- `W:UndockWindow(frame)` -> `DockWindow`'s handle `:Undock()` for that window; false when the window
--- was never docked or already let go. (MINOR 38)
function lib:UndockWindow(frame)
	local h = type(frame) == "table" and rawget(frame, "_lagwDock")
	return h and h:Undock() or false
end

-- ---------------------------------------------------------------------------
-- The bottom-row icon cluster (MINOR 33)
-- ---------------------------------------------------------------------------
-- Lift a bottom-row control above AceGUI's invisible resize strips. `sizer_s` and `sizer_se` are laid
-- along the bottom edge and in the corner at parent level + 1, so a control parked on the bottom row
-- loses most of its hitbox to them and only a sliver in the middle answers a click or a hover.
-- FastGuildInvite found it (functions.lua:32-38 `LiftAboveSizers`) and three more addons re-derived
-- it; ClearFrame's own chrome and DressBottomRow now share this one.
local function liftAboveSizers(f)
	if not (f and f.GetParent and f.SetFrameLevel) then return false end
	local parent = f:GetParent()
	f:SetFrameLevel(((parent and parent.GetFrameLevel and parent:GetFrameLevel()) or 0) + 5)
	return true
end

-- THE FLEET'S NUMBERS, and where they come from rather than who copied them last. AceGUI's stock Frame
-- puts its Close button at BOTTOMRIGHT (-27, 17), 100 x 20 (AceGUIContainer-Frame.lua:199-204), so its
-- LEFT edge sits at -127; the first icon's right edge at -133 is that edge less a 6px gap. The first
-- icon is 24 square at y 15, every further one 20 square at y 17 with an 8px gap, which centres them
-- all on one line with Close. TOGBankClassic/Modules/UI.lua:404-417 is where they were first written
-- down; FastGuildInvite, TOGProfessionMaster and Questbook each carry the same numbers by hand.
--
-- NOT SCALED, DELIBERATELY. Everything else this library draws follows `SetScale`, but this row sits
-- beside AceGUI's own Close button and status bar, which do not -- so a scaled icon would drift away
-- from the chrome it is lining up with. Do not "fix" this by wrapping the numbers in `ScaledSize`.
local ICON_FIRST_SIZE, ICON_SIZE = 24, 20
local ICON_FIRST_X, ICON_FIRST_Y, ICON_Y, ICON_GAP = -133, 15, 17, 8
-- AceGUI's own status-bar anchors, used only when the bar carries no readable points to put back.
local STATUS_LEFT, STATUS_BOTTOM, STATUS_STOCK_RIGHT, STATUS_GAP = 15, 15, -132, 6

local function statusBarOf(widget)
	if type(widget) ~= "table" then return nil end
	if widget.statusbg then return widget.statusbg end
	local st = widget.statustext
	return st and st.GetParent and st:GetParent() or nil
end

-- A spec's tooltip half, resolved AT HOVER so a consumer can re-label by assignment and so an icon
-- whose text depends on state (Questbook's stop icon: "nothing to stop" while nothing is tracked)
-- says the right thing without re-dressing. An array of lines is joined rather than added one at a
-- time, so every tooltip in this library still goes through the one `showTooltip` draw. A function is
-- a consumer callback and goes through `safeCall` like every other: one that errors is reported with
-- its stack and that half of the tooltip is left out, rather than the error escaping OnEnter raw.
local function tipPart(v, icon)
	if type(v) == "function" then
		local ok, out = safeCall(v, icon)
		v = ok and out or nil
	end
	if type(v) == "table" then
		local out = {}
		for _, line in ipairs(v) do
			local s = tooltipText(line)
			-- A blank line is a deliberate paragraph break in these tooltips, which `tooltipText`
			-- drops as an empty string; keep it as a space, the way the hand-rolled copies write it.
			out[#out + 1] = s or (line == "" and " " or nil)
		end
		return #out > 0 and table.concat(out, "\n") or nil
	end
	return tooltipText(v)
end
lib._tipPart = tipPart   -- for the satellite files (SideTabs, MINOR 45)

local function BottomIcon_OnEnter(icon)
	showTooltip(icon, tipPart(icon._lagwTipTitle, icon), tipPart(icon._lagwTipBody, icon),
		icon._lagwTipMinW and { minWidth = icon._lagwTipMinW } or nil)   -- spec.tipMinWidth, MINOR 36
end
local function BottomIcon_OnLeave(icon) lib:HideTooltip(icon) end
local function BottomIcon_OnClick(icon, button)
	if icon._lagwOnClick then safeCall(icon._lagwOnClick, icon, button) end
end

-- Build (or re-dress) the row of icons that sits left of AceGUI's Close button, and shorten the
-- status bar so its text cannot run underneath them.
--
--   local icons = W:DressBottomRow(window, {
--       { key = "help", texture = "Interface\\Common\\help-i", tipTitle = "Questbook", tipBody = { ... } },
--       { key = "gear", texture = "Interface\\Icons\\Trade_Engineering", texCoord = { 0.08, 0.92, 0.08, 0.92 },
--         tipTitle = "Settings", tipBody = "Open the options panel.", onClick = function() ns.Options:Open() end },
--   })
--   icons[1] == icons.help                                   -- by position and, when given, by key
--
-- `widget` is an AceGUI Frame widget (this library's ClearFrame included) or a raw frame. Per spec:
--   texture   the icon, a file path or id. Required; a spec without one is skipped
--   texCoord  { left, right, top, bottom } crop -- Blizzard's icon files carry transparent padding,
--             so an Icons\\ texture wants { 0.08, 0.92, 0.08, 0.92 } or the glyph floats in its button
--   size, y   overrides for that icon's square size and its height off the bottom edge
--   gap       the space to the icon on its right (default 8)
--   alpha     initial alpha (a dimmed icon that says there is nothing to act on)
--   tipTitle / tipBody  a string, an array of lines, or a function(icon) returning either; READ ON
--             HOVER, so `icon._lagwTipBody = ...` re-labels without re-dressing
--   tipMinWidth  scale-1.0 px floor on the tooltip's width, for long help text (MINOR 36)
--   onClick   function(icon, mouseButton)
--   key       a string to find the icon by in the returned table; ignored if not a string
--
-- IDEMPOTENT, and that is required rather than tidy: AceGUI pools its frames for the whole session, so
-- a window released and reacquired hands back the same frame and a second Dress that built fresh
-- buttons would stack them on the first set. The icons are cached on the frame by position and
-- re-pointed; a shorter second Dress hides the ones it no longer uses.
--
-- Pair it with `UndressBottomRow` when the window closes. Hiding is the load-bearing half there: the
-- pooled frame can go to ANOTHER addon's window next, and children shown when their parent shows
-- would put this addon's gear on somebody else's frame.
function lib:DressBottomRow(widget, specs)
	local frame = type(widget) == "table" and (widget.frame or widget) or nil
	if not (frame and frame.CreateTexture and type(specs) == "table") then return nil end

	local cache = frame._lagwBottomRow
	if not cache then cache = {}; frame._lagwBottomRow = cache end

	local icons, x, n = {}, ICON_FIRST_X, 0
	for i = 1, #specs do
		local spec = specs[i]
		if type(spec) == "table" and spec.texture then
			n = n + 1
			local icon = cache[n]
			if not icon then
				icon = CreateFrame("Button", nil, frame)
				icon:EnableMouse(true)
				-- 2px past the visible button on every side, so a 20px icon clicks like a 24px one.
				icon:SetHitRectInsets(-2, -2, -2, -2)
				icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
				icon:SetScript("OnEnter", BottomIcon_OnEnter)
				icon:SetScript("OnLeave", BottomIcon_OnLeave)
				icon:SetScript("OnClick", BottomIcon_OnClick)
				cache[n] = icon
			end
			icon:SetNormalTexture(spec.texture)
			icon:SetPushedTexture(spec.texture)
			local normal, pushed = icon:GetNormalTexture(), icon:GetPushedTexture()
			local c = spec.texCoord
			if normal and normal.SetTexCoord and c then normal:SetTexCoord(c[1], c[2], c[3], c[4]) end
			if pushed then
				if pushed.SetTexCoord and c then pushed:SetTexCoord(c[1], c[2], c[3], c[4]) end
				if pushed.SetVertexColor then pushed:SetVertexColor(0.7, 0.7, 0.7) end
			end
			icon._lagwTipTitle, icon._lagwTipBody = spec.tipTitle, spec.tipBody
			icon._lagwTipMinW = spec.tipMinWidth
			icon._lagwOnClick = spec.onClick

			local size = spec.size or (n == 1 and ICON_FIRST_SIZE or ICON_SIZE)
			icon:SetSize(size, size)
			icon:ClearAllPoints()
			icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x, spec.y or (n == 1 and ICON_FIRST_Y or ICON_Y))
			-- The NEXT icon's right edge: this one's, less its width and the gap. Walked rather than
			-- anchored icon-to-icon so a consumer's per-icon `size` override cannot drag the rest of
			-- the row sideways with it.
			x = x - size - (spec.gap or ICON_GAP)
			liftAboveSizers(icon)
			if icon.SetAlpha then icon:SetAlpha(spec.alpha or 1) end
			icon:Show()
			icons[n] = icon
			-- String keys only: a numeric key would overwrite an icon's slot in the array.
			if type(spec.key) == "string" then icons[spec.key] = icon end
		end
	end
	-- A second, shorter Dress: the icons the new set does not use go away rather than lingering at
	-- their old spot with their old click handler.
	for i = n + 1, #cache do cache[i]:Hide() end

	local bar = statusBarOf(widget)
	if bar and bar.SetPoint then
		if not frame._lagwStatusPoints then
			-- What the bar was anchored to BEFORE this row shortened it, read rather than assumed:
			-- AceGUI's stock Frame pins it at -132 but ClearFrame pins it to its own info icon, and
			-- restoring a ClearFrame to AceGUI's number would move a bar nobody asked to move.
			local saved = {}
			for i = 1, (bar.GetNumPoints and bar:GetNumPoints() or 0) do
				local p, rel, relPoint, px, py = bar:GetPoint(i)
				saved[#saved + 1] = { p, rel, relPoint, px, py }
			end
			frame._lagwStatusPoints = saved
		end
		if icons[1] then
			bar:ClearAllPoints()
			bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", STATUS_LEFT, STATUS_BOTTOM)
			bar:SetPoint("BOTTOMRIGHT", icons[n], "BOTTOMLEFT", -STATUS_GAP, 0)
		end
	end
	return icons
end

-- Take the row down when the window closes: hide every icon and put the status bar back.
--
-- BOTH HALVES ARE REQUIRED, and neither is tidiness. AceGUI pools frames across every addon in the
-- session: icons left shown go to whoever takes that frame next, where this addon's gear opens this
-- addon's settings from somebody else's window; and AceGUI builds its status bar ONCE and never
-- re-anchors it on acquire, so a bar still pinned to a hidden icon of ours arrives at the next addon
-- 33px short on the right, anchored to a button that is not theirs. FastGuildInvite and Questbook
-- each cleaned up the same two hazards by hand.
function lib:UndressBottomRow(widget)
	local frame = type(widget) == "table" and (widget.frame or widget) or nil
	if not frame then return false end
	local cache = frame._lagwBottomRow
	if cache then for i = 1, #cache do cache[i]:Hide() end end

	local bar, saved = statusBarOf(widget), frame._lagwStatusPoints
	if bar and bar.SetPoint then
		bar:ClearAllPoints()
		if saved and #saved > 0 then
			for i = 1, #saved do
				local p = saved[i]
				bar:SetPoint(p[1], p[2], p[3], p[4], p[5])
			end
		else
			bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", STATUS_LEFT, STATUS_BOTTOM)
			bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", STATUS_STOCK_RIGHT, STATUS_BOTTOM)
		end
	end
	frame._lagwStatusPoints = nil
	return true
end

-- ---------------------------------------------------------------------------
-- A text button in a window's top-right corner (MINOR 40)
-- ---------------------------------------------------------------------------
-- Grouper inbox 12c62f8b (their operator, 2026-10-03: "can you add a button in the top right to switch
-- the user back to the legacy UI ... we'll need the legacy ui to have the same button"). One builder for
-- both window kinds: ClearFrame's `SetHeaderButton` calls this, and a stock AceGUI `Frame` uses it
-- directly, so the two windows cannot drift apart.
--
-- Placement: inside the border, right-aligned, its BOTTOM level with the content's top (27 below the
-- frame's top in both window kinds, AceGUIContainer-Frame.lua's `content` anchor), so it sits on the
-- title row and never over the window's own content. A ClearFrame's chrome follows the UI scale and so
-- does this button on one; a stock Frame's chrome does not, so on one the button stays at scale 1.0, for
-- the reason `DressBottomRow`'s numbers are unscaled.
-- One table, not seven locals: the main chunk is at Lua 5.1's 200-local limit (Tests/localheadroom_spec.lua).
local HEADER = {
	RIGHT = -14, BOTTOM = 27, H = 20, PAD = 10, MIN_W = 40,
	-- A ClearFrame's button sits a further 4 in and 6 down. SEEN, NOT DERIVED: with the stock numbers the
	-- operator saw it straddle the ClearFrame's top border while the same numbers on a stock Frame sat
	-- inside it ("it kinda overlaps the border in the new UI" / "it's perfect in the classic ui", Grouper
	-- inbox e62d2977, 2026-10-03). Reading the two constructors does not explain the difference -- same
	-- backdrop, same 27 content inset at scale 1.0 -- so this is set from what was seen, not from a cause.
	CF_IN = 4, CF_DOWN = 6,
}

local function HeaderButton_OnClick(btn, mouseButton)
	if btn._lagwOnClick then safeCall(btn._lagwOnClick, btn, mouseButton) end
end
local function HeaderButton_OnEnter(btn) showTooltip(btn, btn._lagwTipTitle, btn._lagwTipBody) end
local function HeaderButton_OnLeave(btn) lib:HideTooltip(btn) end

local function layoutHeaderButton(btn)
	local frame = btn:GetParent()
	local S = btn._lagwScaled and function(px) return lib:ScaledSize(px) end or function(px) return px end
	if btn._lagwScaled then scaleButtonFonts(lib, btn) end
	local fs = btn.GetFontString and btn:GetFontString()
	local textW = fs and fs.GetStringWidth and fs:GetStringWidth() or 0
	local h = S(HEADER.H)
	btn:SetSize(math.max(S(HEADER.MIN_W), textW + 2 * S(HEADER.PAD)), h)
	local x, y = HEADER.RIGHT, -(S(HEADER.BOTTOM) - h)
	if btn._lagwScaled then x, y = x - S(HEADER.CF_IN), y - S(HEADER.CF_DOWN) end
	btn:ClearAllPoints()
	btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, y)
end
local function HeaderButton_OnScaleChanged(_, _, btn)
	if btn:IsShown() then layoutHeaderButton(btn) end
end

--- `W:AttachHeaderButton(widget, text, onClick, tipTitle, tipBody)` -> the button, or nil.
--- A text button pinned to the top-right corner of an AceGUI window (`widget.frame`; a stock `Frame`
--- or this library's `ClearFrame`, which also has it as `win:SetHeaderButton(...)`). Sized to its label.
--- `onClick(button, mouseButton)`; `tipTitle` / `tipBody` fill its tooltip. Calling again REPLACES the
--- text, handler and tooltip on the same button; `text = nil` hides it. On Release it hides and lets go
--- of its handler, so AceGUI's pooled frame never carries it into another addon's window.
function lib:AttachHeaderButton(widget, text, onClick, tipTitle, tipBody)
	local frame = type(widget) == "table" and widget.frame or nil
	if not (frame and frame.CreateTexture) then return nil end
	local btn = frame._lagwHeaderButton
	if text == nil then
		if btn then self:DetachHeaderButton(widget) end
		return nil
	end
	if not btn then
		btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		btn:SetScript("OnClick", HeaderButton_OnClick)
		btn:SetScript("OnEnter", HeaderButton_OnEnter)
		btn:SetScript("OnLeave", HeaderButton_OnLeave)
		frame._lagwHeaderButton = btn
	end
	-- Re-decided per attach: the pooled frame may have been a ClearFrame's last time and not this time.
	btn._lagwScaled = widget.type == "ClearFrame"
	btn._lagwOnClick, btn._lagwTipTitle, btn._lagwTipBody = onClick, tipTitle, tipBody
	btn:SetText(tostring(text))
	liftAboveSizers(btn)
	btn:Show()
	layoutHeaderButton(btn)
	self:OnScaleChanged(btn, btn._lagwScaled and HeaderButton_OnScaleChanged or nil)
	self:OnWidgetRelease(widget, "lagw:header", function(w) lib:DetachHeaderButton(w) end)
	return btn
end

--- Hide `widget`'s header button and drop its handler and tooltip, now. Runs for you on Release.
--- Returns true when there was a button to take down.
function lib:DetachHeaderButton(widget)
	local frame = type(widget) == "table" and widget.frame or nil
	local btn = frame and frame._lagwHeaderButton
	if not btn then return false end
	btn:Hide()
	lib:HideTooltip(btn)
	btn._lagwOnClick, btn._lagwTipTitle, btn._lagwTipBody = nil, nil, nil
	self:OnScaleChanged(btn, nil)
	self:OnWidgetRelease(widget, "lagw:header", false)
	return true
end

-- ---------------------------------------------------------------------------
-- Breathing -- the fleet's attention-getter, as one call (MINOR 28)
-- ---------------------------------------------------------------------------
-- An alpha pulse from 1 down to `low` and back, looping, eased. Requested by TOGBankClassic (inbox
-- 370504bb, 2026-09-13), who had the identical eight lines three times -- a cancelled request's date
-- glow, the bank window's help icon, the status bar's urgent line -- with the numbers copied by hand
-- and one comment saying "the same as Requests" with nothing asserting it. FastGuildInvite and Dibs
-- use the same idiom. The defaults ARE the fleet's existing breath, so lifting a call site onto this
-- changes nothing on screen.
--
--   W:Breathe(frame)                                    -- 1 -> 0.35 -> 1, one second each way, eased
--   W:Breathe(frame, { low = 0.5, seconds = 0.6, smoothing = "IN_OUT" })
--   W:StopBreathing(frame)                              -- Stop + SetAlpha(1); a no-op if it never breathed
--   W:IsBreathing(frame)
--
-- IDEMPOTENT. The animation group lives on the region under one library-owned key, so a second call
-- re-points the same group rather than stacking another -- a pooled AceGUI frame handed back and
-- reacquired reuses it. The group is built ONCE and its animation re-parameterised on each call, so
-- changing `low` on a breathing frame takes effect on the next Play without a leak.
--
-- Works on a Frame; on a Texture or FontString too where the client allows (they are
-- AnimatableObjects in every flavour this library ships to). A consumer that wants a harness-driveable
-- breath puts it on a Frame: the offline model's Frame has CreateAnimationGroup, its regions do not,
-- and this returns nil rather than raising for a region that cannot animate.
local BREATH_LOW, BREATH_SECONDS, BREATH_SMOOTHING = 0.35, 1.0, "IN_OUT"

function lib:Breathe(region, opts)
	if type(region) ~= "table" or type(region.CreateAnimationGroup) ~= "function" then return nil end
	opts = opts or {}
	local group = region._lagwBreath
	if not group then
		group = region:CreateAnimationGroup()
		group:SetLooping("BOUNCE")
		group._lagwAlpha = group:CreateAnimation("Alpha")
		region._lagwBreath = group
	end
	local anim = group._lagwAlpha
	anim:SetFromAlpha(1)
	anim:SetToAlpha(tonumber(opts.low) or BREATH_LOW)
	anim:SetDuration(tonumber(opts.seconds) or BREATH_SECONDS)
	anim:SetSmoothing(opts.smoothing or BREATH_SMOOTHING)
	if not group:IsPlaying() then group:Play() end
	return group
end

-- Returns true if the region had a breath to stop. Alpha goes back to 1 either way a group exists,
-- because a Stop mid-pulse leaves the region wherever the pulse was.
function lib:StopBreathing(region)
	local group = type(region) == "table" and region._lagwBreath
	if not group then return false end
	local was = group:IsPlaying()
	group:Stop()
	if region.SetAlpha then region:SetAlpha(1) end
	return was
end

function lib:IsBreathing(region)
	local group = type(region) == "table" and region._lagwBreath
	return (group and group:IsPlaying()) and true or false
end

-- ---------------------------------------------------------------------------
-- Flash -- a FINITE attention flash, beside Breathe (MINOR 36, TOGProfessionMaster inbox 759b8287)
-- ---------------------------------------------------------------------------
-- Breathe loops until stopped: "this needs you". Flash is "something just happened": `times` dips of
-- the region's alpha to `low` and back, then it stops by itself and the alpha is 1 again.
--
--   W:Flash(frame)                                  -- 3 dips, 0.25s each way, down to 0
--   W:Flash(frame, { times = 2, seconds = 0.4, low = 0.2, onDone = fn })
--   W:FlashScreen()                                 -- a full-screen edge glow in the accent, 3 times
--   W:FlashScreen({ color = "ffff0000", times = 2 })
--
-- A BOUNCE group; each OnLoop turning back to FORWARD is one dip. The count lives on the
-- group and a second call RESTARTS it (resets the count, re-points the numbers) rather than stacking a
-- second group. Nothing here touches a protected frame or API, so it is safe in combat.
local FLASH_TIMES, FLASH_SECONDS, FLASH_LOW = 3, 0.25, 0

local function endFlash(region, group)
	group:Stop()
	if region.SetAlpha then region:SetAlpha(1) end
	local done = group._lagwDone
	group._lagwDone = nil
	if done then safeCall(done, region) end
end

function lib:Flash(region, opts)
	if type(region) ~= "table" or type(region.CreateAnimationGroup) ~= "function" then return nil end
	opts = opts or {}
	local group = region._lagwFlash
	if not group then
		group = region:CreateAnimationGroup()
		group:SetLooping("BOUNCE")
		group._lagwAlpha = group:CreateAnimation("Alpha")
		-- A dip is counted when the loop turns back to FORWARD, i.e. once the alpha is back up. Whether the
		-- client calls OnLoop at each end of a BOUNCE pass or once per cycle is not settled by the docs
		-- (wiki: "the loop state that the animation is transitioning to"), and counting only FORWARD is
		-- right either way (peer review, thread a4829ae2).
		group:SetScript("OnLoop", function(g, loopState)
			if loopState ~= "FORWARD" then return end
			g._lagwLeft = (g._lagwLeft or 0) - 1
			if g._lagwLeft <= 0 then endFlash(region, g) end
		end)
		region._lagwFlash = group
	end
	if group:IsPlaying() then group:Stop() end
	local anim = group._lagwAlpha
	anim:SetFromAlpha(1)
	anim:SetToAlpha(tonumber(opts.low) or FLASH_LOW)
	anim:SetDuration(tonumber(opts.seconds) or FLASH_SECONDS)
	group._lagwLeft = math.max(1, math.floor(tonumber(opts.times) or FLASH_TIMES))
	group._lagwDone = type(opts.onDone) == "function" and opts.onDone or nil
	group:Play()
	return group
end

--- Stop a flash now and put the alpha back. Returns whether one was running.
function lib:StopFlash(region)
	local group = type(region) == "table" and region._lagwFlash
	if not (group and group:IsPlaying()) then return false end
	endFlash(region, group)
	return true
end

local FLASH_EDGE = 28   -- scale-1.0 thickness of each edge bar

--- A full-screen edge glow, flashed and then hidden (MINOR 36). ONE shared frame on UIParent at
--- FULLSCREEN_DIALOG strata that never takes the mouse, so it cannot block a click; a second call
--- restarts the flash on that same frame. The glow is four flat-colour bars along the screen's edges,
--- which render on every flavour -- no client texture to go missing. `color` is "ffRRGGBB" and
--- defaults to the accent.
function lib:FlashScreen(opts)
	opts = opts or {}
	local f = self._flashScreen
	if not f then
		f = CreateFrame("Frame", nil, UIParent)
		f:SetAllPoints(UIParent)
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:EnableMouse(false)
		f.bars = {}
		local sides = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
			{ "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }
		for i, s in ipairs(sides) do
			local t = f:CreateTexture(nil, "BACKGROUND")
			t:SetPoint(s[1], f, s[1], 0, 0)
			t:SetPoint(s[2], f, s[2], 0, 0)
			t._lagwHorizontal = i <= 2
			f.bars[i] = t
		end
		f:Hide()
		self._flashScreen = f
	end
	local r, g, b = hexRGB(opts.color or self:GetAccent())
	local edge = self:ScaledSize(FLASH_EDGE)
	for _, t in ipairs(f.bars) do
		t:SetColorTexture(r, g, b, 0.55)
		if t._lagwHorizontal then t:SetHeight(edge) else t:SetWidth(edge) end
	end
	f:Show()
	return self:Flash(f, { times = opts.times, seconds = opts.seconds,
		onDone = function(frame) frame:Hide() end })
end

-- UIDropDownMenu_CreateInfo with notCheckable preset (hides the unused left
-- check-mark slot on single-select menus). Pass checkable=true to keep it.
function lib:CreateMenuInfo(checkable)
	local info = UIDropDownMenu_CreateInfo()
	if not checkable then info.notCheckable = true end
	return info
end

-- Brand-coloured label, implemented as a transparent Button so it can carry a
-- tooltip (bare FontStrings have no OnEnter/OnLeave). opts:
--   x, y, width, height, justify, font, tipTitle, tipBody.
-- Returns the Button (callers can re-anchor from the default TOPLEFT origin).
-- `width`/`height` are scale-1.0 sizes and follow the scale; `x`/`y` are the caller's layout and
-- do not (MINOR 29).
function lib:MakeLabel(parent, text, opts)
	opts = opts or {}
	local btn = CreateFrame("Button", nil, parent)
	self:SetScaledSize(btn, opts.width or 120, opts.height or 12)
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x or 0, opts.y or 0)
	btn:EnableMouse(opts.tipTitle ~= nil)

	local fs = btn:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(self:ScaledFont(opts.font or "GameFontNormalSmall") or opts.font or "GameFontNormalSmall")
	fs:SetAllPoints(btn)
	fs:SetJustifyH(opts.justify or "LEFT")
	fs:SetText(self:Brand(text))
	btn.label = fs

	if opts.tipTitle then
		self:AttachTooltip(btn, opts.tipTitle, opts.tipBody)
	end
	return btn
end

-- ---------------------------------------------------------------------------
-- Dropdown menu — a lightweight anchored menu with cascading submenus
-- ---------------------------------------------------------------------------
-- Menu frames are pooled per DEPTH (1 = the root opened at the anchor, 2+ = flyout submenus). Each
-- row carries a check mark (radio-style: the current selection is checked); a row with `children`
-- shows a ▶ arrow and, on hover, opens the next-depth submenu anchored to its right. Clicking a leaf
-- row runs its onClick and closes the whole stack (unless opts.keepOpen); clicking outside — or the
-- anchor's own button (via ToggleMenu) — closes it.
--
-- Every menu frame renders at the TOOLTIP strata, which sits ABOVE the FULLSCREEN_DIALOG windows this
-- suite uses — so the menu is never overdrawn by the window's own content (a RowList's cells live in
-- the same strata and, at a higher frame level, would otherwise punch their text through a menu placed
-- at the anchor's level; strata beats level, so lifting the strata is the real fix, not backdrop alpha).
--   items: { { text = , checked = bool, onClick = function, children = list|function }, ... }
--          MINOR 30 per item: isTitle (gold header, inert), disabled (grey, inert; empty text = spacer),
--          tooltipTitle / tooltipText (shown on hover, inert rows included), keepOpen (overrides opts')
--   opts:  { width = , keepOpen = bool }
-- MENU_PAD = horizontal inset of rows from the frame edge. MENU_VPAD = top/bottom inset — it must clear the
-- FrameBackdrop's 8px border inset (else the first/last row's text sits under the border), with breathing room.
-- Scale-1.0 values; `renderMenu` scales them on every render, so an open menu is always at the current
-- scale and a pooled row built at one scale is re-sized at the next (MINOR 29).
-- ---------------------------------------------------------------------------
-- Floating frames -- one implementation of "a panel that floats above the window" (MINOR 30)
-- ---------------------------------------------------------------------------
-- The pooled menu frames, the DatePicker popup and `ShowDialog` each built this by hand, and the
-- duplication had already cost something: the menu copy took a strata fix -- TOOLTIP strata, because
-- **strata beats level** and a RowList's cells would otherwise punch their text through a menu placed
-- at the anchor's level -- which a later copy would not have inherited. Three behaviours live here now:
-- the frame itself, the client's Escape list, and click-outside-to-close.
--
--   local f = W:CreateFloatingFrame({ name = "MyAddon_Popup", level = 130 })
--   W:OwnFloating(f, { isOver = function() return myAnchor:IsMouseOver() end })
--
-- What each CALLER keeps, because it is genuinely theirs: the menus close a whole STACK (`close`), the
-- popup also forgets its owner on hide, and the dialog is parented INTO its consumer's window at that
-- window's strata, so it uses `RegisterSpecialFrame` alone and builds its own frame.

--- Append `name` to the client's Escape list, once. Returns whether this call added it.
--- A frame must be NAMED to be listed -- `UISpecialFrames` holds global names, not frames -- and a
--- MINOR upgrade re-runs the file against a list that already has the name, which is why this checks.
function lib:RegisterSpecialFrame(name)
	local special = _G.UISpecialFrames
	if type(name) ~= "string" or type(special) ~= "table" then return false end
	for _, entry in ipairs(special) do
		if entry == name then return false end
	end
	table.insert(special, name)
	return true
end

-- Take `name` off the client's Escape list. Returns whether it was there.
local function unregisterSpecial(name)
	local special = _G.UISpecialFrames
	if type(name) ~= "string" or type(special) ~= "table" then return false end
	for i = #special, 1, -1 do
		if special[i] == name then
			table.remove(special, i)
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Escape closes a window's popups before the window (MINOR 36, TOGProfessionMaster inbox d8f15682)
-- ---------------------------------------------------------------------------
-- HOW THE CLIENT CLOSES THINGS ON ESCAPE, read in the Classic Era source rather than assumed
-- (Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:1041, `CloseSpecialWindows`): it walks
-- `UISpecialFrames` with `pairs`, hides EVERY entry whose frame `IsShown()`, and reports whether it hid
-- any (which is what stops Escape opening the game menu). So a popup and its window both on the list
-- close together on one press, in no defined order -- there is no "topmost" in that walk at all.
--
-- So a layered window is represented on the list by ONE hidden-when-idle proxy frame, and the window
-- and its children are taken off it. The proxy is shown while the window is, so one press finds it and
-- hides it. Its OnHide then closes the most recently shown child and shows itself again, ready for the
-- next press, or, with no child showing, hides the window. It is a plain frame hidden by the client's
-- own Lua, so it works in combat exactly as any special frame does.
--
--   * `IsShown()` is the frame's OWN flag, so the proxy's OnHide ignores a hide it did not get (its window
--     hidden, UIParent hidden) by checking the flag: an Escape leaves it false, a parent's hide does not.
--   * The window hiding hides the proxy (so a closed window cannot swallow the next Escape) and every
--     shown child, which runs their own OnHide.
--   * The hooks on the window frame are installed once and read the layer from the frame at event time,
--     so a released window's hooks do nothing, and the proxy is kept on the frame for its next owner.
--   * KNOWN COST: Escape is not the only caller. `CloseWindows` (line 1087 of the same file) ends in
--     `securecall("CloseSpecialWindows")`, and CloseAllWindows (loss of control, some panel opens) runs
--     through it. The proxy cannot tell those calls from a key press, so each one closes the newest child
--     only, and a layered window survives a call that closes an unlayered one outright. The same function
--     and line numbers are in the classic_anniversary and classic trees.
local escapeStamp, escapeProxies = 0, 0

local function escapeFrameOf(x)
	if type(x) ~= "table" then return nil end
	if type(x.frame) == "table" then return x.frame end
	return x.HookScript and x or nil
end

local function Escape_ProxyOnHide(proxy)
	local wf = proxy._lagwWindow
	local layer = wf and wf._lagwEscape
	if not layer or layer.quiet or proxy:IsShown() or not wf:IsShown() then return end
	local top, best
	for _, c in ipairs(layer.children) do
		if c:IsShown() and (not best or (c._lagwEscapeStamp or 0) > best) then
			top, best = c, c._lagwEscapeStamp or 0
		end
	end
	if top then
		top:Hide()
		layer.quiet = true
		proxy:Show()   -- ready for the next press
		layer.quiet = nil
	else
		wf:Hide()
	end
end

local function Escape_WindowOnShow(wf)
	local layer = wf._lagwEscape
	if not layer then return end
	layer.quiet = true
	wf._lagwEscapeProxy:Show()
	layer.quiet = nil
end

local function Escape_WindowOnHide(wf)
	local layer = wf._lagwEscape
	-- A window still flagged shown was hidden by its parent, not closed: leave everything as it is.
	if not layer or wf:IsShown() then return end
	layer.quiet = true
	wf._lagwEscapeProxy:Hide()
	layer.quiet = nil
	-- Snapshot: a child's OnHide may leave the layer (ShowDialog's dialog does, via RemoveEscapeChild),
	-- and removing from the list being walked would skip the child after it.
	local shown = {}
	for _, c in ipairs(layer.children) do
		if c:IsShown() then shown[#shown + 1] = c end
	end
	for _, c in ipairs(shown) do c:Hide() end
end

local function Escape_ChildOnShow(c)
	escapeStamp = escapeStamp + 1
	c._lagwEscapeStamp = escapeStamp
end

--- `W:EscapeLayer(window, childFrames)` (MINOR 36): Escape closes the most recently shown of
--- `childFrames` (popups, dialogs, floating panels the window owns) first, and the window itself on the
--- press after the last of them is gone. `window` and each child may be a frame or an AceGUI widget. A
--- second call adds more children. The window and every child are taken off `UISpecialFrames` for as
--- long as the layer lasts, because the client would otherwise close them all on one press; they go
--- back on when it ends. For an AceGUI window the layer ends on Release, and for a raw frame with
--- `W:DropEscapeLayer(window)`. Returns the proxy frame on the Escape list, or nil for a non-frame.
--- Never call it (or DropEscapeLayer / RemoveEscapeChild) from an OnHide that Escape reaches: those run
--- inside the client's walk of `UISpecialFrames`, which these edit -- see RemoveEscapeChild.
function lib:EscapeLayer(window, childFrames)
	local wf = escapeFrameOf(window)
	if not wf then return nil end
	local layer = rawget(wf, "_lagwEscape")
	if not layer then
		layer = { children = {}, has = {}, removed = {} }
		wf._lagwEscape = layer
		local proxy = wf._lagwEscapeProxy
		if not proxy then
			escapeProxies = escapeProxies + 1
			local name = "LibAceGUIWidgetsEscape" .. escapeProxies
			proxy = CreateFrame("Frame", name, wf)
			proxy._lagwWindow = wf
			proxy:SetScript("OnHide", Escape_ProxyOnHide)
			wf._lagwEscapeProxy = proxy
			wf:HookScript("OnShow", Escape_WindowOnShow)
			wf:HookScript("OnHide", Escape_WindowOnHide)
			self:RegisterSpecialFrame(name)
		end
		local own = wf.GetName and wf:GetName()
		if own and unregisterSpecial(own) then layer.removed[#layer.removed + 1] = own end
		layer.quiet = true
		if wf:IsShown() then proxy:Show() else proxy:Hide() end
		layer.quiet = nil
		if window ~= wf and type(window) == "table" then
			self:OnWidgetRelease(window, "lagwEscape", function() lib:DropEscapeLayer(wf) end)
		end
	end
	for _, x in ipairs(type(childFrames) == "table" and childFrames or {}) do
		local c = escapeFrameOf(x)
		if c and c ~= wf and not layer.has[c] then
			layer.has[c] = true
			layer.children[#layer.children + 1] = c
			-- The owning windows, so ShowDialog over a UIParent-parented child (a floating panel or form
			-- dialog) finds this layer, which no GetParent walk from the child reaches (Peer Review ace03ea9).
			-- A LIST, because one frame may be a child of several layers (RemoveEscapeChild's shared frame);
			-- an entry whose layer has since let the child go is skipped by ShowDialog's `has` check. Kept in
			-- add order, newest last: a window re-adding the child moves to the end.
			local owners = rawget(c, "_lagwEscapeOwners")
			if not owners then owners = {}; c._lagwEscapeOwners = owners end
			for i = #owners, 1, -1 do
				if owners[i] == wf then table.remove(owners, i) end
			end
			owners[#owners + 1] = wf
			local n = c.GetName and c:GetName()
			if n and unregisterSpecial(n) then layer.removed[#layer.removed + 1] = n end
			if not c._lagwEscapeHooked then
				c._lagwEscapeHooked = true
				c:HookScript("OnShow", Escape_ChildOnShow)
			end
			if c:IsShown() then Escape_ChildOnShow(c) end
		end
	end
	return wf._lagwEscapeProxy
end

--- End `window`'s Escape layer: its proxy is hidden (so it takes no press) and every name the layer took
--- off `UISpecialFrames` goes back on. Returns whether there was a layer. Called for you on Release.
function lib:DropEscapeLayer(window)
	local wf = escapeFrameOf(window)
	if not wf then return false end
	local layer = rawget(wf, "_lagwEscape")
	if not layer then return false end
	layer.quiet = true
	wf._lagwEscapeProxy:Hide()
	wf._lagwEscape = nil
	for _, n in ipairs(layer.removed) do self:RegisterSpecialFrame(n) end
	return true
end

-- Take child `c` out of `wf`'s layer. With `relist`, a name the layer took off UISpecialFrames goes
-- back on; without it the name is only forgotten by the layer and stays off (ShowDialog's finish, which
-- can run INSIDE the client's Escape walk and so must not append to the list -- see RemoveEscapeChild).
local function leaveEscapeLayer(wf, c, relist)
	local layer = wf and rawget(wf, "_lagwEscape")
	if not (layer and c and layer.has[c]) then return false end
	layer.has[c] = nil
	for i = #layer.children, 1, -1 do
		if layer.children[i] == c then table.remove(layer.children, i) end
	end
	local n = c.GetName and c:GetName()
	if n then
		for i = #layer.removed, 1, -1 do
			if layer.removed[i] == n then
				table.remove(layer.removed, i)
				if relist then lib:RegisterSpecialFrame(n) end
			end
		end
	end
	return true
end

--- `W:RemoveEscapeChild(window, frame)` (MINOR 43): take one child back out of `window`'s Escape layer
--- -- for a transient child that outlives its stay, such as a shared frame shown in several windows. If
--- the layer took the child's name off `UISpecialFrames`, it goes back on. The layer itself, and every
--- other child, are untouched. Returns whether `frame` was a child of that layer.
---
--- NOT FROM AN OnHide THAT ESCAPE REACHES -- and the same holds for EscapeLayer and DropEscapeLayer. The
--- client closes special frames with `for _, name in pairs(UISpecialFrames)`, hiding as it goes
--- (UIParentPanelManager.lua:1041, Classic Era tree), so every OnHide it triggers -- the proxy's, a
--- child's, the window's -- runs INSIDE that walk. Lua 5.1 leaves `next` undefined if the traversal
--- assigns a new field (re-listing a name appends one), and removing an entry shifts the later ones down
--- so the walk can skip one (Lua 5.1 manual, `next`). Call these from a click or a show instead.
function lib:RemoveEscapeChild(window, frame)
	return leaveEscapeLayer(escapeFrameOf(window), escapeFrameOf(frame), true)
end

--- A panel that floats above the consuming window: UIParent-parented, TOOLTIP strata, the library's
--- backdrop, clamped to the screen, mouse-enabled, with an opaque fill inset inside the border so the
--- window behind never shows through. opts: `name` (a global name, which also puts it on the Escape
--- list), `level` (default 100), `strata`, `parent`, `inset` (default 5). Returns the frame; `frame.bg`
--- is the fill.
function lib:CreateFloatingFrame(opts)
	opts = opts or {}
	local f = CreateFrame("Frame", opts.name, opts.parent or UIParent,
		BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetBackdrop(self.FrameBackdrop)
	f:SetBackdropColor(0, 0, 0, 1)             -- solid black fill
	f:SetBackdropBorderColor(0.5, 0.5, 0.5)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetFrameStrata(opts.strata or "TOOLTIP")
	f:SetFrameLevel(opts.level or 100)
	-- Belt-and-suspenders opaque fill: a solid-black texture inside the border, so the panel is fully
	-- opaque regardless of how the backdrop's tiled bg texture renders. Contents draw above it (OVERLAY).
	local inset = opts.inset or 5
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetColorTexture(0, 0, 0, 1)
	f.bg:SetPoint("TOPLEFT",     f, "TOPLEFT",      inset, -inset)
	f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset,  inset)
	if opts.name then self:RegisterSpecialFrame(opts.name) end
	return f
end

local function Floating_OnEvent(f, event)
	if event ~= "GLOBAL_MOUSE_DOWN" then return end
	if f:IsMouseOver() then return end
	local isOver = f._lagwFloatIsOver
	if isOver and isOver(f) then return end
	local close = f._lagwFloatClose
	if close then close(f) else f:Hide() end
end

local function Floating_OnShow(f) f:RegisterEvent("GLOBAL_MOUSE_DOWN") end
local function Floating_OnHide(f) f:UnregisterEvent("GLOBAL_MOUSE_DOWN") end

--- Close `frame` when the mouse goes down anywhere that is not it or its owner. opts: `isOver(frame)`
--- -> true while the pointer is over something that must NOT close it (the frame itself is always
--- checked first), and `close(frame)` -> what closing means, defaulting to `frame:Hide()`; the menus
--- pass one because closing the root must take the whole stack with it.
---
--- It listens only while SHOWN, and registers IMMEDIATELY if the frame is already shown when it is
--- handed over -- `OpenMenu` shows the root before owning it, so an OnShow-only registration would miss
--- the first open and click-outside would do nothing until the second. Calling it again re-points the
--- options without stacking a second listener.
function lib:OwnFloating(frame, opts)
	if type(frame) ~= "table" or not frame.RegisterEvent then return nil end
	opts = opts or {}
	frame._lagwFloatIsOver, frame._lagwFloatClose = opts.isOver, opts.close
	if not frame._lagwFloatOwned then
		frame._lagwFloatOwned = true
		frame:SetScript("OnEvent", Floating_OnEvent)
		-- HookScript, not SetScript: the popup's own OnShow/OnHide carry its owner bookkeeping.
		frame:HookScript("OnShow", Floating_OnShow)
		frame:HookScript("OnHide", Floating_OnHide)
	end
	if frame:IsShown() then frame:RegisterEvent("GLOBAL_MOUSE_DOWN") end
	return frame
end

-- ---------------------------------------------------------------------------

local MENU_ROW_H, MENU_PAD, MENU_VPAD = 18, 6, 12
local MENU_GLYPH, MENU_WIDTH = 14, 160   -- the check / submenu-arrow texture; the width floor

-- Acquire (build once) the pooled menu frame for `depth`.
local function menuFrame(self, depth)
	self._menus = self._menus or {}
	local menu = self._menus[depth]
	if menu then return menu end
	-- Deeper submenus above shallower ones. The strata (TOOLTIP, above FULLSCREEN_DIALOG) and the
	-- opaque fill are the shared floating shape; see lib:CreateFloatingFrame. Menus are NOT named and
	-- therefore not on the Escape list -- Escape has never closed a menu here, and the click-outside
	-- handler below is the closer.
	menu = lib:CreateFloatingFrame({ level = 100 + depth * 10 })
	menu.rows = {}
	menu.depth = depth
	self._menus[depth] = menu
	return menu
end

-- Hide every open menu at depth >= `from` (submenu collapse / full close).
local function closeMenusFrom(self, from)
	if not self._menus then return end
	local wasOpen = from == 1 and self._menus[1] and self._menus[1]:IsShown()
	for d = #self._menus, from, -1 do
		if self._menus[d] then self._menus[d]:Hide() end
	end
	-- Closing the ROOT closes the menu; a submenu collapsing is not news (MINOR 36, OnMenuClosed).
	if wasOpen then self:_menuClosed(self._menuAnchor) end
end

-- The root menu's SEARCH box (opts.search). Built once per pooled menu frame and reused, so the frame count
-- doesn't grow with re-renders. It drives `menu._onSearch`, which renderMenu re-points on every render — the
-- indirection is what lets typing re-run the CURRENT items function rather than the one captured at the open
-- that created the box. Height is reserved above the rows; see SEARCH_H.
local SEARCH_H = 26

--- ONE definition of "this menu has a search box", because there were two and they disagreed.
---
--- Peer review finding 5 (LibAceGUIWidgets AUDIT, raised after Dibs shipped this feature): `renderMenu` built
--- and showed the box on `opts.search and opts.itemsFor`, while `OpenMenu` focused it on `opts.search` alone.
--- The menu frames are POOLED and the box outlives the open that created it, so a later call passing `search`
--- without `itemsFor` took the hide branch and then focused the EditBox it had just hidden — keyboard focus on
--- an invisible frame, with `OnEscapePressed` set on something that will not receive it.
---
--- The value here is not the branch, it is that the predicate stops being two spellings that can drift apart.
local function hasSearch(opts) return (opts.search and opts.itemsFor) and true or false end

local SEARCH_BOX_H = 20

local function searchBox(self, menu)
	if menu.search then return menu.search end
	local eb = CreateFrame("EditBox", nil, menu, "InputBoxTemplate")
	lib:_trackFocus(eb)
	eb:SetAutoFocus(false)
	eb:SetTextInsets(2, 2, 0, 0)
	if eb.SetFontObject then eb:SetFontObject(self:ScaledFont("ChatFontNormal")) end
	-- Height and anchors are (re)applied per render, where the scale is read.
	-- Only a USER keystroke re-filters. The `user` flag is the whole reason: OpenMenu clears the box on every
	-- open, and reacting to that programmatic change would re-render the list a second time on every open.
	eb:SetScript("OnTextChanged", function(box, user)
		if user and menu._onSearch then menu._onSearch(box:GetText() or "") end
	end)
	eb:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
		closeMenusFrom(self, 1)
	end)
	eb:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
	menu.search = eb
	return eb
end

-- A menu row's checked state, allowing `checked` to be a FUNCTION (evaluated live) as well as a bool — so a
-- multi-select menu (opts.keepOpen) can reflect toggles without a rebuild. A function that raises is
-- reported and reads as unchecked, so the rest of the menu is still drawn.
local function checkedOf(c)
	if type(c) == "function" then
		local ok, v = safeCall(c)
		return (ok and v) and true or false
	end
	return c and true or false
end

-- Is the pointer over ANY currently-shown menu frame (root or a submenu)?
local function overAnyMenu(self)
	if not self._menus then return false end
	for _, m in ipairs(self._menus) do
		if m:IsShown() and m:IsMouseOver() then return true end
	end
	return false
end

-- Populate + show the depth-`depth` menu with `items`, positioned by `place` (a SetPoint tuple).
local function renderMenu(self, depth, items, opts, place)
	local menu = menuFrame(self, depth)
	-- Every dimension is read at the current scale HERE, per render, so the pooled frames never carry
	-- a size from an earlier scale. `opts.widthPx` is what OpenMenu resolved from the anchor (already
	-- pixels); `opts.width` is a consumer's scale-1.0 value.
	local S = function(px) return self:ScaledSize(px) end
	local rowH, pad, vpad, glyph = S(MENU_ROW_H), S(MENU_PAD), S(MENU_VPAD), S(MENU_GLYPH)
	local width = opts.widthPx or S(opts.width or MENU_WIDTH)
	for _, row in ipairs(menu.rows) do row:Hide() end
	-- SEARCH, root menu only: a filter box above the rows. Submenus never get one — they're the RESULT of a
	-- selection in the root, so filtering them would be filtering a filter.
	local searchH = 0
	if depth == 1 and hasSearch(opts) then
		searchH = S(SEARCH_H)
		local eb = searchBox(self, menu)
		eb:SetHeight(S(SEARCH_BOX_H))
		eb:ClearAllPoints()
		eb:SetPoint("TOPLEFT",  menu, "TOPLEFT",  pad + 8, -vpad + 4)
		eb:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -pad,    -vpad + 4)
		eb:Show()
		-- An itemsFor that raises is reported and the menu keeps the rows it already shows.
		menu._onSearch = function(text)
			local ok, list = safeCall(opts.itemsFor, text)
			if ok then renderMenu(self, 1, list or {}, opts, place) end
		end
	elseif depth == 1 and menu.search then
		menu.search:Hide()
		menu._onSearch = nil
	end
	local y = -vpad - searchH
	for i, item in ipairs(items) do
		local row = menu.rows[i]
		if not row then
			row = CreateFrame("Button", nil, menu)
			row.check = row:CreateTexture(nil, "ARTWORK")
			row.check:SetPoint("LEFT", row, "LEFT", 4, 0)
			row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			row.arrow = row:CreateTexture(nil, "ARTWORK")   -- ▶ submenu indicator (shown only while hovered)
			row.arrow:SetPoint("RIGHT", row, "RIGHT", -2, 0)   -- inset so it never sits over the border
			row.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
			row.arrow:Hide()
			row.fs = row:CreateFontString(nil, "OVERLAY")
			row.fs:SetFontObject(self:ScaledFont("GameFontHighlightSmall"))
			row.fs:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
			row.fs:SetJustifyH("LEFT")
			row.fs:SetWordWrap(false)   -- single line: a long label clips, never wraps onto the next row
			row.fs:SetMaxLines(1)
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			menu.rows[i] = row
		end
		row:SetHeight(rowH)
		row.check:SetSize(glyph, glyph)
		row.arrow:SetSize(glyph, glyph)
		row:SetPoint("TOPLEFT",  menu, "TOPLEFT",  pad, y)
		row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -pad, y)
		row.fs:SetText(item.text or "")
		-- MINOR 30 (ClassicCalendar inbox 4d698ce3, item 2): a TITLE row is a gold header and a DISABLED
		-- row (an empty one is a spacer) is grey; neither selects, checks, highlights or opens a submenu.
		-- Every one of these is re-applied per render, because the rows are POOLED -- a row that was a
		-- title in the last menu must come back an ordinary choice in this one.
		local inert = item.isTitle or item.disabled
		row.fs:SetFontObject(self:ScaledFont(item.isTitle and "GameFontNormalSmall"
			or item.disabled and "GameFontDisableSmall" or "GameFontHighlightSmall"))
		local hl = row:GetHighlightTexture()
		if hl then hl:SetAlpha(inert and 0 or 1) end
		row.check:SetShown(not item.isTitle and checkedOf(item.checked))
		local children = not inert and item.children or nil
		row.arrow:Hide()   -- the ▶ shows only while this row is hovered (OnEnter/OnLeave below)
		-- Reserve room on the right for the ▶ arrow when this row has a submenu (kept even while the arrow
		-- is hidden, so the label doesn't shift on hover).
		row.fs:SetPoint("RIGHT", row, "RIGHT", children and -(glyph + 2) or -4, 0)
		-- Per-item keepOpen overrides the menu's in either direction: a keepOpen menu of checkboxes can
		-- still have one action that closes it, and a closing menu one toggle that does not.
		local keepOpen = opts.keepOpen
		if item.keepOpen ~= nil then keepOpen = item.keepOpen end
		row._lagwItem = item
		row:SetScript("OnClick", function()
			if inert or children then return end   -- parent rows expand on hover; they don't select
			-- A raising handler must not leave the menu open (MINOR 39, Peer Review b64aa131): before this
			-- the error left OnClick before the close below, so the menu stayed up and OnMenuClosed never
			-- fired. Run it protected, finish the close or refresh, THEN hand the error on.
			-- xpcall so the handler's own stack travels with the message (Peer Review, same thread);
			-- debugstack is feature-detected rather than assumed on every flavour.
			local ok, err = true, nil
			if item.onClick then
				ok, err = xpcall(item.onClick, withStack)
			end
			if keepOpen then
				-- Multi-select: reflect the toggle in place. Read from the item the row carries NOW, not
				-- the one this closure was built for: an onClick may re-render the menu (RowList's Select
				-- all does), and the pooled row at this index may then be showing a different item
				-- (MINOR 34, peer review L3).
				local now = row._lagwItem or item
				row.check:SetShown(not now.isTitle and checkedOf(now.checked))
			else
				closeMenusFrom(self, 1)
			end
			if not ok then reportError(err) end
		end)
		row:SetScript("OnEnter", function(rowFrame)
			row.arrow:SetShown(children ~= nil)   -- reveal the submenu arrow on the highlighted row
			closeMenusFrom(self, depth + 1)       -- entering any row collapses deeper submenus
			if children then
				-- A children function that raises is reported and opens no submenu; the tooltip below still shows.
				local list = children
				if type(children) == "function" then
					local ok, v = safeCall(children)
					list = ok and v or nil
				end
				if list then
					renderMenu(self, depth + 1, list, opts,
						{ "TOPLEFT", rowFrame, "TOPRIGHT", 2, self:ScaledSize(MENU_VPAD) })   -- first row level with this one
				end
			end
			-- Tooltips show on inert rows too: why an entry is disabled is exactly what one says. The same
			-- draw as AttachTooltip, by call, so a menu row's tooltip and a control's cannot drift apart.
			showTooltip(rowFrame, item.tooltipTitle, item.tooltipText)
		end)
		row:SetScript("OnLeave", function(rowFrame)
			row.arrow:Hide()
			if GameTooltip:IsOwned(rowFrame) then lib:HideTooltip() end
		end)
		row:Show()
		y = y - rowH
	end
	menu:SetSize(width, (#items * rowH) + vpad * 2 + searchH)
	menu:ClearAllPoints()
	menu:SetPoint(place[1], place[2], place[3], place[4] or 0, place[5] or 0)
	menu:Show()
	return menu
end

-- opts: { width, keepOpen, point, search, itemsFor }. `search` + `itemsFor(query) -> rows` put a filter box
-- at the top of the ROOT menu: each keystroke calls `itemsFor` again and re-renders, so the filtering rule
-- (name match, stat match, best-N-by-score, …) stays with the consumer that knows its data. Pass the rows for
-- the empty query as `items`. `point` overrides where the root opens — a placement array
-- { menuPoint, relFrame, relPoint, x, y } (e.g. { "TOPRIGHT", someFrame, "BOTTOMRIGHT", 0, -2 } to drop from
-- a top-right corner); default is below the anchor's bottom-left. `width` defaults to the anchor's width.
function lib:OpenMenu(anchor, items, opts)
	-- SHALLOW COPY, and it is a fix rather than a habit. This used to be
	-- `opts.width = opts.width or math.max(...)`, which writes the resolved width back into the table the
	-- CALLER passed — so a consumer holding a module-level options constant and reusing it across anchors of
	-- different widths gets the first anchor's width baked in permanently, for the rest of the session.
	-- Not reachable through `CreateDropdownBox` (fresh table per click), but `OpenMenu` is public.
	local src = opts or {}
	opts = {}
	for k, v in pairs(src) do opts[k] = v end
	-- A consumer's `width` is a scale-1.0 value (renderMenu scales it); the anchor's own width is
	-- already pixels, so that fallback is resolved here into `widthPx` and never scaled again.
	if not opts.width then
		opts.widthPx = math.max(self:ScaledSize(MENU_WIDTH), anchor:GetWidth() or 0)
	end
	-- The stack is re-rendered in place for a new anchor without a Hide, so the previous owner's menu
	-- closes here as far as its OnMenuClosed is concerned (MINOR 36).
	local prevRoot = self._menus and self._menus[1]
	if prevRoot and prevRoot:IsShown() and self._menuAnchor and self._menuAnchor ~= anchor then
		self:_menuClosed(self._menuAnchor)
	end
	self._menuAnchor = anchor
	local place = opts.point or { "TOPLEFT", anchor, "BOTTOMLEFT", 0, -2 }
	local root = renderMenu(self, 1, items, opts, place)
	-- A menu must not outlive its anchor's visibility. The menu frames live on UIParent at TOOLTIP strata
	-- (so they never clip inside the window), which means they DON'T hide when the anchor's window closes or
	-- its tab is released — the stack would keep floating and reappear over the next tab. So close the stack
	-- when the anchor hides (window close / tab switch fires OnHide on the anchor as a descendant). Hooked
	-- once per anchor, and only closes if this anchor still owns the open menu.
	if not anchor._agwMenuHideHook then
		anchor._agwMenuHideHook = true
		anchor:HookScript("OnHide", function()
			if self._menuAnchor == anchor then closeMenusFrom(self, 1) end
		end)
	end
	-- The root owns the click-outside close for the whole STACK: a mouse-down that is not over any open
	-- menu or the anchor button collapses everything, which is why `close` is passed -- hiding the root
	-- alone would leave a submenu floating. `OwnFloating` registers immediately because renderMenu has
	-- already shown the frame; an OnShow-only registration would miss the first open.
	self:OwnFloating(root, {
		isOver = function() return overAnyMenu(self)
			or (self._menuAnchor and self._menuAnchor:IsMouseOver()) and true or false end,
		close  = function() closeMenusFrom(self, 1) end,
	})
	-- A fresh open starts from an empty filter with the caret already in the box, so a picker is "click, type"
	-- and not "click, click, type". This SetText is a PROGRAMMATIC change — which is precisely why the box's
	-- OnTextChanged gates on the `user` flag; without that gate every open would render its list twice.
	if hasSearch(opts) and root.search then   -- the SAME predicate that decided to show it (finding 5)
		root.search:SetText("")
		root.search:SetFocus()
	end
	return root
end

function lib:CloseMenu()
	closeMenusFrom(self, 1)
end

--- How many rows a menu can show and still fit in 80% of the screen at the current scale (MINOR 34).
--- A menu does not scroll and is clamped to the screen, so a row past this is unreachable. `withSearch`
--- reserves the root menu's search box. RowList's column filter caps its value list with this; a
--- consumer building a long menu of its own can do the same.
function lib:MenuCapacity(withSearch)
	local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
	local S = function(px) return self:ScaledSize(px) end
	local room = screenH * 0.8 - S(MENU_VPAD) * 2 - (withSearch and S(SEARCH_H) or 0)
	return math.max(1, math.floor(room / S(MENU_ROW_H)))
end

-- Close the open menu only if one of the given anchors owns it. Returns whether it did (MINOR 31).
--
-- The menu stack is ONE stack shared by every consumer, so `CloseMenu()` reaches whatever is open,
-- whoever opened it. The collision is narrow and every consumer gets it wrong the same way: opening
-- yours already closed theirs, so a blind close looks harmless in every test -- what it actually
-- takes is a menu opened AFTER yours went away (ClassicCalendar: the player presses Escape in their
-- name field while another addon's menu is up). The anchor-hide hook in OpenMenu has always made
-- this check for itself; this is the same check offered to a consumer's own close path. Same shape
-- and same reason as CloseDialog(token). Requested on inbox 4d698ce3 (reply 9), where ClassicCalendar
-- had been reading `_menuAnchor` to do it.
--
--   if not W:CloseMenuFor(myBox, myOtherBox) then ... end   -- nothing of yours was open
function lib:CloseMenuFor(...)
	local root = self._menus and self._menus[1]
	if not (root and root:IsShown()) then return false end
	local owner = self._menuAnchor
	if owner == nil then return false end
	for i = 1, select("#", ...) do
		if select(i, ...) == owner then
			closeMenusFrom(self, 1)
			return true
		end
	end
	return false
end

-- Open the menu for `anchor`, or close it if it's already open for that anchor (so the
-- anchor button toggles it).
function lib:ToggleMenu(anchor, items, opts)
	local root = self._menus and self._menus[1]
	if root and root:IsShown() and self._menuAnchor == anchor then
		closeMenusFrom(self, 1)
	else
		self:OpenMenu(anchor, items, opts)
	end
end

-- A labelled dropdown BOX — a bordered button with a down-arrow and a text label that opens a
-- ToggleMenu on click. Factors the picker pattern every consuming addon was hand-rolling (loadout /
-- character / event / enchant / spec selectors). opts:
--   width, height          box size (default 170 x 22)
--   items = function(query) ... end  returns { { text=, checked=, onClick= }, ... }; built FRESH per open
--                                so dynamic lists (specs, saved sets, …) are always current. `query` is the
--                                search text and is "" unless `search` is set — existing zero-argument
--                                item functions are unaffected
--   search = true          put a filter box at the top of the menu; `items` is then re-called on every
--                          keystroke with the typed text. The consumer owns the matching rule — the library
--                          can't know whether "agi" should match a name, a stat or an item level
--   menuWidth, keepOpen    forwarded to ToggleMenu
--   tipTitle, tipBody      optional AttachTooltip
-- Returns the Button. Set the shown text via `box.label:SetText(...)`; `box.label` is the FontString.
function lib:CreateDropdownBox(parent, opts)
	opts = opts or {}
	local box = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	self:SetScaledSize(box, opts.width or 170, opts.height or 22)   -- scale-1.0 sizes, follow the scale
	box:SetBackdrop({
		bgFile   = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	box:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
	box:SetBackdropBorderColor(0.45, 0.45, 0.45)
	box:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	local arrow = box:CreateTexture(nil, "OVERLAY")
	self:SetScaledSize(arrow, 16, 16)
	arrow:SetPoint("RIGHT", box, "RIGHT", -3, -1)
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetRotation(-1.5708)   -- point the arrow downward

	local fs = box:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(self:ScaledFont("GameFontHighlight"))
	fs:SetPoint("LEFT",  box, "LEFT", 8, 0)
	fs:SetPoint("RIGHT", arrow, "LEFT", -2, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)   -- single line inside the box: a long label clips, never wraps out of the 22px height
	fs:SetMaxLines(1)
	box.label = fs

	box:SetScript("OnClick", function(self_)
		local itemsFor = opts.items or function(_) return {} end   -- takes the query, like a real items fn
		-- A raising items function is reported and the menu opens empty rather than not at all.
		local ok, first = safeCall(itemsFor, "")
		lib:ToggleMenu(self_, (ok and first) or {}, {
			width    = opts.menuWidth,
			keepOpen = opts.keepOpen,
			search   = opts.search,
			itemsFor = opts.search and itemsFor or nil,
		})
	end)
	if opts.tipTitle then lib:AttachTooltip(box, opts.tipTitle, opts.tipBody) end
	return box
end

-- A plain UIPanelButton whose tooltip EXPLAINS it -- and, when it is greyed, explains why (MINOR 33,
-- Dibs' DIBSREQ-LAGW-008). Three fields on the button, read at HOVER time and drawn in this order:
--
--   btn._lagwTipTitle   gold header    -- what this button is
--   btn._lagwTipBody    white, wrapped -- what pressing it would do
--   btn._lagwReason     red, LAST      -- why it cannot be pressed right now
--
-- READ AT HOVER, NOT AT CONSTRUCTION, and that is the whole shape of it: the same button is
-- Need/Greed/Pass on one prompt and MS/OS/Pass on another and Bid/Pass on a third, so a consumer
-- re-labels by ASSIGNMENT (`btn._lagwReason = "You already have two"`) and never by re-attaching.
-- A button with none of the three shows nothing.
--
-- WHY THIS IS NOT `AttachTooltip`, since it looks like it should be: AttachTooltip uses HookScript,
-- which is additive and runs AFTER whatever the frame already had -- so a button with its own
-- OnEnter gets its red reason line painted over by the library's plain title/body draw, which is
-- precisely the line a refused player most needs. This factory OWNS the handler (SetScript), so the
-- order is fixed and the reason is always last.
--
-- opts: width / height (scale-1.0, default 80 x 22), text, onClick, and initial tipTitle / tipBody /
-- reason. Returns the Button.
function lib:CreateExplainedButton(parent, opts)
	opts = opts or {}
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	self:SetScaledSize(btn, opts.width or 80, opts.height or 22)
	if opts.text then btn:SetText(opts.text) end
	btn._lagwTipTitle, btn._lagwTipBody, btn._lagwReason = opts.tipTitle, opts.tipBody, opts.reason

	-- The same rule `AttachTooltip` applies, through the same function -- see
	-- `allowHoverWhileDisabled` for why, and why this factory cannot simply CALL `AttachTooltip`
	-- (it owns its OnEnter with SetScript, to draw the gold title and the red reason line, where
	-- AttachTooltip's HookScript is additive). Without the flag the reason line is dead in exactly
	-- the state it exists for, and the failure is silent: the field is set, the handler is
	-- installed, and the player sees nothing.
	allowHoverWhileDisabled(btn)

	btn:SetScript("OnEnter", function(b)
		showTooltip(b, b._lagwTipTitle, b._lagwTipBody,
			{ titleColor = NORMAL_FONT_GOLD, reason = b._lagwReason })
	end)
	btn:SetScript("OnLeave", function(b) lib:HideTooltip(b) end)
	if opts.onClick then btn:SetScript("OnClick", opts.onClick) end
	return btn
end

-- ---------------------------------------------------------------------------
-- Numeric stepper:  [-] [ qty ] [+] [MAX]   (MINOR 36, TOGProfessionMaster inbox ea8db903)
-- ---------------------------------------------------------------------------
-- TOGProfessionMaster had two hand-built copies (the Crafting quantity and each Shopping List row). The
-- rules, all of them from the request:
--   * Typing: digits only (anything else is dropped as it is typed; one decimal point is kept when `step`
--     is fractional); the number COMMITS on Enter or when the box loses focus; it snaps to the nearest
--     step counted from `min` and out of range clamps; an emptied box reverts; Escape reverts.
--     Refresh() and SetBounds() leave the box's text alone while it has focus.
--   * - and + step by `step` and disable at the bounds, saying why in their tooltip -- they are
--     CreateExplainedButtons, so the reason is the red last line and still shows while greyed.
--   * MAX sets `max()`; a max of 0 (or none) disables it. `max` may be a function, read on every click and
--     every Refresh, so "as many as you can make" is always current.
--   * SetValue is SILENT. A change the PLAYER makes calls onValueChanged(value, stepper) once, and only
--     when the value actually changed.
--   * NOT DELIVERED: holding - or + to repeat. It needs a per-frame tick while the button is held, and this
--     library adds no timers of its own; a click per step is what it does.
-- Sizes are scale-1.0 and follow the scale (SetScaledSize); the box's font is the scaled ChatFontNormal.
local STEPPER_BTN, STEPPER_H, STEPPER_GAP, STEPPER_MAX_W = 22, 22, 2, 40

local function Stepper_Max(st)
	local m = st._max
	-- A max function that raises is reported and reads as no max, so the button states are still set.
	if type(m) == "function" then
		local ok, v = safeCall(m)
		m = ok and v or nil
	end
	return tonumber(m)
end

-- Snap to the nearest multiple of `step` counted from `min`, then clamp. An integer step lands exactly
-- where the old whole-number rounding did; a fractional one (0.5) keeps its fraction instead of being
-- rounded away (Peer Review, audit thread 231f14e7 item 3). The MAX bound itself is allowed off the grid.
local function Stepper_Clamp(st, v)
	v = tonumber(v) or st._value
	local step = st._step
	v = st._min + math.floor((v - st._min) / step + 0.5) * step
	if v < st._min then v = st._min end
	local mx = Stepper_Max(st)
	if mx and v > mx then v = math.max(st._min, mx) end
	return v
end

-- Re-read the bounds and set each button's state and reason. Called after every change, on show, and by
-- the consumer when `max` may have moved under it. `force` rewrites the box's text even while it has
-- focus: every change the player or the consumer MAKES passes it, and a bare Refresh() does not, so a
-- consumer refreshing on BAG_UPDATE does not wipe what the player is half-way through typing -- the
-- typed number is clamped against the new bounds when it commits on focus loss (Peer Review, audit
-- thread 231f14e7 item 2).
local function Stepper_Refresh(st, force)
	local v, mx, off = st._value, Stepper_Max(st), st._disabled
	if force == true or not st.edit:HasFocus() then st.edit:SetText(tostring(v)) end
	local atMin, atMax = v <= st._min, mx ~= nil and v >= mx
	st.minus._lagwReason = atMin and ("Already at the minimum (" .. st._min .. ").") or nil
	st.plus._lagwReason = atMax and ("Already at the maximum (" .. mx .. ").") or nil
	st.minus:SetEnabled(not off and not atMin)
	st.plus:SetEnabled(not off and not atMax)
	if st.maxButton then
		local none = not mx or mx <= 0
		st.maxButton._lagwReason = none and (st._maxReason or "None available.") or nil
		st.maxButton:SetEnabled(not off and not none)
	end
	st.edit:EnableMouse(not off)
end

-- A player's change: clamp, store, repaint, and report once if it moved.
local function Stepper_Commit(st, v)
	v = Stepper_Clamp(st, v)
	local changed = v ~= st._value
	st._value = v
	Stepper_Refresh(st, true)
	if changed and st._onChange then safeCall(st._onChange, v, st) end
end

--- `W:CreateStepper(parent, opts)` -> the stepper frame. opts: `min` (0), `max` (a number, a
--- `function() -> number`, or nil for none), `step` (1), `value` (min), `width` (the box, scale-1.0, 40),
--- `maxButton` (true builds MAX), `onValueChanged(value, stepper)`, `tipTitle` (the - and + tooltips'
--- title, default "Quantity"), `maxTip` (MAX's tooltip body) and `maxReason` (why MAX is greyed).
--- Methods: `SetValue(v)` (silent, clamped), `GetValue()`, `SetBounds(min, max)`, `SetStep(n)`,
--- `SetDisabled(bool)`, `Refresh()`. Parts: `.minus`, `.edit`, `.plus`, `.maxButton`.
function lib:CreateStepper(parent, opts)
	opts = opts or {}
	local st = CreateFrame("Frame", nil, parent)
	st._min = tonumber(opts.min) or 0
	st._max = opts.max
	st._step = (tonumber(opts.step) or 0) > 0 and tonumber(opts.step) or 1
	st._onChange = opts.onValueChanged
	st._maxReason = opts.maxReason
	st._value = st._min

	local title = opts.tipTitle or "Quantity"
	st.minus = self:CreateExplainedButton(st, { width = STEPPER_BTN, height = STEPPER_H, text = "-",
		tipTitle = title, tipBody = "One less.",
		onClick = function() Stepper_Commit(st, st._value - st._step) end })
	local eb = CreateFrame("EditBox", nil, st, "InputBoxTemplate")
	self:_trackFocus(eb)
	eb:SetAutoFocus(false)
	eb:SetJustifyH("CENTER")
	if eb.SetFontObject then eb:SetFontObject(self:ScaledFont("ChatFontNormal")) end
	self:SetScaledSize(eb, opts.width or 40, STEPPER_H)
	st.edit = eb
	st.plus = self:CreateExplainedButton(st, { width = STEPPER_BTN, height = STEPPER_H, text = "+",
		tipTitle = title, tipBody = "One more.",
		onClick = function() Stepper_Commit(st, st._value + st._step) end })
	if opts.maxButton then
		st.maxButton = self:CreateExplainedButton(st, { width = STEPPER_MAX_W, height = STEPPER_H,
			text = "MAX", tipTitle = "Max", tipBody = opts.maxTip or "The most you can have.",
			onClick = function()
				local mx = Stepper_Max(st)
				if mx and mx > 0 then Stepper_Commit(st, mx) end
			end })
	end

	-- Laid out left to right, re-laid on a scale change because the gaps and widths move with it. The
	-- widths are computed from the scale here, not read back from the parts: each part's own scale
	-- listener may not have run yet when this one does.
	local boxW = opts.width or 40
	local function layout()
		local S = function(px) return self:ScaledSize(px) end
		local g = S(STEPPER_GAP)
		st.minus:ClearAllPoints()
		st.minus:SetPoint("LEFT", st, "LEFT", 0, 0)
		-- InputBoxTemplate draws its left cap outside the box, so the box sits a little further in.
		eb:ClearAllPoints()
		eb:SetPoint("LEFT", st.minus, "RIGHT", g * 3, 0)
		st.plus:ClearAllPoints()
		st.plus:SetPoint("LEFT", eb, "RIGHT", g * 2, 0)
		local w = S(STEPPER_BTN) * 2 + S(boxW) + g * 5
		if st.maxButton then
			st.maxButton:ClearAllPoints()
			st.maxButton:SetPoint("LEFT", st.plus, "RIGHT", g, 0)
			w = w + g + S(STEPPER_MAX_W)
		end
		st:SetSize(w, S(STEPPER_H))
	end
	layout()
	self:OnScaleChanged(st, function(_, _, s) s:_layout() end)
	st._layout = layout

	-- Digits only, as they are typed -- plus ONE decimal point when the step is fractional, or a 0.5 step
	-- could be clicked to but never typed. A programmatic SetText (the repaint) is not user input.
	eb:SetScript("OnTextChanged", function(box, userInput)
		if not userInput then return end
		local text = box:GetText() or ""
		local clean
		if st._step % 1 ~= 0 then
			local int, frac = text:match("^([^%.]*)%.?(.*)$")
			clean = int:gsub("%D", "")
			if text:find(".", 1, true) then clean = clean .. "." .. frac:gsub("%D", "") end
		else
			clean = text:gsub("%D", "")
		end
		if clean ~= text then box:SetText(clean) end
	end)
	local function commitTyped(box)
		local text = box:GetText() or ""
		if tonumber(text) == nil then Stepper_Refresh(st, true) else Stepper_Commit(st, tonumber(text)) end
	end
	eb:SetScript("OnEnterPressed", function(box) commitTyped(box); box:ClearFocus() end)
	eb:SetScript("OnEditFocusLost", commitTyped)
	eb:SetScript("OnEscapePressed", function(box)
		Stepper_Refresh(st, true)   -- revert first, so the focus loss that follows commits the old value
		box:ClearFocus()
	end)
	st:SetScript("OnShow", function(s) Stepper_Refresh(s, true) end)

	function st:SetValue(v)
		self._value = Stepper_Clamp(self, v)
		Stepper_Refresh(self, true)
	end
	function st:GetValue() return self._value end
	-- Not forced: a consumer re-bounding on BAG_UPDATE must not wipe a half-typed number either.
	function st:SetBounds(mn, mx)
		self._min = tonumber(mn) or 0
		self._max = mx
		self._value = Stepper_Clamp(self, self._value)
		Stepper_Refresh(self)
	end
	-- A step of zero or less would divide by zero in Stepper_Clamp; it falls back to 1. The value is
	-- re-snapped onto the new grid, as SetBounds re-clamps it, or one click from an off-grid value would
	-- move by more than the step (Peer Review, audit thread 231f14e7, reply c65c5b43). Not forced, like
	-- SetBounds.
	function st:SetStep(n)
		n = tonumber(n)
		self._step = (n and n > 0) and n or 1
		self._value = Stepper_Clamp(self, self._value)
		Stepper_Refresh(self)
	end
	function st:SetDisabled(off)
		self._disabled = off and true or false
		if off then eb:ClearFocus() end
		Stepper_Refresh(self, true)
	end
	-- The public Refresh never forces: it is what a consumer calls when `max` may have moved.
	function st:Refresh() Stepper_Refresh(self) end

	st:SetValue(opts.value)
	return st
end

-- ---------------------------------------------------------------------------
-- Docked-panel layout (MINOR 36, TOGProfessionMaster inbox 2f9efc9e)
-- ---------------------------------------------------------------------------
--   local dock = W:NewDockLayout(tabGroup, { top = 28, right = 220, bottom = "auto", minCenter = 200 })
--   dock.top      -- toolbar strip, full width
--   dock.center   -- (also dock.left) what is left: the list goes here, and always has a real size
--   dock.right    -- side panel, between top and bottom
--   dock.bottom   -- detail panel, full width; "auto" = the height you give dock:SetBottomHeight(px)
--
-- Four raw frames the LIBRARY owns, anchored into the container's content frame, so they follow a
-- resize (a MakeResizable drag included) through their anchors alone -- no method of the pooled AceGUI
-- widget is replaced and no script is hooked onto its frames. The sizes are re-decided by one extra
-- frame of ours laid over the content, whose OnSizeChanged runs the layout, and by the scale listener:
--   * `top`, `right` and a fixed `bottom` are scale-1.0 values; an "auto" bottom is pixels, set by the
--     consumer from what it measured.
--   * The centre never collapses while the container has room: the top is capped one pixel short of the
--     height, the bottom to what is left under it, and the right so the centre keeps `minCenter`
--     (scale-1.0, default 1). A RowList in the centre therefore always has a height.
--   * `dock:SetPaneShown(name, bool)` hides a pane and gives its space to the centre.
-- Released with the container when it is an AceGUI widget (every frame hidden and handed to UIParent,
-- as RowList:Detach does), or by `dock:Release()` for a raw frame. A released dock does nothing.
local DOCK_PANES = { "top", "right", "bottom", "center" }

local DockLayout = {}
DockLayout.__index = DockLayout

function DockLayout:Relayout()
	if self._released then return end
	local host, o = self.host, self.opts
	local S = function(px) return lib:ScaledSize(px) end
	local W_, H_ = host:GetWidth() or 0, host:GetHeight() or 0
	local shown = self._shown
	local topH = shown.top and math.min(S(tonumber(o.top) or 0), math.max(0, H_ - 1)) or 0
	local botReq = 0
	if shown.bottom then
		if o.bottom == "auto" then botReq = self._bottomH or 0 else botReq = S(tonumber(o.bottom) or 0) end
	end
	local botH = math.min(botReq, math.max(0, H_ - topH - 1))
	local minC = S(tonumber(o.minCenter) or 1)
	local rightW = shown.right and math.min(S(tonumber(o.right) or 0), math.max(0, W_ - minC)) or 0

	local p = self.panes
	p.top:ClearAllPoints()
	p.top:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
	p.top:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
	p.top:SetHeight(math.max(topH, 0.001))
	p.bottom:ClearAllPoints()
	p.bottom:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
	p.bottom:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
	p.bottom:SetHeight(math.max(botH, 0.001))
	p.right:ClearAllPoints()
	p.right:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -topH)
	p.right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, botH)
	p.right:SetWidth(math.max(rightW, 0.001))
	p.center:ClearAllPoints()
	p.center:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -topH)
	p.center:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -rightW, botH)
	for _, name in ipairs(DOCK_PANES) do
		p[name]:SetShown(shown[name] and true or false)
	end
	self.sizes = { top = topH, bottom = botH, right = rightW,
		centerW = math.max(0, W_ - rightW), centerH = math.max(0, H_ - topH - botH) }
end

--- Show or hide one pane ("top", "right" or "bottom"); its space goes to the centre.
function DockLayout:SetPaneShown(name, on)
	if name == "center" or self.panes[name] == nil then return end
	self._shown[name] = on and true or false
	self:Relayout()
end

--- The height, in pixels, of an `"auto"` bottom pane: what the consumer measured its content to be.
function DockLayout:SetBottomHeight(px)
	self._bottomH = math.max(0, tonumber(px) or 0)
	self:Relayout()
end

--- Take the dock off its container for good. Idempotent.
function DockLayout:Release()
	if self._released then return end
	self._released = true
	lib:OnScaleChanged(self, nil)
	for _, f in ipairs({ self.panes.top, self.panes.right, self.panes.bottom, self.panes.center, self.sizer }) do
		f:Hide()
		f:ClearAllPoints()
		f:SetParent(UIParent)
	end
end

local function Dock_OnScaleChanged(_, _, dock) dock:Relayout() end

--- `W:NewDockLayout(container, { top, right, bottom = n|"auto", minCenter })` -> the dock. `container` is
--- an AceGUI container (its `content` frame is used) or a raw frame. Omit a size to leave that pane out.
function lib:NewDockLayout(container, opts)
	if type(container) ~= "table" then return nil end
	local host = container.content or container.frame or container
	if type(host) ~= "table" or not host.GetWidth then return nil end
	opts = opts or {}
	local dock = setmetatable({ host = host, opts = opts, panes = {}, _shown = {} }, DockLayout)
	for _, name in ipairs(DOCK_PANES) do
		dock.panes[name] = CreateFrame("Frame", nil, host)
		dock[name] = dock.panes[name]
	end
	dock.left = dock.center
	dock._shown.top = opts.top ~= nil
	dock._shown.right = opts.right ~= nil
	dock._shown.bottom = opts.bottom ~= nil
	dock._shown.center = true
	-- Ours, over the content, so a resize reaches the layout without touching the widget's own scripts.
	local sizer = CreateFrame("Frame", nil, host)
	sizer:SetAllPoints(host)
	sizer:SetScript("OnSizeChanged", function() dock:Relayout() end)
	dock.sizer = sizer
	self:OnScaleChanged(dock, Dock_OnScaleChanged)
	if container ~= host and container.frame then
		self:OnWidgetRelease(container, "lagwDock", function() dock:Release() end)
	end
	dock:Relayout()
	return dock
end

-- ---------------------------------------------------------------------------
-- Secure action button (MINOR 36, TOGProfessionMaster inbox 3d04549b)
-- ---------------------------------------------------------------------------
-- A button that casts or uses something through the client's own secure handler, with the combat
-- guards every hand-rolled copy needs. What was read, rather than assumed:
--   * Key down vs key up (Classic Era Blizzard_FrameXML/SecureTemplates.lua:789-823):
--     SecureActionButton_OnClick acts on exactly ONE of the down and up events, chosen by the button's
--     `useOnKeyDown` attribute or else the ActionButtonUseKeyDown CVar. So registering for both
--     ("AnyUp", "AnyDown") fires once under either setting; registering for one would do nothing
--     under the other -- unless `useOnKeyDown` is pinned to match, which is what opts.clicks = "up" does.
--   * SetParent is IsProtectedFunction (SimpleScriptRegionAPIDocumentation.lua:540, all three Classic
--     trees), and a protected frame's anchors, visibility and attributes cannot be changed in combat.
--   * A frame that PARENTS a secure button is itself treated as protected (Warcraft Wiki, "Secure
--     Execution and Tainting" -- web, not the client source): the consumer's window then cannot be
--     hidden in combat either.
-- So: NOT SAFE TO POOL, AND NOT SAFE IN A POOLED FRAME. Parent it to a frame the consumer owns for the
-- session, never to an AceGUI widget's frame (the next addon to acquire that frame would inherit the
-- protection). Build it out of combat -- the factory returns nil in combat. Re-parenting is allowed only
-- out of combat, which `SetParent` on the button enforces like the other guarded calls.
--
-- Guarded calls: SetAction(attrs) applies secure attributes, and the button's own SetPoint /
-- ClearAllPoints / SetSize / Show / Hide / SetEnabled / SetParent are wrapped on the instance. Out of
-- combat each runs at once; in combat it is QUEUED and the queue runs once, in order, on
-- PLAYER_REGEN_ENABLED. The button never calls a protected function from insecure code in combat -- the
-- click itself is the client's secure handler. The tooltip is CreateExplainedButton's: `_lagwTipTitle`,
-- `_lagwTipBody`, `_lagwReason` read at hover, and it shows while disabled.

-- One queue for the session, on the library table so an upgraded copy keeps what an older one queued.
lib._secureQueue = lib._secureQueue or {}

local function Secure_Flush()
	if InCombatLockdown() then return end
	local q = lib._secureQueue
	lib._secureQueue = {}
	for _, fn in ipairs(q) do fn() end
end

--- Run `fn` now, or queue it for the end of combat. Returns true when it ran now.
local function secureRun(fn)
	if not InCombatLockdown() then
		fn()
		return true
	end
	local q = lib._secureQueue
	q[#q + 1] = fn
	if not lib._secureWatcher then
		local w = CreateFrame("Frame")
		w:RegisterEvent("PLAYER_REGEN_ENABLED")
		lib._secureWatcher = w
	end
	lib._secureWatcher:SetScript("OnEvent", Secure_Flush)
	return false
end

-- Every spelling of the same change is guarded, not only one: Enable/Disable are SetEnabled, and
-- SetWidth/SetHeight/SetAllPoints are SetSize/SetPoint, and a consumer reaches for whichever it knows.
-- Shadowing them with Lua fields would taint any SECURE caller of these methods on this button (Peer
-- Review, audit thread 231f14e7). Read for that, and there is none: the secure click path
-- (Classic Era Blizzard_FrameXML/SecureTemplates.lua:213-823) calls only GetID, GetAttribute,
-- SetAttribute, ExecuteAttribute and Click; the templates' scripts (SecureUIPanelTemplates.lua:166-209)
-- only set textures; and UIButtonFitToTextBehaviorMixin:FitToText's SetWidth (line 218) runs only when
-- an addon calls it, which is exactly the call the guard is for. A restricted-environment frame handle
-- calls the C methods, not these fields. Not verified in a client.
local SECURE_GUARDED = { "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight",
	"Show", "Hide", "SetShown", "SetEnabled", "Enable", "Disable", "SetParent" }

--- `W:CreateSecureActionButton(parent, opts)` -> the Button, or nil in combat. opts: `name` (a global
--- name, recommended for a secure frame), `text`, `width` / `height` (scale-1.0, 80 x 22; re-applied on a
--- scale change, queued in combat), `action` (initial attributes), `preClick(button, mouseButton, down)`
--- and `postClick(...)` for the consumer's bookkeeping (insecure: they may not change attributes in
--- combat), and `tipTitle` / `tipBody` / `reason`. `button:SetAction({ type = "macro", macrotext = ... })`
--- returns true when applied now, false when queued.
---
--- `opts.clicks = "up"` (MINOR 44, Ultimate Guild Roster inbox d761a47e): ONE PreClick/PostClick pair per
--- click, on the half the action runs on. By default both halves are registered, so preClick and
--- postClick run twice per mouse click and are not told which half acted -- UGR re-armed its next batch
--- in the down's postClick and the up then ran it. With "up" the button registers "AnyUp" only and pins
--- the `useOnKeyDown` attribute to false, so the secure handler acts on the up under either setting of
--- the ActionButtonUseKeyDown CVar (SecureTemplates.lua:807-808). A keybinding to the button follows the
--- same rule and acts on key release. Do not also set `pressAndHoldAction` or `useOnKeyDown` through
--- SetAction on such a button: either one asks for the down this mode does not register.
function lib:CreateSecureActionButton(parent, opts)
	if InCombatLockdown() then return nil end
	opts = opts or {}
	local b = CreateFrame("Button", opts.name, parent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
	if opts.clicks == "up" then
		b:RegisterForClicks("AnyUp")
		b:SetAttribute("useOnKeyDown", false)
	else
		b:RegisterForClicks("AnyUp", "AnyDown")
	end
	if opts.text then b:SetText(opts.text) end
	b._lagwTipTitle, b._lagwTipBody, b._lagwReason = opts.tipTitle, opts.tipBody, opts.reason
	allowHoverWhileDisabled(b)
	b:SetScript("OnEnter", function(btn)
		showTooltip(btn, btn._lagwTipTitle, btn._lagwTipBody,
			{ titleColor = NORMAL_FONT_GOLD, reason = btn._lagwReason })
	end)
	b:SetScript("OnLeave", function(btn) lib:HideTooltip(btn) end)
	if opts.preClick then b:SetScript("PreClick", opts.preClick) end
	if opts.postClick then b:SetScript("PostClick", opts.postClick) end

	for _, method in ipairs(SECURE_GUARDED) do
		local raw = b[method]
		b[method] = function(self_, ...)
			local n, args = select("#", ...), { ... }
			return secureRun(function() raw(self_, unpack(args, 1, n)) end)
		end
	end

	function b:SetAction(attrs)
		return secureRun(function()
			for k, v in pairs(attrs or {}) do self:SetAttribute(k, v) end
		end)
	end

	local w, h = opts.width or 80, opts.height or 22
	b:SetSize(self:ScaledSize(w), self:ScaledSize(h))
	self:OnScaleChanged(b, function(_, _, btn) btn:SetSize(lib:ScaledSize(w), lib:ScaledSize(h)) end)
	if opts.action then b:SetAction(opts.action) end
	return b
end

-- ---------------------------------------------------------------------------
-- Secure overlay button (MINOR 48, TOGProfessionMaster inbox 48ef6be4)
-- ---------------------------------------------------------------------------
-- A secure button drawn OVER a panel inside a pooled AceGUI window without being part of it. Three
-- in-game failures in TOGProfessionMaster's hand-rolled copy shaped every rule here:
--   * A secure child protects every ancestor, and protection also carries to frames it is anchored to
--     (Warcraft Wiki, "Secure Execution and Tainting" -- web, not the client source; TOGPM's report of
--     2026-09-26 was ADDON_ACTION_BLOCKED Frame:Hide() closing the window in combat). So the button
--     lives on a library-owned holder parented to UIParent, and nothing of the panel's or window's is
--     ever its parent or anchor: the holder spans UIParent at the panel's effective scale, and the
--     button is pinned to the holder's BOTTOMLEFT at the panel's own coordinates, re-read on change.
--   * The AceGUI Frame is Toplevel (AceGUIContainer-Frame.lua:194): every click on it Raises it over
--     everything in its strata. Chasing its level (TOGPM: window level + 100 on each Raise) climbed both
--     to the ceiling, and the button ended up under the window's translucent backdrop, dim red and
--     dead to clicks (Discord 2026-10-30). A Raise cannot leave its strata, so the button is drawn in
--     the strata ABOVE the panel's, set on holder AND button, at a FIXED level that never chases.
--   * The button outlived the window once (in game 2026-10-18; the cause was never found). So
--     visibility is not left to OnHide alone: a plain watcher frame re-reads the panel's IsVisible and
--     rect every frame while the panel is shown, and the window's AceGUI Release lets go outright.
-- Combat: a secure state driver ("[combat] hide; show", Blizzard's own SecureStateDriver, which may
-- hide a protected frame then) hides the holder for all of combat, and every protected call here runs
-- out of combat only. PLAYER_REGEN_ENABLED re-syncs every overlay. Not verified in a client.
-- ONE file-scope local for all of it (Tests/localheadroom_spec.lua: the file is near Lua 5.1's limit).
-- Instances take their methods through the metatable; the helpers are fields of the same table.
local Overlay = {
	STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" },
	LEVEL = 10,   -- fixed; the button sits one above it
}
Overlay.__index = Overlay

--- The strata one above `strata`; TOOLTIP for the top one or a name this list does not know.
function Overlay.StrataAbove(strata)
	local list = Overlay.STRATA
	for i = 1, #list - 1 do
		if list[i] == strata then return list[i + 1] end
	end
	return "TOOLTIP"
end
lib._OverlayStrata = Overlay.StrataAbove

-- The panel-relative anchor of `point`, in the panel's own units, or nil while it has no rect.
function Overlay.Anchor(panel, point)
	local l, r, t, b = panel:GetLeft(), panel:GetRight(), panel:GetTop(), panel:GetBottom()
	if not (l and r and t and b) then return nil end
	local x = point:find("LEFT") and l or point:find("RIGHT") and r or (l + r) / 2
	local y = point:find("TOP") and t or point:find("BOTTOM") and b or (t + b) / 2
	return x, y
end

-- Every overlay ever built, for the session (a secure frame cannot be destroyed), on the library table
-- so an upgraded copy still syncs what an older one built. Keyed by name too, so a consumer that
-- rebuilds its panel per window gets its one button back instead of leaking another secure frame.
lib._overlays = lib._overlays or {}
lib._overlaysByName = lib._overlaysByName or {}
-- panel -> set of overlays on it, kept HERE rather than on the panel, so a pooled panel carries
-- nothing of ours into the next addon but a hook that finds an empty set. Weak both ways.
lib._overlayPanels = lib._overlayPanels or setmetatable({}, { __mode = "k" })

-- Everything that decides where and whether the button is drawn. A change re-places it.
function Overlay.Key(o)
	local panel = o.panel
	if not panel then return nil end
	local x, y = Overlay.Anchor(panel, o.point)
	if not x then return "norect" end
	-- The library scale too: the offsets are scale-1.0 and go through ScaledSize (Peer Review 38e05fb4 #3).
	return string.format("%.2f:%.2f:%.4f:%.4f:%s:%s", x, y, panel:GetEffectiveScale(), lib:GetScale(),
		tostring(panel:GetFrameStrata()), tostring(panel:IsVisible()))
end

function Overlay.Sync(o)
	if InCombatLockdown() then return false end
	local btn, holder, panel = o.button, o.holder, o.panel
	local want = panel ~= nil and panel:IsVisible()
	if want and o.isWanted then
		local ok, v = safeCall(o.isWanted)
		want = ok and v and true or false
	end
	local x, y
	if want then x, y = Overlay.Anchor(panel, o.point) end
	if want and x then
		local strata = Overlay.StrataAbove(panel:GetFrameStrata())
		holder:SetFrameStrata(strata)
		holder:SetFrameLevel(Overlay.LEVEL)
		btn:SetFrameStrata(strata)
		btn:SetFrameLevel(Overlay.LEVEL + 1)
		local uiScale = UIParent:GetEffectiveScale()
		if uiScale and uiScale > 0 then holder:SetScale(panel:GetEffectiveScale() / uiScale) end
		btn:ClearAllPoints()
		btn:SetPoint(o.point, holder, "BOTTOMLEFT", x + lib:ScaledSize(o.x), y + lib:ScaledSize(o.y))
		btn:Show()
	else
		btn:Hide()
	end
	o.placedAt = Overlay.Key(o)
	-- Watch whenever the panel is attached and shown, not only while the button is: a panel with no
	-- rect yet keeps the button hidden, and only the watcher sees the rect arrive.
	if panel and panel:IsVisible() then o.watcher:Show() else o.watcher:Hide() end
	return true
end

function Overlay.OnUpdate(watcher)
	if InCombatLockdown() then return end
	local o = watcher._lagwOverlay
	if Overlay.Key(o) ~= o.placedAt then Overlay.Sync(o) end
end

function Overlay.Regen()
	for _, o in ipairs(lib._overlays) do o:Sync() end
end

--- Detach from the panel: hide, stop watching, and turn the panel's hooks inert. Idempotent.
function Overlay.Detach(o)
	local panel = o.panel
	local set = panel and lib._overlayPanels[panel]
	if set then set[o] = nil end
	if o.releaseWidget then
		lib:OnWidgetRelease(o.releaseWidget, o, false)
		o.releaseWidget = nil
	end
	o.panel = nil
	o.watcher:Hide()
	if not InCombatLockdown() then o.button:Hide() end
end

function Overlay.PanelChanged(panel)
	for o in pairs(lib._overlayPanels[panel] or {}) do
		if o.panel == panel then o:Sync() end
	end
end

-- The INNERMOST AceGUI widget whose frame is `f` or contains it (AceGUI sets `frame.obj`), or nil.
-- Innermost, not outermost (Peer Review 38e05fb4 #1): a TabGroup tab switch releases the inner widget
-- alone through ReleaseChildren (Ace3 AceGUI-3.0.lua:465) while the window stays open, and that frame
-- goes back to the pool -- hooked on the window, the button stayed on it and would show over the next
-- addon's widget. The window's own Release reaches the inner widget through ReleaseChildren too
-- (AceGUI-3.0.lua:178), so the innermost hook fires in both cases.
function Overlay.InnermostWidget(f)
	while f do
		local obj = rawget(f, "obj")
		if type(obj) == "table" and obj.frame == f then return obj end
		f = f.GetParent and f:GetParent() or nil
	end
	return nil
end

--- Attach to `panel` (a new one, or the same again). Out of combat it is placed at once; in combat it
--- is recorded and placed on PLAYER_REGEN_ENABLED.
function Overlay.SetPanel(o, panel)
	if o.panel and o.panel ~= panel then o:Detach() end
	o.panel = panel
	local set = lib._overlayPanels[panel]
	if not set then
		set = setmetatable({}, { __mode = "k" })
		lib._overlayPanels[panel] = set
		panel:HookScript("OnShow", Overlay.PanelChanged)
		panel:HookScript("OnHide", Overlay.PanelChanged)
	end
	set[o] = true
	-- A pooled widget lets go by itself: its frame goes back to AceGUI's pool on Release and the next
	-- addon gets it, so the button must not keep following anything inside it.
	local widget = Overlay.InnermostWidget(panel)
	if o.releaseWidget and o.releaseWidget ~= widget then lib:OnWidgetRelease(o.releaseWidget, o, false) end
	o.releaseWidget = widget
	if widget then lib:OnWidgetRelease(widget, o, function() o:Detach() end) end
	return o:Sync()
end

--- `button:SetOverlayPoint(point, x, y)` -- move it within the panel. x / y are scale-1.0 and follow
--- the library scale (ScaledSize), like the button's width and height.
function Overlay.SetOverlayPoint(o, point, x, y)
	o.point, o.x, o.y = point or o.point, x or 0, y or 0
	return o:Sync()
end

--- `W:CreateSecureOverlayButton(panel, opts)` -> the Button, or nil in combat. opts: everything
--- `CreateSecureActionButton` takes, plus `point` / `x` / `y` (where on the panel, default "TOPRIGHT",
--- 0, 0; the button's own `point` is pinned there), `isWanted()` -> bool (the consumer's extra rule,
--- read on every sync; an error reads as false), and `onCreate(button)`.
---
--- IN COMBAT the factory returns nil and builds it on leaving combat, then calls `opts.onCreate(button)`
--- -- CreateSecureActionButton refuses in combat, so there is nothing to return yet. A second in-combat
--- call with the same unbuilt name replaces the pending panel and opts rather than queueing another
--- build, so onCreate runs once, with the latest call's (Peer Review 38e05fb4 #4).
---
--- `opts.name` is the KEY: a second call with a name already built returns THAT button re-attached
--- to the new panel with the new placement and `isWanted`, so a window rebuilt per open reuses one
--- secure button instead of making another each time. Recommended.
---
--- The button carries `:SetOverlayPoint(point, x, y)`, `:Sync()` (re-read `isWanted` and the panel;
--- false in combat, when the regen re-sync covers it), `:SetPanel(panel)` and `:Detach()`. A release of
--- the innermost AceGUI widget around the panel detaches it; call `:SetPanel` (or the factory, by name)
--- again with the next panel.
---
--- THE COST OF THE STRATA ABOVE (Peer Review 38e05fb4 #2): over an AceGUI Frame (FULLSCREEN_DIALOG) the
--- button is in TOOLTIP. Another window dragged over the panel's -- any other AceGUI Frame is
--- FULLSCREEN_DIALOG too -- does not cover the button: it draws through that window and takes its clicks
--- there. It also shares TOOLTIP with GameTooltip at a fixed level, so whether a tooltip over that corner
--- draws under it is not known. Chosen anyway: a same-strata button lost every click to the window's
--- Toplevel Raise (Discord 2026-10-30). Neither cost is verified in a client.
lib._overlayPending = lib._overlayPending or {}

function lib:CreateSecureOverlayButton(panel, opts)
	opts = opts or {}
	if type(panel) ~= "table" or not panel.HookScript then return nil end
	local existing = opts.name and lib._overlaysByName[opts.name]
	if existing then
		local o = existing._lagwOverlay
		o.isWanted = opts.isWanted
		o.point, o.x, o.y = opts.point or "TOPRIGHT", opts.x or 0, opts.y or 0
		o:SetPanel(panel)
		return existing
	end
	if InCombatLockdown() then
		-- A panel whose widget is released before combat ends is dropped, so the regen build never lands
		-- on a frame already back in AceGUI's pool (Peer Review 38e05fb4 follow-up): Release does not
		-- clear frame.obj, so InnermostWidget at regen would still find the released widget.
		local function watch(pending)
			if pending.widget then lib:OnWidgetRelease(pending.widget, pending, false) end
			pending.widget, pending.dropped = Overlay.InnermostWidget(pending.panel), false
			if pending.widget then
				lib:OnWidgetRelease(pending.widget, pending, function() pending.dropped = true end)
			end
		end
		local pending = opts.name and lib._overlayPending[opts.name]
		if pending then
			pending.panel, pending.opts = panel, opts
			watch(pending)
			return nil
		end
		pending = { panel = panel, opts = opts }
		watch(pending)
		if opts.name then lib._overlayPending[opts.name] = pending end
		secureRun(function()
			if opts.name then lib._overlayPending[opts.name] = nil end
			if pending.widget then lib:OnWidgetRelease(pending.widget, pending, false) end
			if pending.dropped then return end
			local b = lib:CreateSecureOverlayButton(pending.panel, pending.opts)
			if b and pending.opts.onCreate then safeCall(pending.opts.onCreate, b) end
		end)
		return nil
	end

	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetAllPoints(UIParent)
	if _G.RegisterStateDriver then _G.RegisterStateDriver(holder, "visibility", "[combat] hide; show") end
	local b = self:CreateSecureActionButton(holder, opts)
	if not b then return nil end   -- unreachable out of combat; the factory's own guard
	b:Hide()

	local watcher = CreateFrame("Frame")
	watcher:Hide()
	watcher:SetScript("OnUpdate", Overlay.OnUpdate)

	local o = setmetatable({ button = b, holder = holder, watcher = watcher, isWanted = opts.isWanted,
		point = opts.point or "TOPRIGHT", x = opts.x or 0, y = opts.y or 0 }, Overlay)
	watcher._lagwOverlay = o
	b._lagwOverlay, b._lagwHolder = o, holder
	function b:SetOverlayPoint(point, x, y) return o:SetOverlayPoint(point, x, y) end
	function b:Sync() return o:Sync() end
	function b:SetPanel(p) return o:SetPanel(p) end
	function b:Detach() return o:Detach() end

	lib._overlays[#lib._overlays + 1] = o
	if opts.name then lib._overlaysByName[opts.name] = b end
	if not lib._overlayRegen then
		lib._overlayRegen = CreateFrame("Frame")
		lib._overlayRegen:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
	lib._overlayRegen:SetScript("OnEvent", Overlay.Regen)

	o:SetPanel(panel)
	return b
end

-- A labelled checkbox bound to a getter and a setter (MINOR 30, ClassicCalendar inbox 4d698ce3 item 5).
--   label               text beside the box
--   tipTitle, tipBody   optional AttachTooltip
--   get()               -> boolean; read when built, every time the box is shown, and on cb:Refresh()
--   set(checked)        called on a click with the new state; the box then shows get() again, so a
--                       setter that refuses the change is shown refusing it
--   size                scale-1.0 edge (default 26, OptionsBaseCheckButtonTemplate's), follows the scale
--   font                a font object name for the label (default GameFontNormalSmall), scaled
-- Returns the CheckButton; `cb.label` is its FontString. Built on UICheckButtonTemplate
-- (Blizzard_SharedXML CheckButtonTemplates.xml:50), which every flavour ships -- not on
-- OptionsBaseCheckButtonTemplate, which classic_era already files under DeprecatedTemplates.xml.
-- A getter that errors is reported and the box is left as it is; a setter that errors is reported and
-- the box still shows get(), so a failed setter reads as refused.
local function Checkbox_Refresh(cb)
	local get = cb._lagwGet
	if not get then return end
	local ok, v = safeCall(get)
	if ok then cb:SetChecked(v and true or false) end
end

local function Checkbox_OnClick(cb)
	local on = cb:GetChecked() and true or false
	if PlaySound and SOUNDKIT then
		PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	end
	if cb._lagwSet then safeCall(cb._lagwSet, on) end
	Checkbox_Refresh(cb)
end

function lib:CreateCheckbox(parent, opts)
	opts = opts or {}
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	self:SetScaledSize(cb, opts.size or 26, opts.size or 26)
	local fs = cb.Text or cb.text
	if not fs then
		fs = cb:CreateFontString(nil, "ARTWORK")
		fs:SetPoint("LEFT", cb, "RIGHT", -2, 0)   -- the template's own anchor
	end
	fs:SetFontObject(self:ScaledFont(opts.font or "GameFontNormalSmall"))
	fs:SetText(opts.label or "")
	cb.label = fs
	cb._lagwGet, cb._lagwSet = opts.get, opts.set
	cb.Refresh = Checkbox_Refresh
	cb:SetScript("OnClick", Checkbox_OnClick)
	cb:HookScript("OnShow", Checkbox_Refresh)
	if opts.tipTitle or opts.tipBody then self:AttachTooltip(cb, opts.tipTitle, opts.tipBody) end
	Checkbox_Refresh(cb)
	return cb
end

-- A small prompt dialog parented INTO `parent` and raised above it (Blizzard StaticPopups render at
-- DIALOG strata, below a window at higher strata, so they hide behind it — this owns its frame and
-- lifts its level instead). One dialog is reused per lib instance, and `parent` IS re-applied on
-- every call (parent, anchor, strata and level), so a later caller's prompt is never trapped inside
-- an earlier caller's window. WHAT PARENTING COSTS: the prompt inherits the parent's visibility, so a
-- prompt parented into a window goes off screen with that window and comes back with it -- for a
-- confirm ABOUT that window that is the feature (ClassicCalendar's delete-event confirm, parented to
-- CalendarFrame); for anything that should stay on screen regardless, pass UIParent. The prompt is
-- still OPEN while the window is away: Enter and Escape work again when it returns, `CloseDialog`
-- still matches its token, and `onHide` has not run (MINOR 33; before that the parent's hide cleared
-- all three and a returning prompt was dead). To dismiss your own prompt use CloseDialog(token),
-- never dialog:Hide() (see below). opts:
--   prompt              the question / message text
--   hasEdit             show a text input (default true); false = a plain confirm
--   default             initial edit text
--   okText, cancelText  button captions (cancelText defaults to CANCEL; `false` = one button, OK centred)
--   onAccept(value)     called on OK / Enter; value = the edit text, or nil when hasEdit is false
--   onShow(dialog)      called once the dialog is visible                          (MINOR 30)
--   onHide(dialog)      called ONCE when it closes, however it closes -- OK, Cancel, Escape, or a later
--                       ShowDialog replacing it -- so a PushModal/PopModal pair always balances. The
--                       parent window hiding is NOT a close and does not run it (MINOR 33)
--   style, title        `style = "window"` draws BasicFrameTemplateWithInset with `title` in its bar and
--                       a close X that is Cancel; omitted, the UI-DialogBox look as before (MINOR 42,
--                       see lib.DIALOG_STYLES)
-- Keys (MINOR 30): with an edit box, the box owns Enter/Escape as before. Without one, Enter accepts and
-- Escape cancels -- but only a dialog shown OUT OF COMBAT listens, because a frame that takes the
-- keyboard must pass every other key on with SetPropagateKeyboardInput, which insecure code may not call
-- in combat (HasRestrictions, SimpleFrameAPIDocumentation.lua:1233); a frame that cannot pass keys on
-- eats them and the player cannot move. Escape ALSO works through UISpecialFrames, in or out of combat.
-- The dialog's geometry, at the current scale. Applied on every show rather than once at build:
-- the frame is reused for the whole session and the scale may have moved since the last prompt.
local function layoutDialog(self, d)
	local S = function(px) return self:ScaledSize(px) end
	-- The window style's inset starts 24px down (BasicFrameTemplateWithInset's InsetBg at y -24,
	-- Blizzard_UIPanelTemplates/Classic/UIPanelTemplates.xml:756) where the plain backdrop's starts 6px
	-- down, so the frame grows 22 and the prompt drops 22: the prompt keeps 12px above it inside the plain
	-- border and gets 16px inside the inset. Everything below the prompt is anchored to it or the bottom.
	local bar = d._lagwStyle == "window" and 22 or 0
	d:SetSize(S(320), S(116 + bar))
	d.prompt:ClearAllPoints()
	d.prompt:SetPoint("TOP", d, "TOP", 0, -S(18 + bar))
	d.prompt:SetWidth(S(280))
	d.edit:SetSize(S(250), S(20))
	-- The copy glyph belongs to ShowCopyBox alone; every show starts without it and with the template's
	-- own zero insets (InputBoxTemplate declares none, SecureUIPanelTemplates.xml:42-69).
	if d.copyIcon then d.copyIcon:Hide() end
	if d.edit.SetTextInsets then d.edit:SetTextInsets(0, 0, 0, 0) end
	d.edit:ClearAllPoints()
	d.edit:SetPoint("TOP", d.prompt, "BOTTOM", 0, -S(12))
	d.ok:SetSize(S(96), S(22))
	d.ok:ClearAllPoints()
	d.ok:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -S(6), S(14))
	d.cancel:SetSize(S(96), S(22))
	d.cancel:ClearAllPoints()
	d.cancel:SetPoint("BOTTOMLEFT", d, "BOTTOM", S(6), S(14))
end

local DIALOG_NAME = "LibAceGUIWidgets_Dialog"

local function inCombat() return (InCombatLockdown and InCombatLockdown()) and true or false end

-- Ends ONE show: runs its onHide exactly once and drops the state that belonged to it. The hook is
-- taken and the fields cleared BEFORE the call, so a hook that re-shows or hides the dialog again
-- cannot fire it twice, and a second finish for the same show is a no-op.
local function finishDialog(d)
	local hook = d._onHide
	d._onHide, d._accept, d._token, d._copyText = nil, nil, nil, nil
	-- Leave the Escape layer this show joined (ShowDialog), so the next show -- maybe another addon's,
	-- under another window -- is not closed by this window. The name is NOT put back on UISpecialFrames
	-- here: this runs inside the client's Escape walk when Escape closed the prompt, and appending to the
	-- list mid-walk is undefined (see RemoveEscapeChild). A hidden dialog needs no entry; the next
	-- ShowDialog re-lists it when it finds no layer to join (Peer Review e2a2b784).
	local joined = d._lagwEscapeJoined
	if joined then
		d._lagwEscapeJoined = nil
		leaveEscapeLayer(joined, d, false)
	end
	d:SetScript("OnKeyDown", nil)
	if d.EnableKeyboard and not inCombat() then d:EnableKeyboard(false) end
	-- Through safeCall: accept() hides first, so a raising onHide used to skip the consumer's onAccept.
	if hook then safeCall(hook, d) end
end

-- THE ONLY WAY THE LIBRARY CLOSES THE DIALOG. `d:Hide()` alone is not enough, because OnHide fires on
-- a change of EFFECTIVE visibility, not of the frame's own flag: a dialog parented into a window that
-- is currently hidden is already invisible, so hiding it dispatches nothing and the consumer's onHide
-- -- their PopModal -- would never run. Finishing here covers that case; the OnHide script covers the
-- closes that do not come through this function (Escape through UISpecialFrames, or a consumer hiding
-- the named global by hand), and whichever runs second finds the hook already taken.
local function hideDialog(d)
	local wasOpen = d.IsShown and d:IsShown()
	d:Hide()
	if wasOpen then finishDialog(d) end
end

-- Enter accepts, Escape cancels, everything else is passed on. The propagation flag is set per key
-- because it decides what happens to THIS key: Enter and Escape are consumed (or Enter would also open
-- chat and Escape the game menu), every other key goes on to the game. In combat the flag cannot be
-- touched, so it is left as it was set at show time (on) and the dialog still acts on Enter/Escape.
local function Dialog_OnKeyDown(d, key)
	local consume = key == "ENTER" or key == "ESCAPE"
	if not inCombat() and d.SetPropagateKeyboardInput then d:SetPropagateKeyboardInput(not consume) end
	if key == "ENTER" then
		if d._accept then d._accept() end
	elseif key == "ESCAPE" then
		hideDialog(d)
	end
end

-- Monotonic, never reset: a token identifies ONE prompt for the life of the session, so a token a
-- consumer kept can never come to mean a later prompt. Cleared on close as well, so `CloseDialog` on
-- an already-closed prompt is a no-op rather than closing whatever is showing now.
local dialogToken = 0

-- A PARENT HIDING IS NOT A CLOSE. OnHide runs on a frame when its own flag clears AND when any
-- ancestor hides, because an ancestor's hide cascades to every descendant it makes invisible. Only
-- the first is this prompt ending: for the second the dialog's own flag is still set and the prompt
-- comes back the instant the parent shows again. `IsShown` is the frame's own flag (false inside its
-- own hide, true under a hidden ancestor); `IsVisible` is that flag and every ancestor's -- so this
-- test tells the two apart exactly. Clearing the show's state on a cascaded hide used to leave a
-- visibly-open confirm with a dead Enter key, a token `CloseDialog` no longer matched, and -- the one
-- that costs a consumer -- an onHide that never ran on the real close, so a PushModal paired in
-- onShow was left one push up. Reported by Dibs, 2026-09-21.
local function Dialog_OnHide(d)
	if d.IsShown and d:IsShown() then return end
	finishDialog(d)
end

-- The looks ShowDialog can draw (MINOR 42, ClassicCalendar inbox 82cae97e). Feature-detect a style with
-- `if W.DIALOG_STYLES and W.DIALOG_STYLES.window then`.
--   plain   the UI-DialogBox backdrop, as every ShowDialog before MINOR 42
--   window  Blizzard's BasicFrameTemplateWithInset -- title bar with `opts.title`, close X, inset -- the
--           look of a consumer window built from that template
lib.DIALOG_STYLES = { plain = true, window = true }

-- Every dialog frame built so far, one per style. The ONE list ShowDialog and CloseDialog both walk, so a
-- third style is added here and nowhere else.
local function dialogFrames(self)
	local list = {}
	if self._dialog then list[#list + 1] = self._dialog end
	if self._windowDialog then list[#list + 1] = self._windowDialog end
	return list
end

-- Build one dialog frame. ONE FRAME PER STYLE, each kept for the session (`_dialog` plain,
-- `_windowDialog` window): a frame cannot change template once built, and restyling one shared frame
-- per show would leak into the next addon's prompt. Both carry the same children and scripts, so
-- everything below this -- tokens, onHide once, Enter/Escape, the copy box -- treats them alike.
local function buildDialog(self, parent, style)
	local window = style == "window"
	-- Named so it can be in UISpecialFrames. A MINOR upgrade builds a fresh frame under the same
	-- name, which rebinds the global to the new frame; the list entry is a name and is added once.
	local name = window and (DIALOG_NAME .. "Window") or DIALOG_NAME
	local template = window and "BasicFrameTemplateWithInset" or (BackdropTemplateMixin and "BackdropTemplate" or nil)
	local d = CreateFrame("Frame", name, parent, template)
	d._lagwStyle = style
	d:SetPoint("CENTER", parent, "CENTER", 0, 30)
	d:EnableMouse(true)
	if window then
		-- The X is Cancel: hideDialog, so onHide runs once like every other close. The template's own
		-- UIPanelCloseButton script would hide the parent panel and skip that path for a dialog under a
		-- hidden parent.
		if d.CloseButton then d.CloseButton:SetScript("OnClick", function() hideDialog(d) end) end
	else
		d:SetBackdrop({
			bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			edgeSize = 20, insets = { left = 6, right = 6, top = 6, bottom = 6 },
		})
	end
	local prompt = d:CreateFontString(nil, "OVERLAY")
	prompt:SetFontObject(self:ScaledFont("GameFontHighlight"))
	d.prompt = prompt
	local eb = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
	lib:_trackFocus(eb)
	eb:SetAutoFocus(false)
	if eb.SetFontObject then eb:SetFontObject(self:ScaledFont("ChatFontNormal")) end
	d.edit = eb
	local ok = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	scaleButtonFonts(self, ok)
	d.ok = ok
	local cancel = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	scaleButtonFonts(self, cancel)
	cancel:SetScript("OnClick", function() hideDialog(d) end)
	d.cancel = cancel
	eb:SetScript("OnEscapePressed", function() hideDialog(d) end)
	d:SetScript("OnHide", Dialog_OnHide)
	self:RegisterSpecialFrame(name)
	return d
end

function lib:ShowDialog(parent, opts)
	opts = opts or {}
	local window = opts.style == "window"
	-- A dialog already open, in EITHER style, is being replaced: close it properly first, so its
	-- consumer's onHide runs (their PopModal) before this consumer's onShow (their PushModal).
	for _, open in ipairs(dialogFrames(self)) do
		if open:IsShown() then hideDialog(open) end
	end
	local d
	if window then
		d = self._windowDialog
		if not d then d = buildDialog(self, parent, "window"); self._windowDialog = d end
	else
		d = self._dialog
		if not d then d = buildDialog(self, parent, "plain"); self._dialog = d end
	end
	layoutDialog(self, d)
	if window and d.TitleText then d.TitleText:SetText(opts.title or "") end
	-- Every show starts writable. ShowCopyBox sets this AFTER its ShowDialog returns; a plain prompt on the
	-- same shared frame must never inherit the read-only guard from a copy box before it.
	d._copyText = nil

	d:SetParent(parent)
	d:ClearAllPoints()
	d:SetPoint("CENTER", parent, "CENTER", 0, 30)
	d:SetFrameStrata(parent:GetFrameStrata() or "FULLSCREEN_DIALOG")
	d:SetFrameLevel((parent:GetFrameLevel() or 0) + 50)
	-- A prompt inside a window with an Escape layer joins that layer for THIS show (Peer Review
	-- e2a2b784). Left on UISpecialFrames, one Escape hides the dialog AND the layer's proxy in the same
	-- pass, and the proxy, finding no child up, closes the window too. That is the in-combat case: out of
	-- combat the dialog's own key handler or focused box takes Escape first. Only a join made HERE is
	-- undone by finishDialog; a consumer that added the dialog to its layer itself keeps it. With no layer
	-- above it, the dialog's name goes back on UISpecialFrames HERE -- finishDialog leaves it off -- and this
	-- runs from a click or a show, never from inside the client's Escape walk. The walk also stops at a
	-- frame that is a CHILD of a layer and joins its owner's layer (Peer Review ace03ea9): a floating
	-- panel or form dialog is parented to UIParent, so walking GetParent from it never reaches the window,
	-- and one Escape in combat would hide the prompt and the proxy together and the proxy would then take
	-- the panel, and what was typed in it, with it.
	local layered, f = false, parent
	while f do
		local layer = rawget(f, "_lagwEscape")
		local owners = rawget(f, "_lagwEscapeOwners")
		if not layer and owners then
			-- The newest SHOWN owner whose layer still holds this child. A hidden owner's proxy is hidden
			-- and takes no press, so joining it would leave the prompt on no Escape path at all (Peer Review
			-- on 4e6d3a5b); with no shown owner the walk carries on and the dialog is listed as before.
			for i = #owners, 1, -1 do
				local o = owners[i]
				local ol = rawget(o, "_lagwEscape")
				if ol and ol.has[f] and o:IsShown() then f, layer = o, ol break end
			end
		end
		if layer then
			layered = true
			if not layer.has[d] then
				self:EscapeLayer(f, { d })
				d._lagwEscapeJoined = f
			end
			break
		end
		f = f.GetParent and f:GetParent() or nil
	end
	if not layered then self:RegisterSpecialFrame(d:GetName()) end
	d.prompt:SetText(opts.prompt or "")
	d.ok:SetText(opts.okText or (_G.OKAY or "Okay"))
	if opts.cancelText == false then
		-- One button: an info or copy popup. OK moves to the centre; layoutDialog put it left of centre
		-- and puts it back on the next two-button show.
		d.cancel:Hide()
		d.ok:ClearAllPoints()
		d.ok:SetPoint("BOTTOM", d, "BOTTOM", 0, self:ScaledSize(14))
	else
		d.cancel:SetText(opts.cancelText or (_G.CANCEL or "Cancel"))
		d.cancel:Show()
	end

	-- Read the edit BEFORE hiding: `d:Hide()` runs onHide, and a hook may reuse the dialog.
	local function accept()
		local val = d.edit:IsShown() and d.edit:GetText() or nil
		hideDialog(d)
		if opts.onAccept then safeCall(opts.onAccept, val) end
	end
	d._accept = accept
	d._onHide = opts.onHide
	d.ok:SetScript("OnClick", accept)
	d:SetScript("OnKeyDown", nil)
	if opts.hasEdit ~= false then
		d.edit:Show()
		d.edit:SetText(opts.default or "")
		d.edit:SetScript("OnEnterPressed", accept)
		d.edit:SetFocus()
		d.edit:HighlightText()
	else
		d.edit:Hide()
		if not inCombat() then
			if d.EnableKeyboard then d:EnableKeyboard(true) end
			if d.SetPropagateKeyboardInput then d:SetPropagateKeyboardInput(true) end
			d:SetScript("OnKeyDown", Dialog_OnKeyDown)
		end
	end
	dialogToken = dialogToken + 1
	d._token = dialogToken
	d:Show()
	d:Raise()
	-- Protected, so a raising onShow cannot cost the caller the token it needs for CloseDialog.
	if opts.onShow then safeCall(opts.onShow, d) end
	return d, dialogToken
end

-- Close a prompt THIS caller opened, and nothing else. Returns whether it actually closed one.
--
-- The dialog is ONE frame shared by every addon in the session, so a consumer that wants to dismiss
-- its own prompt (ClassicCalendar's delete confirm, when the calendar's month steps) cannot call
-- `dialog:Hide()`: by then the frame may be showing somebody else's question, and hiding it would run
-- THEIR onHide -- an unbalanced PopModal, or a confirm that silently answers itself. The token that
-- `ShowDialog` returns as its SECOND value identifies one prompt; a stale one matches nothing.
--
--   local dialog, token = W:ShowDialog(parent, { ... })
--   ...
--   W:CloseDialog(token)   -- a no-op unless that exact prompt is still up
--
-- Feature-detect with `if W.CloseDialog then`. (MINOR 30, after ClassicCalendar reported having to
-- hand-roll this guard on their own side to adopt `ShowDialog` safely.)
function lib:CloseDialog(token)
	if token == nil then return false end
	-- Either style's frame may hold the prompt (MINOR 42); a token matches at most one of them.
	for _, d in ipairs(dialogFrames(self)) do
		if d._token == token and d:IsShown() then
			hideDialog(d)
			return true
		end
	end
	return false
end

-- A "copy this text" popup (MINOR 38, TOGTools inbox 737274f2). Addons cannot write the clipboard, so every
-- one hand-rolled the same thing: a popup whose edit box holds the text, selected, for Ctrl+C. This is
-- ShowDialog with that recipe applied, plus the part a hand-rolled copy missed -- the box is READ-ONLY, so a
-- stray key cannot destroy the text before it is copied.
--   W:ShowCopyBox(text, opts) -> dialog, token        (W:CloseDialog(token) closes it)
-- opts, all optional:
--   parent            default UIParent
--   prompt            default "Press Ctrl+C to copy, then Escape."
--   okText            the one button's caption; default CLOSE, else "Close"
--   onShow, onHide    passed to ShowDialog unchanged
--   style, title      passed to ShowDialog unchanged (MINOR 42; `style = "window"` for the window look)
-- One button, and it closes. Enter and Escape close as well. Nothing is called with the text on any close.
-- It is ShowDialog's shared frame for that style, so its rules hold: onHide once, a parent hide is not a close.
-- Long text scrolls inside the single-line box; the dialog keeps ShowDialog's size.
--
-- Read-only is a guard, not a flag the client has: a user edit (OnTextChanged with userInput true) is put
-- back and selected again, and a click in the box re-selects on mouse up, so the text is never left partly
-- selected. The template already selects all on focus (InputBoxScriptTemplate's OnEditFocusGained,
-- Blizzard_SharedXML/SecureUIPanelTemplates.xml:8). The guard reads `d._copyText`, which ShowDialog clears
-- on every show and finishDialog clears on every close -- so the hooks, installed once on the shared box, do
-- nothing for an ordinary prompt.
local function CopyBox_OnTextChanged(eb, userInput)
	local d = eb:GetParent()
	local text = d and d._copyText
	if not text or not userInput then return end
	if eb:GetText() ~= text then eb:SetText(text) end
	eb:HighlightText()
end

local function CopyBox_Reselect(eb)
	local d = eb:GetParent()
	if d and d._copyText then eb:HighlightText() end
end

-- The in-box copy glyph, drawn exactly as SearchBoxTemplate draws its magnifying glass and as the
-- DatePicker draws its calendar (LibAceGUIWidgets-DatePicker.lua:241-260): the field's LEFT +1,-1 on the
-- OVERLAY layer, 14px at scale 1, the text inset 20 to clear it, and the magnifier's tint rule
-- (InputBoxTemplates.lua:20-43) -- white while focused or holding text, 0.6 grey otherwise.
-- `Textures/copy.tga` is a 64x64 32-bit TGA of white line art (two overlapping rounded sheets, the
-- universal copy symbol) with an alpha channel, the same format as `calendar.tga`. `SetTexture` returns
-- success (SimpleTextureBaseAPIDocumentation.lua:429); a miss draws no glyph and no inset rather than a
-- blank square.
local COPY_ICON = "Interface\\AddOns\\RCLootCouncil_dibs\\libs\\LibAceGUIWidgets\\Textures\\copy.tga"
local COPY_GLYPH, COPY_INSET = 14, 20
lib.COPY_ICON = COPY_ICON

local function CopyBox_Tint(eb)
	local d = eb:GetParent()
	local icon = d and d.copyIcon
	if not (icon and icon:IsShown()) then return end
	local v = (eb:HasFocus() or (eb:GetText() or "") ~= "") and 1.0 or 0.6
	icon:SetVertexColor(v, v, v)
end

local function CopyBox_ShowGlyph(self, d)
	local eb = d.edit
	if d.copyIcon == nil then
		local icon = eb:CreateTexture(nil, "OVERLAY")
		icon:SetPoint("LEFT", eb, "LEFT", 1, -1)
		local ok = icon:SetTexture(COPY_ICON)
		d.copyIcon = (ok and icon:GetTexture()) and icon or false
		if not d.copyIcon then icon:Hide() end
	end
	if not d.copyIcon then return end
	d.copyIcon:SetSize(self:ScaledSize(COPY_GLYPH), self:ScaledSize(COPY_GLYPH))
	d.copyIcon:Show()
	if eb.SetTextInsets then eb:SetTextInsets(self:ScaledSize(COPY_INSET), 0, 0, 0) end
	CopyBox_Tint(eb)
end

function lib:ShowCopyBox(text, opts)
	opts = opts or {}
	if text == nil then text = "" end
	text = tostring(text)
	local d, token = self:ShowDialog(opts.parent or UIParent, {
		prompt     = opts.prompt or "Press Ctrl+C to copy, then Escape.",
		default    = text,
		okText     = opts.okText or _G.CLOSE or "Close",
		cancelText = false,
		onShow     = opts.onShow,
		onHide     = opts.onHide,
		style      = opts.style,   -- MINOR 42, as ShowDialog
		title      = opts.title,
	})
	local eb = d.edit
	-- Once per box, not per show: HookScript adds, and a hook per show would pile up for the session. The
	-- flag is on the box, so a dialog frame an older library copy built gets the hooks on its first copy.
	if not eb._lagwCopyHooked then
		eb._lagwCopyHooked = true
		eb:HookScript("OnTextChanged", CopyBox_OnTextChanged)
		eb:HookScript("OnMouseUp", CopyBox_Reselect)
		eb:HookScript("OnEditFocusGained", CopyBox_Reselect)
		eb:HookScript("OnEditFocusGained", CopyBox_Tint)
		eb:HookScript("OnEditFocusLost", CopyBox_Tint)
	end
	d._copyText = text
	CopyBox_ShowGlyph(self, d)
	return d, token
end

-- A TSM-style search box (Blizzard SearchBoxTemplate: magnifier icon, "Search" placeholder, clear-X)
-- as a raw frame that drops into a manual layout. opts:
--   width, height        size (default 160 x 20)
--   placeholder          the greyed instruction text (default the template's "Search")
--   onChanged(text)      called on every edit (incl. the clear button) with the current text
--   tipTitle, tipBody    optional AttachTooltip
-- Returns the EditBox. Read the query with box:GetText().
--
-- `width`/`height` are scale-1.0 sizes and follow the scale (MINOR 29); so do the field's font,
-- the placeholder's, the magnifier, the clear button and the text insets that make room for them --
-- the template's own numbers (10px glyph, 17px button, 16/20 insets) read from
-- `Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml`, multiplied.
local function SearchBox_OnScaleChanged(_, _, rec)
	local eb = rec.eb
	local S = function(px) return lib:ScaledSize(px) end
	eb:SetTextInsets(S(16), S(20), 0, 0)
	if eb.searchIcon then eb.searchIcon:SetSize(S(10), S(10)) end
	local clear = eb.clearButton
	if clear then
		clear:SetSize(S(17), S(17))
		if clear.Icon then clear.Icon:SetSize(S(10), S(10)) end
	end
end

function lib:CreateSearchBox(parent, opts)
	opts = opts or {}
	local eb = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
	lib:_trackFocus(eb)
	self:SetScaledSize(eb, opts.width or 160, opts.height or 20)
	eb:SetAutoFocus(false)
	if eb.SetFontObject then eb:SetFontObject(self:ScaledFont("ChatFontNormal")) end
	if eb.Instructions and eb.Instructions.SetFontObject then
		eb.Instructions:SetFontObject(self:ScaledFont("GameFontDisableSmall"))
	end
	if eb.SetTextInsets then
		-- The record, not the box, is the listener's owner (see SetScaledSize): a consumer's own
		-- OnScaleChanged(eb, ...) must not be displaced by the library's.
		local rec = { eb = eb }
		eb._lagwSearchScale = rec
		SearchBox_OnScaleChanged(nil, nil, rec)
		self:OnScaleChanged(rec, SearchBox_OnScaleChanged)
	end
	if opts.placeholder and eb.Instructions then eb.Instructions:SetText(opts.placeholder) end
	-- Hook (don't replace) so the template's own OnTextChanged still runs the clear-button / placeholder.
	eb:HookScript("OnTextChanged", function(e)
		if opts.onChanged then safeCall(opts.onChanged, e:GetText()) end
	end)
	if opts.tipTitle then lib:AttachTooltip(eb, opts.tipTitle, opts.tipBody) end
	return eb
end

-- ---------------------------------------------------------------------------
-- Form dialog -- the small officer prompt: labelled fields, an error line, OK/Cancel (MINOR 33)
-- ---------------------------------------------------------------------------
-- Requested by Dibs (DIBSREQ-LAGW-009), who had TWO hand-rolled copies of it in one file -- the same
-- backdrop block, the same title placement, the same local `field()` / `row()` builder written twice,
-- the same red wrapped error line, the same 22px buttons at BOTTOMRIGHT. Their peer review named it
-- as the two-copies class and asked for this rather than a third copy when the next officer form
-- arrives.
--
--   local f = W:CreateFormDialog({
--       name  = "MyAddon_AdjustDialog",       -- global name: Escape list, and what a spec looks up
--       title = "Adjust DKP", hint = "A negative amount deducts.",
--       rows  = {
--           { label = "Character" },
--           { label = "Amount", numeric = true },            -- narrow; still accepts "-50"
--           { label = "Decay %", numeric = true, digitsOnly = true,
--             button = { text = "Apply", onClick = function(f) ... end },
--             tipTitle = "Decay", tipBody = "Reduces every standing." },
--       },
--       okText = "Record", onAccept = function(f) ... end,
--   })
--
-- Returns the frame: `.fields[i]` (the EditBoxes, by row), `.buttons[i]` (a row's own button, by row),
-- `.labels[i]` (each row's label FontString, by row; `f:SetLabel(i, text)` replaces it), `.err`, `.ok`,
-- `.cancel`, `.title`, `.hint`.
--
-- ONE FRAME PER `name`, built once and handed back on every later call, because these dialogs are
-- module-scope singletons on the consumer side and a second frame under one global name would leave
-- the first orphaned on screen.
--
-- OK DOES NOT HIDE, and that is the point of `.err` existing. A caller validates in `onAccept`, and a
-- refusal has to leave the dialog open with the reason in the error line -- a factory that closed on
-- OK would throw away what the player typed every time they got it wrong. Cancel always hides.
--
-- ENTER IS THE CALLER'S. No `OnEnterPressed` is installed, because a consumer confirms through
-- `ShowDialog` before writing and an Enter that accepted would skip that. ESCAPE in any field hides
-- the dialog, and the frame is on the Escape list when it is named.
--
-- `numeric` is the WIDTH (a narrow field); `digitsOnly` is `SetNumeric(true)`. They are separate
-- because the field that made this contract -- a DKP adjustment -- is narrow AND must accept a typed
-- minus sign, which `SetNumeric` refuses outright.
-- One table, not thirteen locals: the main chunk is at Lua 5.1's 200-local limit (Tests/localheadroom_spec.lua).
local FORM = {
	PAD       = 14,
	ROW_H     = 26,
	ROW_GAP   = 6,
	BTN_W     = 90,
	BTN_H     = 22,
	FIELD_W   = 140,
	NUMERIC_W = 70,
	ERR_H     = 28,
	TITLE_H   = 16,
	HINT_H    = 16,
	NOTE_H    = 12,
	NOTE_GAP  = 2,
	CHECK_SZ  = 24,
}

local function FormField_OnEscape(box)
	box:ClearFocus()
	local dialog = box._lagwFormDialog
	if dialog then dialog:Hide() end
end

-- MINOR 36 (TOGProfessionMaster inbox 6cf3b4e4): four additions, all opt-in, for their [Bank] request
-- dialog -- an item row, a banker picker, a shop-price line that exists only sometimes, and a dialog that
-- opens beside the row it came from.

--- `f:SetHint(text or nil)`: show, change or remove the hint line after the dialog is built, re-flowing
--- the first row under it and the dialog's height, so an optional line leaves no gap when it goes. The
--- OK/Cancel pair is anchored to the bottom and moves with it.
local function FormDialog_SetHint(f, text)
	if text == nil or text == "" then
		if f.hint then f.hint:Hide() end
	else
		if not f.hint then
			local hint = f:CreateFontString(nil, "OVERLAY")
			hint:SetFontObject(lib:ScaledFont("GameFontDisableSmall"))
			hint:SetPoint("TOPLEFT",  f.title, "BOTTOMLEFT",  0, -4)
			hint:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -4)
			hint:SetJustifyH("LEFT")
			hint:SetWordWrap(true)
			f.hint = hint
		end
		f.hint:SetText(text)
		f.hint:Show()
	end
	f._lagwFormReflow()
end

-- The height a row's note takes, in scale-1.0 units: nothing when it is hidden or absent, else the wrapped
-- text's measured height (never under one line) plus the gap above it.
local function FormNote_Height(note)
	if not (note and note:IsShown()) then return 0 end
	local h = (note:GetStringHeight() or 0) / lib:GetScale()
	return math.max(FORM.NOTE_H, h) + FORM.NOTE_GAP
end

--- `f:SetNote(i, text or nil)` (MINOR 37, Dibs inbox 8d5165f7): add, change or remove the small grey line
--- under row i's field, re-flowing every row below it and the dialog's height, as SetHint does. nil or ""
--- removes it and leaves no gap. An index with no row does nothing.
local function FormDialog_SetNote(f, i, text)
	local holder = f._rowHolders and f._rowHolders[i]
	if not holder then return end
	local note = f.notes[i]
	if text == nil or text == "" then
		if note then note:Hide() end
	else
		if not note then
			note = f:CreateFontString(nil, "OVERLAY")
			note:SetFontObject(lib:ScaledFont("GameFontDisableSmall"))
			note:SetPoint("TOPLEFT", f.fields[i], "BOTTOMLEFT", 0, -FORM.NOTE_GAP)
			note:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
			note:SetJustifyH("LEFT")
			note:SetWordWrap(true)
			f.notes[i] = note
		end
		note:SetText(text)
		note:Show()
	end
	f._lagwFormReflow()
end

--- `f:SetBody(text or nil)` (MINOR 37, Dibs inbox 33a2bbce): a paragraph under the title (and hint),
--- above the rows, wrapped to the dialog's width. Set it again at any time -- after Show included -- and
--- the text is replaced and the dialog's height follows it. nil or "" hides it and it takes no space.
--- `opts.body` sets it at build. The FontString is `f.body`, on the scaled font like the rest of the
--- dialog.
local function FormDialog_SetBody(f, text)
	if text == nil or text == "" then
		if f.body then f.body:Hide() end
	else
		if not f.body then
			local body = f:CreateFontString(nil, "OVERLAY")
			body:SetFontObject(lib:ScaledFont("GameFontHighlightSmall"))
			body:SetJustifyH("LEFT")
			body:SetJustifyV("TOP")
			body:SetWordWrap(true)
			f.body = body
		end
		f.body:SetText(text)
		f.body:Show()
	end
	f._lagwFormReflow()
end

--- `f:SetLabel(i, text or nil)` (Ultimate Guild Roster inbox 1a2fe53f): replace row i's label after the
--- dialog is built -- one named dialog reused for several prompts names its rows per open. nil or "" clears
--- it to an empty label. A `kind = "check"` row's label is the text to the box's right, so this renames the
--- checkbox. An index with no row is a silent no-op, as SetNote's is. The FontString is `f.labels[i]`.
--- Nothing re-flows: a row's height is fixed, and every field is anchored to its holder's right edge (an
--- item row to the label's right edge, which follows the new text by itself).
local function FormDialog_SetLabel(f, i, text)
	local label = f.labels and f.labels[i]
	if not label then return end
	label:SetText(text or "")
end

-- The body's height in scale-1.0 units, with the gap above it; 0 when hidden or absent.
local function FormBody_Height(body)
	if not (body and body:IsShown()) then return 0 end
	return 4 + math.max(FORM.HINT_H, (body:GetStringHeight() or 0) / lib:GetScale())
end

--- A `kind = "check"` row (MINOR 37, Dibs inbox 8d5165f7): a UICheckButton with the row's label to its
--- right, wrapping, in place of the edit box. `fields[i]` is the CheckButton, with `GetValue()` -> boolean
--- and a silent `SetValue(bool)`; `row.value` sets the start, `row.onChanged(value, dialog)` hears a click,
--- and `row.tipTitle` / `row.tipBody` go on the box through AttachTooltip.
function lib:_formCheckRow(f, holder, row, label)
	local cb = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
	self:SetScaledSize(cb, FORM.CHECK_SZ, FORM.CHECK_SZ)
	cb:SetPoint("LEFT", holder, "LEFT", 0, 0)
	label:ClearAllPoints()
	label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	label:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
	label:SetWordWrap(true)
	function cb:GetValue() return self:GetChecked() and true or false end
	function cb:SetValue(v) self:SetChecked(v and true or false) end
	cb:SetValue(row.value)
	cb:SetScript("OnClick", function(self_)
		if row.onChanged then safeCall(row.onChanged, self_:GetValue(), f) end
	end)
	if row.tipTitle or row.tipBody then self:AttachTooltip(cb, row.tipTitle, row.tipBody) end
	cb._lagwFormDialog = f
	return cb
end

-- Put the dialog beside its owner, if it has one that is on screen. Run on every show.
local function FormDialog_Place(f)
	local a = f._lagwAnchor
	local owner = a and a[1]
	if not (owner and owner.IsVisible and owner:IsVisible()) then return end
	f:ClearAllPoints()
	f:SetPoint(a[2], owner, a[3], a[4], a[5])
end

--- `f:SetAnchor(owner[, point, relPoint, x, y])`: open beside `owner` every time the dialog is shown
--- (default: its TOPLEFT to the owner's TOPRIGHT, 4px right), clamped to the screen by the floating
--- frame. A later call re-points it, which is how one named dialog follows whichever row opened it;
--- nil stops it. An owner that is not visible at show time leaves the dialog where it last was.
local function FormDialog_SetAnchor(f, owner, point, relPoint, x, y)
	if owner == nil then
		f._lagwAnchor = nil
		return
	end
	f._lagwAnchor = { owner, point or "TOPLEFT", relPoint or "TOPRIGHT", x or 4, y or 0 }
	if f:IsShown() then FormDialog_Place(f) end
end

--- A `kind = "dropdown"` row: a CreateDropdownBox where the edit box would be. `row.items(query)` returns
--- `{ { text, value }, ... }` (value defaults to text), built fresh per open; choosing one shows it and
--- calls `row.onChanged(value, dialog)` when it changed. The box is `fields[i]`, with `GetValue()` and a
--- silent `SetValue(value[, text])`. `row.value` / `row.valueText` set the start, `row.search` a filter.
function lib:_formDropdownRow(f, holder, row)
	local box
	box = self:CreateDropdownBox(holder, {
		width = row.width or FORM.FIELD_W, height = 20, search = row.search, menuWidth = row.menuWidth,
		items = function(query)
			local out, list = {}, nil
			if row.items then
				local ok, v = safeCall(row.items, query or "")
				list = ok and v or nil
			end
			for _, it in ipairs(list or {}) do
				local value = it.value
				if value == nil then value = it.text end
				out[#out + 1] = { text = it.text, checked = value == box._value, onClick = function()
					local changed = value ~= box._value
					box:SetValue(value, it.text)
					if changed and row.onChanged then safeCall(row.onChanged, value, f) end
				end }
			end
			return out
		end,
	})
	box:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
	function box:SetValue(v, text)
		self._value = v
		self.label:SetText(text or (v ~= nil and tostring(v)) or "")
	end
	function box:GetValue() return self._value end
	box:SetValue(row.value, row.valueText)
	return box
end

--- A `kind = "item"` row: the item's icon and link from the label to the right edge. Hover shows the
--- item's own tooltip; a click goes to the client's HandleModifiedItemClick (shift-click links it to chat,
--- ctrl-click dresses up). `row.link` and `row.icon` set it; `fields[i]:SetItem(link[, icon])` changes
--- it, and `GetValue()` returns the link. The icon is `row.icon`, else C_Item.GetItemIconByID(link),
--- which the Classic Era, Anniversary and Classic docs all declare (ItemDocumentation.lua:378).
--- `row.onEnter(button, link)`, `row.onLeave(button)` and `row.onClick(button, link, mouseButton)`
--- each replace the built-in hover, leave or click when given (MINOR 39).
local ITEM_ROW_ICON = 18
-- luacheck: read globals C_Item HandleModifiedItemClick

function lib:_formItemRow(f, holder, row, label)
	local b = CreateFrame("Button", nil, holder)
	b:SetPoint("LEFT", label, "RIGHT", 6, 0)
	b:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
	self:SetScaledSize(b, nil, 20)
	local icon = b:CreateTexture(nil, "ARTWORK")
	self:SetScaledSize(icon, ITEM_ROW_ICON, ITEM_ROW_ICON)
	icon:SetPoint("LEFT", b, "LEFT", 0, 0)
	b.icon = icon
	local fs = b:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(self:ScaledFont("GameFontHighlight"))
	fs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	fs:SetPoint("RIGHT", b, "RIGHT", 0, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	b.text = fs
	b._lagwFormDialog = f

	function b:SetItem(link, tex)
		self._link = link
		self.text:SetText(link or "")
		if tex == nil and link and C_Item and C_Item.GetItemIconByID then tex = C_Item.GetItemIconByID(link) end
		self.icon:SetTexture(tex)
		self.icon:SetShown(tex ~= nil)
	end
	function b:GetValue() return self._link end

	-- CONSUMER HOVER AND CLICK (MINOR 39, TOGProfessionMaster contract 1d7a76ba): `row.onEnter(button,
	-- link)`, `row.onLeave(button)` and `row.onClick(button, link, mouseButton)` each REPLACE the built-in
	-- behaviour when given, so a consumer with its own item hover (hold-to-compare) or click (a rebound
	-- chat-link modifier) keeps it. Read from the row spec at EVENT time, not captured here, so a named
	-- dialog reused across opens follows whatever the spec holds now. None given: exactly the old path.
	b._lagwRow = row
	b:SetScript("OnEnter", function(self_)
		local link = self_._link
		if not link then return end
		local spec = self_._lagwRow
		if spec and spec.onEnter then safeCall(spec.onEnter, self_, link) return end
		lib:AnchorTooltip(self_)
		-- The bare "item:..." part: what SetHyperlink takes in every flavour, with or without the markup.
		GameTooltip:SetHyperlink(link:match("|H(.-)|h") or link)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self_)
		local spec = self_._lagwRow
		if spec and spec.onLeave then safeCall(spec.onLeave, self_) return end
		lib:HideTooltip(self_)
	end)
	b:SetScript("OnClick", function(self_, mouseButton)
		local spec = self_._lagwRow
		if spec and spec.onClick then
			if self_._link then safeCall(spec.onClick, self_, self_._link, mouseButton) end
			return
		end
		if self_._link and HandleModifiedItemClick then HandleModifiedItemClick(self_._link) end
	end)
	b:SetItem(row.link, row.icon)
	return b
end

function lib:CreateFormDialog(opts)
	opts = opts or {}
	local cache = self._formDialogs
	if not cache then cache = {}; self._formDialogs = cache end
	if opts.name and cache[opts.name] then return cache[opts.name] end

	local S = function(px) return self:ScaledSize(px) end
	local rows = opts.rows or {}

	-- The shared floating panel: the library's backdrop, clamped to the screen, and -- when named --
	-- the client's Escape list. DIALOG strata rather than the panel default, so an officer form sits
	-- above a consumer's window without stealing the TOOLTIP layer a menu needs.
	local f = self:CreateFloatingFrame({
		name = opts.name, strata = opts.strata or "DIALOG", level = opts.level or 100,
	})
	f:Hide()
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop",  f.StopMovingOrSizing)

	-- Full width, so every later element chains from it by two corners and nothing has to know the
	-- dialog's width.
	local title = f:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(self:ScaledFont("GameFontNormal"))
	title:SetPoint("TOPLEFT",  f, "TOPLEFT",   FORM.PAD, -12)
	title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -FORM.PAD, -12)
	title:SetJustifyH("LEFT")
	title:SetText(opts.title or "")
	title:SetTextColor(self:AccentRGB())
	f.title = title

	local last = title ---@type table  -- the title FontString, then each row's holder Frame
	if opts.hint then
		local hint = f:CreateFontString(nil, "OVERLAY")
		hint:SetFontObject(self:ScaledFont("GameFontDisableSmall"))
		hint:SetPoint("TOPLEFT",  last, "BOTTOMLEFT",  0, -4)
		hint:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -4)
		hint:SetJustifyH("LEFT")
		hint:SetWordWrap(true)
		hint:SetText(opts.hint)
		f.hint = hint
		last = hint
	end

	f.fields, f.buttons = {}, {}
	f._rowHolders, f.notes, f.labels = {}, {}, {}
	for i = 1, #rows do
		local row = rows[i]
		local holder = CreateFrame("Frame", nil, f)
		holder:SetHeight(S(FORM.ROW_H))
		holder:SetPoint("TOPLEFT",  last, "BOTTOMLEFT",  0, -FORM.ROW_GAP)
		holder:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -FORM.ROW_GAP)
		f._rowHolders[i] = holder

		if i == 1 then f._firstRow = holder end

		local label = holder:CreateFontString(nil, "OVERLAY")
		label:SetFontObject(self:ScaledFont("GameFontNormalSmall"))
		label:SetPoint("LEFT", holder, "LEFT", 0, 0)
		label:SetJustifyH("LEFT")
		label:SetText(row.label or "")
		f.labels[i] = label

		-- A row's own button sits hard right; the field ends where it begins. `button` is a table, or
		-- a bare string as shorthand for its text.
		local btn
		local spec = row.button
		if type(spec) == "string" then spec = { text = spec } end
		if row.kind == "dropdown" then
			f.fields[i] = self:_formDropdownRow(f, holder, row)
		elseif row.kind == "item" then
			f.fields[i] = self:_formItemRow(f, holder, row, label)
		elseif row.kind == "check" then
			f.fields[i] = self:_formCheckRow(f, holder, row, label)
		elseif spec then
			btn = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
			self:SetScaledSize(btn, spec.width or FORM.BTN_W, FORM.BTN_H)
			btn:SetText(spec.text or "")
			btn:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
			if spec.onClick then btn:SetScript("OnClick", function() safeCall(spec.onClick, f) end) end
			if row.tipTitle or row.tipBody then self:AttachTooltip(btn, row.tipTitle, row.tipBody) end
			f.buttons[i] = btn
		end

		if not f.fields[i] then
			local eb = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
			lib:_trackFocus(eb)
			self:SetScaledSize(eb, row.width or (row.numeric and FORM.NUMERIC_W or FORM.FIELD_W), 20)
			eb:SetAutoFocus(false)
			if eb.SetFontObject then eb:SetFontObject(self:ScaledFont("ChatFontNormal")) end
			-- SetNumeric ONLY on demand: it refuses a typed minus sign, so the field a deduction is typed
			-- into must not have it however numeric the value is.
			if row.digitsOnly and eb.SetNumeric then eb:SetNumeric(true) end
			eb:SetPoint("RIGHT", btn or holder, btn and "LEFT" or "RIGHT", btn and -6 or 0, 0)
			eb._lagwFormDialog = f
			eb:SetScript("OnEscapePressed", FormField_OnEscape)
			f.fields[i] = eb
		end

		last = holder
	end

	-- Red, wrapped, and cleared by NOBODY but the caller: a validation message has to survive the
	-- repaint that follows the OK it refused.
	local err = f:CreateFontString(nil, "OVERLAY")
	err:SetFontObject(self:ScaledFont("GameFontRedSmall"))
	err:SetPoint("TOPLEFT",  last, "BOTTOMLEFT",  0, -FORM.ROW_GAP)
	err:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -FORM.ROW_GAP)
	err:SetJustifyH("LEFT")
	err:SetWordWrap(true)
	err:SetHeight(S(FORM.ERR_H))
	f.err = err
	f._firstRow = f._firstRow or err

	-- `cancelText == false` collapses the pair to the button that CLOSES, since that is the one a
	-- read-only form (a settings panel with per-row buttons) actually needs.
	local closeOnly = opts.cancelText == false
	local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	self:SetScaledSize(cancel, FORM.BTN_W, FORM.BTN_H)
	cancel:SetText(closeOnly and (opts.closeText or CLOSE or "Close")
		or (opts.cancelText or CANCEL or "Cancel"))
	cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -FORM.PAD, 12)
	cancel:SetScript("OnClick", function() f:Hide() end)
	f.cancel = cancel

	if not closeOnly then
		local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		self:SetScaledSize(ok, FORM.BTN_W, FORM.BTN_H)
		ok:SetText(opts.okText or OKAY or "Okay")
		ok:SetPoint("RIGHT", cancel, "LEFT", -6, 0)
		ok:SetScript("OnClick", function() if opts.onAccept then safeCall(opts.onAccept, f) end end)
		f.ok = ok
	end

	-- The height is a function of whether the hint shows, so SetHint (MINOR 36) can re-flow it. A caller's
	-- own `height` is theirs and is never re-flowed.
	f._lagwFormSize = function()
		local notes = 0
		for i = 1, #rows do notes = notes + FormNote_Height(f.notes[i]) end
		local height = 12 + FORM.TITLE_H
			+ ((f.hint and f.hint:IsShown()) and (4 + FORM.HINT_H) or 0)
			+ FormBody_Height(f.body)
			+ #rows * (FORM.ROW_GAP + FORM.ROW_H)
			+ notes
			+ FORM.ROW_GAP + FORM.ERR_H
			+ 6 + FORM.BTN_H + 12
		self:SetScaledSize(f, opts.width or 340, opts.height or height)
	end
	-- Re-hang every row (or, with none, the error line) under whatever shows above it: the hint or the
	-- title for the first, the previous row plus its note, if shown, for the rest. The points are the
	-- ones the build set, so a dialog with no note and no hint change lands exactly where it was built.
	f._lagwFormReflow = function()
		local above = (f.hint and f.hint:IsShown()) and f.hint or f.title
		if f.body and f.body:IsShown() then
			f.body:ClearAllPoints()
			f.body:SetPoint("TOPLEFT",  above, "BOTTOMLEFT",  0, -4)
			f.body:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -4)
			above = f.body
		end
		local extra = 0
		local chain = {}
		for i = 1, #rows do chain[i] = f._rowHolders[i] end
		chain[#chain + 1] = err
		for i, frame in ipairs(chain) do
			local off = -(FORM.ROW_GAP + extra)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT",  above, "BOTTOMLEFT",  0, off)
			frame:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, off)
			above = frame
			extra = S(FormNote_Height(f.notes[i]))
		end
		f._lagwFormSize()
	end
	f.SetHint = FormDialog_SetHint
	f.SetNote = FormDialog_SetNote
	f.SetBody = FormDialog_SetBody
	f.SetLabel = FormDialog_SetLabel
	local anyNote = opts.body ~= nil and opts.body ~= ""
	if anyNote then FormDialog_SetBody(f, opts.body) end
	for i = 1, #rows do
		if rows[i].note and rows[i].note ~= "" then
			FormDialog_SetNote(f, i, rows[i].note)
			anyNote = true
		end
	end
	if not anyNote then f._lagwFormSize() end
	f.SetAnchor = FormDialog_SetAnchor
	if opts.anchorTo then
		f:SetAnchor(opts.anchorTo, opts.point, opts.relPoint, opts.x, opts.y)
	end
	f:HookScript("OnShow", FormDialog_Place)

	if opts.name then cache[opts.name] = f end
	return f
end

-- Tokenised, case-insensitive substring search: true when EVERY whitespace-separated token of `query`
-- appears somewhere in the combined haystack strings (name, source, zone, stat names, …). An empty
-- query matches everything; nil haystack fields are skipped. Pure — the reusable "search any field".
function lib:SearchMatch(query, ...)
	if not query or query == "" then return true end
	local parts = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v ~= nil then parts[#parts + 1] = tostring(v) end
	end
	local hay = table.concat(parts, " "):lower()
	for tok in tostring(query):lower():gmatch("%S+") do
		if not hay:find(tok, 1, true) then return false end
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Named cooldowns — a rate-limited button that counts itself down (MINOR 24)
-- ---------------------------------------------------------------------------
-- Ported from FastGuildInvite's scan cooldown (`fn.startScanCooldown` in functions.lua, and the button
-- treatment in GUI/Tabs/Scan.lua's `ScanTab.SetCooldown`), which is the UX this reproduces: while the
-- cooldown runs, the button's caption becomes the seconds remaining, the text dims, the highlight is hidden
-- and the click is refused at the UI layer rather than fired and bounced somewhere deeper.
--
-- Two things are deliberately NOT copied from FGI:
--
--   • FGI's ticker DECREMENTS a counter, so the displayed number is only as accurate as the ticker firing;
--     a frame drop, a loading screen or a re-entrant start leaves it wrong or stuck. Here the deadline is
--     stamped once (`endsAt`) and every reader COMPUTES the remainder from the clock, so the ticker only
--     ever repaints. A missed tick shows a stale number for one second instead of permanently.
--   • FGI fans each tick to three named views by hand (`setCompactCooldown` / `setMainScanCooldown` /
--     `setLegacyCooldown`), which is why adding a fourth view meant editing the driver. A cooldown here is
--     keyed by NAME and carries a list of listeners, so a view registers itself and the driver never learns
--     about it.
--
-- The re-entrancy rule is FGI's and is kept: starting a named cooldown that is already running CANCELS the
-- in-flight ticker first, so two starts never leave two tickers decrementing one display.

lib.cooldowns = lib.cooldowns or {}

local function nowSeconds()
	return (GetTime and GetTime()) or 0
end

-- The one place a cooldown record is shaped; OnCooldownTick and StartCooldown both create on first use.
local function ensureCooldown(name)
	local cd = lib.cooldowns[name]
	if not cd then
		cd = { endsAt = 0, ticker = nil, listeners = {} }
		lib.cooldowns[name] = cd
	end
	return cd
end

-- Drop the `false` holes OffCooldownTick leaves behind. Only ever run outside a fan-out, so the index walk
-- in fanCooldown never sees the list shift under it.
local function compactListeners(cd)
	local kept = {}
	for i = 1, #cd.listeners do
		local fn = cd.listeners[i]
		if fn then kept[#kept + 1] = fn end
	end
	cd.listeners = kept
	cd.dirty = nil
end

-- Fire every listener with the seconds remaining (0 when it has expired). A listener removed mid-fan is
-- a `false` slot by the time the walk reaches it, so it is not called; the holes are swept afterwards.
-- A listener that errors is reported through safeCall, with its stack, and the walk goes on:
-- an escaping error would skip every later listener AND leave `fanning` above 0 for good, so the holes
-- would never be swept again.
local function fanCooldown(cd, remaining)
	cd.fanning = (cd.fanning or 0) + 1
	local list = cd.listeners
	for i = 1, #list do
		local fn = list[i]
		if fn then safeCall(fn, remaining) end
	end
	cd.fanning = cd.fanning - 1
	if cd.fanning == 0 and cd.dirty then compactListeners(cd) end
end

--- Seconds left on a named cooldown, 0 when it isn't running. Computed, never decremented.
function lib:CooldownRemaining(name)
	local cd = name and lib.cooldowns[name]
	if not cd then return 0 end
	local left = cd.endsAt - nowSeconds()
	if left <= 0 then return 0 end
	return left
end

--- Is the named cooldown blocking right now? The one predicate a click handler should ask.
function lib:OnCooldown(name)
	return lib:CooldownRemaining(name) > 0
end

--- Register a listener for a named cooldown. Returns the listener, so a caller can drop it again.
---
--- Listeners are per NAME rather than per cooldown-run, so a view that registers before the first start
--- keeps working across every later one. Called with whole seconds remaining, and with 0 exactly once when
--- it ends — that final call is what restores the button, so a listener must handle it.
function lib:OnCooldownTick(name, fn)
	if not (name and type(fn) == "function") then return nil end
	local cd = ensureCooldown(name)
	cd.listeners[#cd.listeners + 1] = fn
	return fn
end

--- Drop a listener OnCooldownTick added (MINOR 43). Removes every registration of that exact function for
--- that name; returns true when one was found, false (a no-op) otherwise. Never touches the cooldown's clock.
--- Safe from inside a listener: the removed one is not called again, even later in the same tick.
function lib:OffCooldownTick(name, fn)
	local cd = name and lib.cooldowns[name]
	if not (cd and fn) then return false end
	local found = false
	for i = 1, #cd.listeners do
		if cd.listeners[i] == fn then cd.listeners[i] = false; found = true end
	end
	if found then
		cd.dirty = true
		if (cd.fanning or 0) == 0 then compactListeners(cd) end
	end
	return found
end

--- Stop a named cooldown immediately and tell its listeners (remaining 0).
function lib:StopCooldown(name)
	local cd = name and lib.cooldowns[name]
	if not cd then return false end
	if cd.ticker then cd.ticker:Cancel(); cd.ticker = nil end
	cd.endsAt = 0
	fanCooldown(cd, 0)
	return true
end

--- Start (or restart) a named cooldown for `seconds`. Returns the deadline.
---
--- `seconds` <= 0 is a STOP rather than an error: "the thing that was rate-limited is available again" is a
--- real event and this is how a caller says it, which is exactly how FGI's driver reads a 0.
function lib:StartCooldown(name, seconds, opts)
	if not name then return nil end
	opts = opts or {}
	local secs = tonumber(seconds) or 0
	local cd = ensureCooldown(name)
	-- Cancel first, unconditionally — see the re-entrancy note above.
	if cd.ticker then cd.ticker:Cancel(); cd.ticker = nil end
	if secs <= 0 then
		cd.endsAt = 0
		fanCooldown(cd, 0)
		return 0
	end
	cd.endsAt = nowSeconds() + secs
	fanCooldown(cd, secs)
	if C_Timer and C_Timer.NewTicker then
		local interval = tonumber(opts.interval) or 1
		cd.ticker = C_Timer.NewTicker(interval, function()
			local left = lib:CooldownRemaining(name)
			fanCooldown(cd, left)
			-- Self-clear at zero. The ticker is given no iteration count deliberately: an iteration count is
			-- another copy of the duration, and the two disagree the moment `StartCooldown` is called again
			-- with a different length while the old ticker is mid-flight.
			if left <= 0 and cd.ticker then cd.ticker:Cancel(); cd.ticker = nil end
		end)
	end
	return cd.endsAt
end

--- Wire a Button to a named cooldown: FGI's scan-button treatment, as one call.
---
--- While the cooldown runs the caption is the whole seconds remaining, the text dims, the highlight is
--- hidden and `onClick` is not called. When it ends the caption, colour and highlight are restored and the
--- button works again. opts:
---   label          the resting caption (default the button's current text)
---   seconds        how long a click costs; may be a function evaluated per click (a live setting)
---   onClick(btn)   run ONLY when the button was not on cooldown; its return value is ignored
---   format(n)      optional caption for the counting state (default the integer seconds)
---   colour         { r, g, b } for the resting caption (default Blizzard's GameFontNormal yellow)
---   dim            { r, g, b } for the counting caption (default FGI's 0.55 grey)
---
--- Returns the button. The click is refused HERE rather than inside `onClick` so a second call site cannot
--- forget the check — the same reason the cooldown state itself is not left to the caller.
function lib:BindCooldownButton(button, name, opts)
	if not (button and name) then return button end
	opts = opts or {}
	local resting = opts.label or (button.GetText and button:GetText()) or ""
	local col     = opts.colour or NORMAL_FONT_GOLD
	local dim     = opts.dim or { 0.55, 0.55, 0.55 }

	local function paint(remaining)
		local counting = (remaining or 0) > 0
		local text = resting
		if counting then
			local n = math.ceil(remaining)
			-- Protected HERE and not only by fanCooldown: the bind-time paint below is a direct call, and a
			-- raise inside the fan would skip the colour and highlight. A failure shows the plain seconds.
			local ok, v
			if opts.format then ok, v = safeCall(opts.format, n) end
			text = (ok and v) or tostring(n)
		end
		if button.SetText then button:SetText(text) end
		local fs = button.GetFontString and button:GetFontString()
		if fs then
			local c = counting and dim or col
			fs:SetTextColor(c[1], c[2], c[3])
		end
		local hl = button.GetHighlightTexture and button:GetHighlightTexture()
		if hl then if counting then hl:Hide() else hl:Show() end end
	end

	-- A button bound again drops its earlier listener first, so rebinding never leaves two painters on any
	-- cooldown. A button that is thrown away instead of rebound needs W:UnbindCooldownButton.
	lib:UnbindCooldownButton(button)
	button._lagwCooldownBind = { name = name, fn = paint }
	lib:OnCooldownTick(name, paint)
	paint(lib:CooldownRemaining(name))

	button:SetScript("OnClick", function(btn, ...)
		if lib:OnCooldown(name) then return end
		-- Both protected: a raising onClick must not skip StartCooldown, or the rate limit is lost. A
		-- seconds function that raises counts as 0, the same as one returning nothing.
		if opts.onClick then safeCall(opts.onClick, btn, ...) end
		local secs = opts.seconds
		if type(secs) == "function" then
			local ok, v = safeCall(secs)
			secs = ok and v or nil
		end
		lib:StartCooldown(name, tonumber(secs) or 0)
	end)
	return button
end

--- Drop the painter BindCooldownButton registered for `button` (MINOR 43) -- call it when the button's
--- frame is released, so a view rebuilt with a NEW button (a language switch) leaves no painter on the old
--- one. Leaves the cooldown's clock and the button's OnClick alone. Returns true when the button was bound,
--- false (a no-op) otherwise.
function lib:UnbindCooldownButton(button)
	local bind = button and button._lagwCooldownBind
	if not bind then return false end
	button._lagwCooldownBind = nil
	lib:OffCooldownTick(bind.name, bind.fn)
	return true
end

-- ---------------------------------------------------------------------------
-- Scroll frame — a vertically-scrolling box with a slim thumb scrollbar
-- ---------------------------------------------------------------------------
-- Returns { scroll, content, scrollbar, SetContentHeight }. Anchor your content to
-- `.content` (TOPLEFT) and give it a width (the box width minus the bar); after (re)filling
-- it, call box:SetContentHeight(h) to sync the scroll range. The bar hides when everything
-- fits; mouse-wheel scrolls. opts: { barWidth = (default 10) }.
--
-- `opts.anchor = <frame>` (MINOR 33, Dibs' DIBSREQ-LAGW-007) does BOTH of the things a caller
-- otherwise has to remember: it fills that frame with the scroll (TOPLEFT/BOTTOMRIGHT, inset by
-- `opts.inset` on all four sides, default 0) AND anchors the content's two TOP CORNERS to the
-- scroll, which is how AceGUI's own ScrollFrame widget gives a scroll child its width. Without it
-- the returned scroll has no position and the content is 1x1, so rows anchored TOPLEFT/TOPRIGHT to
-- the content lay themselves out inside a one-pixel frame that is nowhere -- a window that draws
-- NOTHING while the count beside it says there is something to show. That shipped in a consumer for
-- six weeks. Omit `anchor` and nothing changes for the thirteen call sites that anchor by hand.
--
-- The content's width comes from the two-corner ANCHOR, never from a `GetWidth` read at build time:
-- a width read here is whatever the frame measured before layout, and `OnSizeChanged` fires only on
-- a change, so a one-time read is both wrong now and never corrected.
function lib:CreateScrollFrame(parent, opts)
	opts = opts or {}
	local barW = opts.barWidth or 10
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	if opts.anchor then
		local pad = opts.inset or 0
		scroll:SetPoint("TOPLEFT",     opts.anchor, "TOPLEFT",      pad, -pad)
		scroll:SetPoint("BOTTOMRIGHT", opts.anchor, "BOTTOMRIGHT", -pad,  pad)
		-- Two TOP corners only: the width is the scroll's less the bar, and the HEIGHT stays
		-- `SetContentHeight`'s, which is what makes the thing scroll at all. Anchoring the bottom
		-- as well would pin the content to the visible box and there would be nothing to scroll.
		content:SetPoint("TOPLEFT",  scroll, "TOPLEFT",   0, 0)
		content:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -barW, 0)
	end

	local sb = CreateFrame("Slider", nil, scroll)
	sb:SetOrientation("VERTICAL")
	sb:SetWidth(barW)
	sb:SetPoint("TOPRIGHT",    scroll, "TOPRIGHT",    0, 0)
	sb:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
	sb:SetMinMaxValues(0, 0)
	sb:SetValueStep(1)
	sb:SetValue(0)
	local track = sb:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(sb)
	track:SetColorTexture(1, 1, 1, 0.05)
	local thumb = sb:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(1, 1, 1, 0.35)
	thumb:SetSize(barW, 40)
	sb:SetThumbTexture(thumb)
	sb:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
	sb:Hide()

	scroll:EnableMouseWheel(true)
	-- One wheel notch moves 24px at scale 1.0 -- about a row and a half of small text -- and
	-- scales with the content, read at wheel time so no listener is needed.
	scroll:SetScript("OnMouseWheel", function(_, delta)
		local _, maxv = sb:GetMinMaxValues()
		if maxv <= 0 then return end
		sb:SetValue(math.min(maxv, math.max(0, sb:GetValue() - delta * lib:ScaledSize(24))))
	end)

	local box = { scroll = scroll, content = content, scrollbar = sb }
	function box:SetContentHeight(h)
		content:SetHeight(math.max(1, h))
		local maxv = math.max(0, h - (scroll:GetHeight() or 0))
		sb:SetMinMaxValues(0, maxv)
		sb:SetShown(maxv > 0)
		if sb:GetValue() > maxv then sb:SetValue(maxv) end
	end
	return box
end

-- ---------------------------------------------------------------------------
-- Expandable list — a scrolling datasheet of collapsible groups
-- ---------------------------------------------------------------------------
-- Each group is a header row (a "+"/"−" toggle glyph + a left label + a right-aligned value) that
-- expands to indented child rows (left label + right value). Built on CreateScrollFrame; header and
-- child rows are pooled and reused across SetData calls, and per-group expansion persists (keyed by
-- `key`, defaulting to `label`) so a refresh keeps what the user opened/closed. Anchor `list.frame`
-- like any frame; it re-lays-out on resize.
--
--   local list = W:CreateExpandableList(parent, { barWidth = 8, childColor = {0.7,0.7,0.7} })
--   list.frame:SetAllPoints(container)
--   list:SetData({
--       { key = "agi", label = "Agility", valueText = "272 EP", defaultExpanded = true, children = {
--           { label = "Cryptstalker Headpiece", valueText = "40 EP" },
--           { label = "Dragonstalker's Legguards", valueText = "35 EP" },
--       } },
--       { key = "set", label = "Set bonus", valueText = "2 EP" },   -- no children → not expandable
--   })
--
-- Group  = { key?, label, valueText?, children?, defaultExpanded? }.
-- Child  = { label, valueText?, color? = {r,g,b} }  (color overrides the default child colour).
-- MINOR 36: a child may carry its own `children`, to any depth, and any node takes `color`,
-- `onClick(node, mouseButton, rowFrame)` and `tooltip` -- see the note above `relayout`.
-- opts   = { barWidth, indent (14), rowHeight (16), childColor ({0.7,0.7,0.7}) }.
-- `rowHeight` and `indent` are scale-1.0 values; the rows re-lay at the new height on a scale
-- change (MINOR 29).
local function ExpandableList_OnScaleChanged(_, _, list)
	list:_relayout()
end

function lib:CreateExpandableList(parent, opts)
	opts = opts or {}
	local ROW_H  = opts.rowHeight or 16
	local INDENT = opts.indent or 14
	local cr, cg, cb = 0.72, 0.72, 0.72
	if opts.childColor then cr, cg, cb = opts.childColor[1], opts.childColor[2], opts.childColor[3] end
	-- `opts.valueColumn = { offset, width, justify }` (MINOR 42, TOGProfessionMaster inbox a79b0269):
	-- every row's value in ONE column -- LEFT at the row's left + offset (rows are not indented, only
	-- their glyph and label are, so depth never moves it), `width` wide, justified `justify` (default
	-- RIGHT). Both numbers are scale-1.0. The label still ends 6px before the value, so it truncates
	-- before the column; everything right of the column stays empty and the highlight spans the row.
	-- Without it the value is right-anchored at the row's right edge, as before.
	local VC = type(opts.valueColumn) == "table" and opts.valueColumn or nil
	local function placeValue(row)
		local v = row.value
		v:ClearAllPoints()
		if VC then
			v:SetPoint("LEFT", row, "LEFT", self:ScaledSize(tonumber(VC.offset) or 0), 0)
			v:SetWidth(self:ScaledSize(tonumber(VC.width) or 0))
			v:SetJustifyH(VC.justify or "RIGHT")
		else
			v:SetPoint("RIGHT", row, "RIGHT", 0, 0)
			v:SetJustifyH("RIGHT")
		end
	end

	local frame = CreateFrame("Frame", nil, parent)
	local box   = self:CreateScrollFrame(frame, { barWidth = opts.barWidth or 8 })
	box.scroll:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, 0)
	box.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	local barW    = opts.barWidth or 8
	local content = box.content
	-- The rows' width comes from these two ANCHORS, never from a GetWidth read (MINOR 42,
	-- TOGProfessionMaster inbox 0f350cea). This used to SetWidth the content to
	-- max(40, scroll:GetWidth() - bar - 2) inside relayout, re-run only from the OUTER frame's
	-- OnSizeChanged. A list SetAllPoints'd into an AceGUI group before that group was laid out read a
	-- ~0 scroll width, clamped to 40, and nothing re-read it once the scroll box had its real width --
	-- every label drawn as "..". The CreateScrollFrame note above says exactly why a one-time read is
	-- wrong; anchored, the engine keeps the width right in any sizing order.
	content:SetPoint("TOPLEFT",  box.scroll, "TOPLEFT",  0, 0)
	content:SetPoint("TOPRIGHT", box.scroll, "TOPRIGHT", -(barW + 2), 0)

	local list = { frame = frame, box = box }
	local headerPool, childPool = {}, {}
	local expanded, data = {}, {}

	local function acquireHeader(i)
		local h = headerPool[i]
		if not h then
			h = CreateFrame("Button", nil, content)
			local hl = h:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(h); hl:SetColorTexture(1, 1, 1, 0.08)
			h.glyph = h:CreateFontString(nil, "OVERLAY")
			h.glyph:SetFontObject(self:ScaledFont("GameFontHighlightSmall"))
			h.glyph:SetPoint("LEFT", h, "LEFT", 0, 0); h.glyph:SetJustifyH("LEFT")
			h.value = h:CreateFontString(nil, "OVERLAY")
			h.value:SetFontObject(self:ScaledFont("GameFontHighlightSmall"))
			h.value:SetPoint("RIGHT", h, "RIGHT", 0, 0); h.value:SetJustifyH("RIGHT")
			h.label = h:CreateFontString(nil, "OVERLAY")
			h.label:SetFontObject(self:ScaledFont("GameFontNormalSmall"))
			h.label:SetPoint("RIGHT", h.value, "LEFT", -6, 0)
			h.label:SetJustifyH("LEFT"); h.label:SetWordWrap(false)
			-- The font's own colour, put back on a node with no `color` (MINOR 36).
			h._defColor = { h.label:GetTextColor() }
			headerPool[i] = h
		end
		-- Geometry per acquire, at the current scale: the pools outlive any one scale. The left edges
		-- depend on the node's depth and are set by the layout.
		h:SetHeight(self:ScaledSize(ROW_H))
		h.glyph:SetWidth(self:ScaledSize(12))
		placeValue(h)   -- per acquire, so the column follows the scale
		return h
	end
	local function acquireChild(i)
		local c = childPool[i]
		if not c then
			c = CreateFrame("Frame", nil, content)
			c.value = c:CreateFontString(nil, "OVERLAY")
			c.value:SetFontObject(self:ScaledFont("GameFontHighlightSmall"))
			c.value:SetPoint("RIGHT", c, "RIGHT", 0, 0); c.value:SetJustifyH("RIGHT")
			c.label = c:CreateFontString(nil, "OVERLAY")
			c.label:SetFontObject(self:ScaledFont("GameFontHighlightSmall"))
			c.label:SetPoint("RIGHT", c.value, "LEFT", -6, 0)
			c.label:SetJustifyH("LEFT"); c.label:SetWordWrap(false)
			childPool[i] = c
		end
		c:SetHeight(self:ScaledSize(ROW_H))
		placeValue(c)
		return c
	end

	-- ANY DEPTH (MINOR 36, TOGProfessionMaster inbox 7ab1cb56): a node with `children` is a group at
	-- whatever depth it sits, drawn in the header style and indented `indent` per level; a node without
	-- them is a leaf, drawn in the header style at depth 0 and the child style below it -- which is exactly
	-- the old two-level picture, so existing data draws unchanged. A group's expand state is keyed by the
	-- PATH of keys from the top ("prof\001spec"), so two specs with one name under two professions keep
	-- their own state; a top-level group's path is its own key, as before.
	--
	-- Per node (MINOR 36): `color = {r,g,b}` (a leaf's already worked), `onClick(node, mouseButton,
	-- rowFrame)`, and `tooltip = { title, body }` or `tooltip = function(node) return title, body end`,
	-- read on hover. A group's click toggles it and then calls its onClick. Every script is set on each
	-- layout from the node drawn there, so nothing follows a pooled row to another node.
	local SEP = "\001"

	-- Put a pooled row's click and hover in place for `node`, or take them away.
	local function wire(row, node, toggle)
		local tip, click = node.tooltip, node.onClick
		local wants = toggle or click or tip
		row:EnableMouse(wants and true or false)
		local down = row:IsObjectType("Button") and "OnClick" or "OnMouseDown"
		if toggle or click then
			row:SetScript(down, function(f, mouseButton)
				if toggle then toggle() end
				if click then safeCall(click, node, mouseButton, f) end
			end)
		else
			row:SetScript(down, nil)
		end
		if tip then
			row:SetScript("OnEnter", function(f)
				local t, b
				if type(tip) == "function" then
					-- safeCall hands back one value and this returns two, so they travel as a pair.
					local ok, pair = safeCall(function(n) return { tip(n) } end, node)
					if ok and pair then t, b = pair[1], pair[2] end
				else
					t, b = tip[1] or tip.title, tip[2] or tip.body
				end
				lib:ShowTooltip(f, t, b)
			end)
			row:SetScript("OnLeave", function(f) lib:HideTooltip(f) end)
		else
			row:SetScript("OnEnter", nil)
			row:SetScript("OnLeave", nil)
		end
	end

	local function relayout()
		local rowH = self:ScaledSize(ROW_H)
		local y, hi, ci = 0, 0, 0

		local function place(row)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
			row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
			row:Show()
			y = y + rowH
		end

		local function walk(nodes, depth, prefix)
			for _, n in ipairs(nodes) do
				local key = n.key
				if key == nil then key = n.label end
				local path = prefix and (prefix .. SEP .. tostring(key)) or key
				local hasKids = n.children and #n.children > 0
				local ind = self:ScaledSize(INDENT * depth)
				if hasKids or depth == 0 then
					hi = hi + 1
					local h = acquireHeader(hi)
					h.glyph:SetPoint("LEFT", h, "LEFT", ind, 0)
					h.label:SetPoint("LEFT", h, "LEFT", ind + self:ScaledSize(13), 0)
					h.glyph:SetText(hasKids and (expanded[path] and "-" or "+") or "")
					h.label:SetText(n.label or "")
					h.value:SetText(n.valueText or "")
					local c = n.color or h._defColor
					h.label:SetTextColor(c[1], c[2], c[3])
					wire(h, n, hasKids and function() expanded[path] = not expanded[path]; relayout() end or nil)
					place(h)
					if hasKids and expanded[path] then walk(n.children, depth + 1, path) end
				else
					ci = ci + 1
					local c = acquireChild(ci)
					c.label:SetPoint("LEFT", c, "LEFT", ind, 0)
					c.label:SetText(n.label or "")
					c.value:SetText(n.valueText or "")
					local r, g2, b = cr, cg, cb
					if n.color then r, g2, b = n.color[1], n.color[2], n.color[3] end
					c.label:SetTextColor(r, g2, b); c.value:SetTextColor(r, g2, b)
					wire(c, n, nil)
					place(c)
				end
			end
		end
		walk(data, 0, nil)

		for j = hi + 1, #headerPool do headerPool[j]:Hide() end
		for j = ci + 1, #childPool  do childPool[j]:Hide()  end
		box:SetContentHeight(y + 2)
	end
	list._relayout = relayout
	self:OnScaleChanged(list, ExpandableList_OnScaleChanged)

	-- Every group at every depth, with its path: `fn(node, path)`.
	local function eachGroup(nodes, prefix, fn)
		for _, n in ipairs(nodes or {}) do
			if n.key == nil and prefix == nil then n.key = n.label end   -- the old top-level behaviour
			local key = n.key
			if key == nil then key = n.label end
			local path = prefix and (prefix .. SEP .. tostring(key)) or key
			if n.children and #n.children > 0 then
				fn(n, path)
				eachGroup(n.children, path, fn)
			elseif prefix == nil then
				fn(n, path)   -- a top-level leaf still takes defaultExpanded, as it always did
			end
		end
	end

	-- Replace the list contents. Groups keep their prior expand state; a group seen for the first
	-- time opens when `defaultExpanded` is set (otherwise starts collapsed).
	function list:SetData(groups)
		data = groups or {}
		eachGroup(data, nil, function(n, path)
			if expanded[path] == nil and n.defaultExpanded then expanded[path] = true end
		end)
		relayout()
	end

	-- Open / close every group, at every depth, at once (e.g. an "expand all" affordance).
	function list:SetAllExpanded(open)
		eachGroup(data, nil, function(n, path)
			if n.children and #n.children > 0 then expanded[path] = open and true or false end
		end)
		relayout()
	end

	-- Is the group at this path of keys open? `list:IsExpanded("prof", "spec")`.
	function list:IsExpanded(...)
		return expanded[table.concat({ ... }, SEP)] and true or false
	end

	-- The scroll range depends on the scroll box's HEIGHT, so re-lay when IT changes size (MINOR 42,
	-- inbox 0f350cea). Not the outer frame as well: the scroll box fills it TOPLEFT/BOTTOMRIGHT, so any
	-- change to the frame reaches here, and hooking both walked the data twice per resize (Peer Review
	-- on 80ee2fe1, L1).
	box.scroll:HookScript("OnSizeChanged", relayout)
	return list
end

-- ---------------------------------------------------------------------------
-- Shared backdrops (exposed for consumers and the later widget files)
-- ---------------------------------------------------------------------------
lib.FrameBackdrop = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 8, right = 8, top = 8, bottom = 8 },
}
lib.PaneBackdrop = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 3, right = 3, top = 5, bottom = 3 },
}

-- ===========================================================================
-- ClearFrame — movable/resizable window with a DialogBox title bar
-- ===========================================================================
do
	-- FastGuildInvite vendors an older fork of this widget in its own `Libs/GUI.lua` and registers
	-- `ClearFrame` at 26. 29 beats 26, so this library's implementation wins for every consumer --
	-- including FGI itself. That is the version number doing the work, not the design; see the note on
	-- `GroupFrame` below, where the two used to TIE and resolve by load order instead. Keep all three
	-- of these above the fork's 26. Peer review finding 12.
	--
	-- 28 -> 29: the frame structure changed. The three sizer strips are now built by
	-- `lib:MakeResizable` and there is an extra child frame (the OnUpdate throttle driver), so a
	-- session holding both copies must take this one.
	-- 29 -> 30: the chrome follows the UI scale (MINOR 29) -- title and status fonts, the bar, its
	-- controls and the content inset re-lay on `OnScaleChanged`. A MINOR-28 copy at 29 would tie and
	-- win by load order, and its window would be the one that ignores the slider.
	-- 31 (MINOR 36): SetInfoTooltip takes { minWidth }. At a tie AceGUI keeps the FIRST registration,
	-- so an older copy loaded earlier would keep a ClearFrame that ignores it. The three move together.
	-- 32 (MINOR 40): SetHeaderButton. An older ClearFrame at 31 winning the tie would have no method,
	-- and a consumer's `if win.SetHeaderButton` would see nothing while `W.AttachHeaderButton` exists.
	-- 33 (MINOR 41): re-lays-out its contents during a resize drag, not only at mouse-up.
	-- 34 (MINOR 45): the settings button calls its handler through safeCall. At 33 an older copy loaded
	-- first would keep the bare handler (Peer Review NEW-1 on 3028f298).
	local Type, Version = "ClearFrame", 34
	local AceGUI = LibStub("AceGUI-3.0", true)
	if AceGUI and (AceGUI:GetWidgetVersion(Type) or 0) < Version then
		local pairs = pairs
		local CreateFrame, UIParent = CreateFrame, UIParent

		local function Frame_OnShow(frame) frame.obj:Fire("OnShow") end
		local function Frame_OnClose(frame) frame.obj:Fire("OnClose") end
		local function Frame_OnMouseDown() AceGUI:ClearFocus() end
		local function Title_OnMouseDown(frame)
			frame:GetParent():StartMoving()
			AceGUI:ClearFocus()
		end
		local function MoverSizer_OnMouseUp(mover)
			local frame = mover:GetParent()
			frame:StopMovingOrSizing()
			local self = frame.obj
			local status = self.status or self.localstatus
			status.width = frame:GetWidth()
			status.height = frame:GetHeight()
			status.top = frame:GetTop()
			status.left = frame:GetLeft()
		end
		-- The three sizer OnMouseDown handlers that used to live here are gone: `lib:MakeResizable`
		-- builds the same grips, with the same geometry and the same StartSizing points, and the
		-- Constructor below calls it. `MoverSizer_OnMouseUp` above is still the TITLE BAR's, which
		-- is a mover and not part of the resize framework.

		-- Bottom status-bar controls.
		local function Close_OnClick(button)
			PlaySound(799)   -- SOUNDKIT.GS_TITLE_OPTION_EXIT
			button:GetParent().obj:Hide()
		end
		local function Info_OnEnter(button)
			local obj = button:GetParent().obj
			local tip = obj and obj._infoTooltip
			if not tip then return end
			lib:AnchorTooltip(button)
			restoreTip()
			raiseTipWidth(obj._infoMinWidth)   -- MINOR 36: SetInfoTooltip(tooltip, { minWidth })
			if type(tip) == "function" then
				safeCall(tip, GameTooltip)   -- a raising filler is reported; the Show below still runs
			else
				GameTooltip:SetText(tostring(tip), 1, 1, 1, 1, true)
			end
			GameTooltip:Show()
		end
		local function Info_OnLeave() lib:HideTooltip() end
		-- The file-level `liftAboveSizers` (the bottom-row section above) is the one copy. This block
		-- carried its own identical local until MINOR 33, agreeing with the four consumers' hand-rolled
		-- copies only because each had been pasted from the last.

		-- The chrome at the current scale. AceGUI's Frame numbers, multiplied: the title band is 40
		-- tall with 30-wide end caps and the text 14 down from its top; the status bar is 24 tall at
		-- 15 from the bottom-left, its controls 20 square and the Close button 90x20; the content
		-- starts 27 below the top and stops just above the bar. Horizontal insets (17, 15) are the
		-- border art and do not scale. Applied at construction and again on every scale change.
		local TOP_INSET, BAR_H, BAR_BOTTOM = 27, 24, 15
		-- AceGUI reports the content 10px taller than its anchors give it (`height - 57` against a
		-- 27 + 40 inset) and every consumer's layout was written against that number, so the fudge is
		-- kept as a named constant rather than corrected under them.
		local ACEGUI_HEIGHT_FUDGE = 10
		local function contentInsets()
			local top = lib:ScaledSize(TOP_INSET)
			local bottom = BAR_BOTTOM + lib:ScaledSize(BAR_H) + 1
			return top, bottom
		end
		local function layoutChrome(self)
			local S = function(px) return lib:ScaledSize(px) end
			local top, bottom = contentInsets()
			self.titlebg:SetHeight(S(40))
			self.titlebg:ClearAllPoints()
			self.titlebg:SetPoint("TOP", 0, S(12))
			self.titletext:ClearAllPoints()
			self.titletext:SetPoint("TOP", self.titlebg, "TOP", 0, -S(14))
			self.titlebg_l:SetSize(S(30), S(40))
			self.titlebg_r:SetSize(S(30), S(40))
			self.content:ClearAllPoints()
			self.content:SetPoint("TOPLEFT", 17, -top)
			self.content:SetPoint("BOTTOMRIGHT", -17, bottom)
			self.close:SetSize(S(90), S(20))
			self.info:SetSize(S(20), S(20))
			self.settings:SetSize(S(20), S(20))
			self.statusbg:SetHeight(S(BAR_H))
			self:SetTitle(self.titletext:GetText())   -- the band width follows the (re-sized) text
		end
		local function ClearFrame_OnScaleChanged(_, _, self)
			layoutChrome(self)
			-- The content region moved, so AceGUI's idea of its height is stale; re-run the height
			-- hook and the layout with the frame's own current size.
			self:OnHeightSet(self.frame:GetHeight() or 0)
			self:OnWidthSet(self.frame:GetWidth() or 0)
			if self.DoLayout then self:DoLayout() end
		end

		local methods = {
			["OnAcquire"] = function(self)
				self.frame:SetParent(UIParent)
				self.frame:SetFrameStrata("FULLSCREEN_DIALOG")
				self:SetTitle()
				self:ApplyStatus()
				self:Show()
			end,
			["OnRelease"] = function(self)
				self.status = nil
				self._infoTooltip, self._infoMinWidth = nil, nil
				if self.info then self.info:Hide() end
				if self.statustext then self.statustext:SetText("") end
			end,

			-- Position + size persistence. Bind a saved table via SetStatusTable
			-- (e.g. an addon SavedVariables sub-table): the mover/sizer writes
			-- top/left/width/height into it, and ApplyStatus restores them (default
			-- CENTER, 700x500), so consumer windows persist across sessions/reloads.
			["SetStatusTable"] = function(self, status)
				assert(type(status) == "table", "SetStatusTable: table expected")
				self.status = status
				self:ApplyStatus()
			end,
			["ApplyStatus"] = function(self)
				local status = self.status or self.localstatus
				local frame = self.frame
				self:SetWidth(status.width or 700)
				self:SetHeight(status.height or 500)
				frame:ClearAllPoints()
				if status.top and status.left then
					frame:SetPoint("TOP", UIParent, "BOTTOM", 0, status.top)
					frame:SetPoint("LEFT", UIParent, "LEFT", status.left, 0)
				else
					frame:SetPoint("CENTER")
				end
			end,
			["OnWidthSet"] = function(self, width)
				local content = self.content
				local contentwidth = width - 34
				if contentwidth < 0 then contentwidth = 0 end
				content:SetWidth(contentwidth)
				content.width = contentwidth
			end,
			["OnHeightSet"] = function(self, height)
				local content = self.content
				-- 27 + 40 - 10 = 57 at scale 1.0, exactly AceGUI's number; the insets scale, the
				-- fudge does not.
				local top, bottom = contentInsets()
				local contentheight = height - (top + bottom - ACEGUI_HEIGHT_FUDGE)
				if contentheight < 0 then contentheight = 0 end
				content:SetHeight(contentheight)
				content.height = contentheight
			end,
			["SetTitle"] = function(self, title)
				self.titletext:SetText(title)
				self.titlebg:SetWidth((self.titletext:GetWidth() or 0) + lib:ScaledSize(10))
			end,
			["Hide"] = function(self) self.frame:Hide() end,
			["Show"] = function(self) self.frame:Show() end,
			["SetStatusText"] = function(self, text)
				self.statustext:SetText(text or "")
			end,
			-- Set the bottom-right info "i" tooltip. `tooltip` is a string or a
			-- function(GameTooltip) that fills it. nil hides the icon. `opts.minWidth` (MINOR 36) floors
			-- the tooltip's width for long help text, restored when it hides.
			["SetInfoTooltip"] = function(self, tooltip, opts)
				self._infoTooltip = tooltip
				self._infoMinWidth = opts and tonumber(opts.minWidth) or nil
				if tooltip then self.info:Show() else self.info:Hide() end
			end,
			-- Enable the bottom-bar settings gear (FGI's Trade_Engineering icon, left of the info "i"). `handler`
			-- fires on click; `tipTitle`/`tipBody` fill its tooltip; a nil handler hides it. The status box
			-- shrinks to make room, so it lines up like FGI's icon row.
			["SetSettingsButton"] = function(self, handler, tipTitle, tipBody)
				local btn = self.settings
				if not btn then return end
				if handler then
					btn._onClick, btn._tipTitle, btn._tipBody = handler, tipTitle, tipBody
					btn:Show()
					self.statusbg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -6, -2)
				else
					btn:Hide()
					self.statusbg:SetPoint("BOTTOMRIGHT", self.info, "BOTTOMLEFT", -6, -2)
				end
			end,
			-- A text button in the top-right corner (MINOR 40, Grouper inbox 12c62f8b). The shared
			-- `lib:AttachHeaderButton` builds it, so a stock AceGUI Frame gets the identical button;
			-- `text = nil` hides it, and Release takes it down.
			["SetHeaderButton"] = function(self, text, onClick, tipTitle, tipBody)
				return lib:AttachHeaderButton(self, text, onClick, tipTitle, tipBody)
			end,
		}

		local function Constructor()
			local frame = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
			frame:Hide()

			frame:EnableMouse(true)
			frame:SetMovable(true)
			frame:SetFrameStrata("FULLSCREEN_DIALOG")
			frame:SetBackdrop(lib.FrameBackdrop)
			frame:SetBackdropColor(0, 0, 0, 1)
			-- SetResizable + the 400x200 bounds were spelled out here, and again as a
			-- SetResizeBounds/SetMinResize fork. Both are now the MakeResizable call further down,
			-- which is the only place in this library that has to know the two spellings.
			frame:SetToplevel(true)
			frame:SetScript("OnShow", Frame_OnShow)
			frame:SetScript("OnHide", Frame_OnClose)
			frame:SetScript("OnMouseDown", Frame_OnMouseDown)

			local titlebg = frame:CreateTexture(nil, "OVERLAY")
			titlebg:SetTexture(131080) -- Interface\\DialogFrame\\UI-DialogBox-Header
			titlebg:SetTexCoord(0.31, 0.67, 0, 0.63)
			titlebg:SetPoint("TOP", 0, 12)
			titlebg:SetWidth(100)
			titlebg:SetHeight(40)

			local title = CreateFrame("Frame", nil, frame)
			title:EnableMouse(true)
			title:SetScript("OnMouseDown", Title_OnMouseDown)
			title:SetScript("OnMouseUp", MoverSizer_OnMouseUp)
			title:SetAllPoints(titlebg)

			local titletext = title:CreateFontString(nil, "OVERLAY")
			titletext:SetFontObject(lib:ScaledFont("GameFontNormal"))
			titletext:SetPoint("TOP", titlebg, "TOP", 0, -14)

			local titlebg_l = frame:CreateTexture(nil, "OVERLAY")
			titlebg_l:SetParent(title)
			titlebg_l:SetTexture(131080)
			titlebg_l:SetTexCoord(0.21, 0.31, 0, 0.63)
			titlebg_l:SetPoint("RIGHT", titlebg, "LEFT")
			titlebg_l:SetWidth(30)
			titlebg_l:SetHeight(40)

			local titlebg_r = frame:CreateTexture(nil, "OVERLAY")
			titlebg_r:SetParent(title)
			titlebg_r:SetTexture(131080)
			titlebg_r:SetTexCoord(0.67, 0.77, 0, 0.63)
			titlebg_r:SetPoint("LEFT", titlebg, "RIGHT")
			titlebg_r:SetWidth(30)
			titlebg_r:SetHeight(40)

			-- Container support
			local content = CreateFrame("Frame", nil, frame)
			content:SetPoint("TOPLEFT", 17, -27)
			content:SetPoint("BOTTOMRIGHT", -17, 40)

			-- Resize grips, through the shared framework rather than beside it. Same three strips,
			-- same geometry, same StartSizing points -- the difference is that a consumer can now
			-- get them on its OWN window (lib:MakeResizable) instead of having to be a ClearFrame.
			--
			-- `onResizeStop` reproduces MoverSizer_OnMouseUp's persistence exactly. It has to be a
			-- callback rather than the framework's `status` option because AceGUI's status table is
			-- swapped at runtime by SetStatusTable -- `self.status or self.localstatus` has to be
			-- read at drag-end, not bound once at construction.
			-- `assert` rather than a nil check: MakeResizable only answers nil when the target is
			-- not a frame, and `frame` was made by CreateFrame ten lines up. Failing loudly here
			-- beats a ClearFrame that silently has no grips.
			local resize = assert(lib:MakeResizable(frame, {
				minW  = 400,
				minH  = 200,
				grips = "SE S E",
				-- Live re-layout during the drag (MINOR 41, Dibs' DIBSREQ-LAGW-003). The framework
				-- coalesces onResize to at most once per draw, so this is one DoLayout per frame while
				-- the mouse is down. `f.obj`, read at call time, not the constructor's `widget`: AceGUI
				-- pools the frame, and a stale reference would lay out the wrong owner.
				-- AceGUI's own ContentResize (RegisterAsContainer's content OnSizeChanged) also calls
				-- DoLayout, and records the size it laid out at in `content.width/height`. When those
				-- already match, that hook ran for this size and a second layout would be wasted work;
				-- only a size it missed is laid out here.
				onResize = function(f)
					local obj = f.obj
					if not (obj and obj.DoLayout) then return end
					local c = obj.content
					if c and c.width == c:GetWidth() and c.height == c:GetHeight() then return end
					if c then c.width, c.height = c:GetWidth(), c:GetHeight() end
					obj:DoLayout()
				end,
				onResizeStop = function(f)
					local obj = f.obj
					if not obj then return end
					local status = obj.status or obj.localstatus
					if not status then return end
					status.width  = f:GetWidth()
					status.height = f:GetHeight()
					status.top    = f:GetTop()
					status.left   = f:GetLeft()
				end,
			}), "ClearFrame: MakeResizable refused its own frame")
			local sizer_se, sizer_s, sizer_e = resize.grips.SE, resize.grips.S, resize.grips.E

			-- Bottom status bar: a PaneBackdrop bar with status text, a Close button,
			-- and an info "i" icon (tooltip set by the consumer via SetInfoTooltip).
			-- All lifted above the resize strips so they stay fully clickable.
			local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			close:SetSize(90, 20)
			close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 17)
			close:SetText(CLOSE)
			scaleButtonFonts(lib, close)
			close:SetScript("OnClick", Close_OnClick)
			liftAboveSizers(close)

			local info = CreateFrame("Button", nil, frame)
			info:SetSize(20, 20)
			info:SetPoint("RIGHT", close, "LEFT", -6, 0)
			local infoTex = info:CreateTexture(nil, "OVERLAY")
			infoTex:SetAllPoints(info)
			infoTex:SetTexture("Interface\\Common\\help-i")
			info:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			info:SetHitRectInsets(-2, -2, -2, -2)
			info:SetScript("OnEnter", Info_OnEnter)
			info:SetScript("OnLeave", Info_OnLeave)
			liftAboveSizers(info)
			info:Hide()

			local statusbg = CreateFrame("Button", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
			statusbg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 15)
			statusbg:SetPoint("BOTTOMRIGHT", info, "BOTTOMLEFT", -6, -2)
			statusbg:SetHeight(24)
			statusbg:SetBackdrop(lib.PaneBackdrop)
			statusbg:SetBackdropColor(0.1, 0.1, 0.1)
			statusbg:SetBackdropBorderColor(0.4, 0.4, 0.4)
			liftAboveSizers(statusbg)

			local statustext = statusbg:CreateFontString(nil, "OVERLAY")
			statustext:SetFontObject(lib:ScaledFont("GameFontNormalSmall"))
			statustext:SetPoint("TOPLEFT", 7, -3)
			statustext:SetPoint("BOTTOMRIGHT", -7, 3)
			statustext:SetJustifyH("LEFT")
			statustext:SetText("")

			-- Optional settings gear (FastGuildInvite's Trade_Engineering icon), parked on the bottom bar just
			-- left of the info "i". Hidden until SetSettingsButton is called; the status box then shrinks to make
			-- room. Lifted above the resize strips like the other bottom-row controls (the border/sizer-overlap
			-- fix — negative HitRectInsets + a TexCoord crop match FGI so the whole 20x20 box is clickable and the
			-- gear fills it edge to edge).
			local settings = CreateFrame("Button", nil, frame)
			settings:SetSize(20, 20)
			settings:SetPoint("RIGHT", info, "LEFT", -6, 0)
			settings:SetNormalTexture("Interface\\Icons\\Trade_Engineering")
			settings:SetPushedTexture("Interface\\Icons\\Trade_Engineering")
			local sgn = settings:GetNormalTexture(); if sgn then sgn:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
			local sgp = settings:GetPushedTexture()
			if sgp then sgp:SetTexCoord(0.08, 0.92, 0.08, 0.92); sgp:SetVertexColor(0.7, 0.7, 0.7) end
			settings:SetHitRectInsets(-2, -2, -2, -2)
			settings:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			settings:SetScript("OnClick", function() if settings._onClick then safeCall(settings._onClick) end end)
			settings:SetScript("OnEnter", function(b) showTooltip(b, settings._tipTitle, settings._tipBody) end)
			settings:SetScript("OnLeave", function(b) lib:HideTooltip(b) end)
			liftAboveSizers(settings)
			settings:Hide()

			local widget = {
				localstatus = {},
				title       = title,
				titletext   = titletext,
				titlebg     = titlebg,
				titlebg_l   = titlebg_l,
				titlebg_r   = titlebg_r,
				content     = content,
				statustext  = statustext,
				info        = info,
				settings    = settings,
				close       = close,
				statusbg    = statusbg,
				frame       = frame,
				sizer_se    = sizer_se,
				sizer_s     = sizer_s,
				sizer_e     = sizer_e,
				type        = Type,
			}
			for method, func in pairs(methods) do
				widget[method] = func
			end

			-- The chrome at whatever the scale already is (a window built after the slider moved),
			-- and again on every change. AceGUI pools the widget for the session, so the weak key
			-- stays live.
			layoutChrome(widget)
			lib:OnScaleChanged(widget, ClearFrame_OnScaleChanged)

			widget = AceGUI:RegisterAsContainer(widget)
			-- RegisterAsContainer does `frame:SetScript("OnSizeChanged", FrameResize)` -- SetScript, not
			-- HookScript -- which REPLACES the hook MakeResizable installed above, and with it the
			-- framework's promise that a programmatic SetWidth wakes the onResize driver. Since MINOR 26
			-- that promise was silently false for a ClearFrame (a drag never needed the hook, so nothing
			-- noticed; found by the MINOR-29 audit). Re-hooked here, after AceGUI's own handler.
			-- `lib.ResizeOnSizeChanged` rather than a file-local since the framework moved to
			-- LibAceGUIWidgets-Resize.lua; it is set by the time any widget is constructed.
			frame:HookScript("OnSizeChanged", lib.ResizeOnSizeChanged)
			return widget
		end

		AceGUI:RegisterWidgetType(Type, Constructor, Version)
	end
end

-- ===========================================================================
-- GroupFrame — borderless movable/resizable container
-- ===========================================================================
do
	-- 26 -> 28 to break a TIE, not because the frame structure changed. FastGuildInvite vendors an
	-- older fork of these widgets in its own `Libs/GUI.lua` and registers `GroupFrame` at 26 as well.
	-- AceGUI's rule is `if oldVersion and oldVersion >= Version then return end`, so equal versions
	-- resolve by LOAD ORDER -- and load order between two addons with no dependency relationship is
	-- controllable by neither. A consumer that declares a dependency on this library could therefore
	-- receive the fork's widget instead, with the loader honouring the declaration and the registry
	-- quietly undoing it. Peer review finding 12.
	-- `RegisterWidgetType` returns nothing and logs nothing, so neither side can detect which won;
	-- this comment is the only thing that makes the next divergence visible.
	--
	-- 28 -> 29 with ClearFrame, whose structure DID change. Nothing about this widget moved; the
	-- three are raised together on purpose, because the last time one was raised alone the other two
	-- sat tied with the fork for an unknown length of time and nothing said so.
	-- `Tests/widgetversion_spec.lua` asserts the three stay equal for exactly that reason.
	-- 29 -> 30 with ClearFrame (the UI scale, MINOR 29). This one's own change: the 400x200 floor is
	-- now a scale-1.0 value applied through MakeResizable, so it follows the scale.
	-- 32 with ClearFrame (SetHeaderButton, MINOR 40); nothing here changed.
	-- 33 with ClearFrame (live re-layout, MINOR 41); nothing here changed.
	-- 34 with ClearFrame and TLabel (MINOR 45); nothing here changed.
	local Type, Version = "GroupFrame", 34
	local AceGUI = LibStub("AceGUI-3.0", true)
	if AceGUI and (AceGUI:GetWidgetVersion(Type) or 0) < Version then
		local pairs = pairs
		local CreateFrame, UIParent = CreateFrame, UIParent

		local function Frame_OnShow(frame) frame.obj:Fire("OnShow") end
		local function Frame_OnClose(frame) frame.obj:Fire("OnClose") end
		local function Frame_OnMouseDown() AceGUI:ClearFocus() end

		local methods = {
			["OnAcquire"] = function(self)
				self.frame:SetParent(UIParent)
				self.frame:SetFrameStrata("FULLSCREEN_DIALOG")
				self:Show()
			end,
			["OnRelease"] = function() end,
			["OnWidthSet"] = function(self, width)
				local content = self.content
				local contentwidth = width - 34
				if contentwidth < 0 then contentwidth = 0 end
				content:SetWidth(contentwidth)
				content.width = contentwidth
			end,
			["OnHeightSet"] = function(self, height)
				local content = self.content
				local contentheight = height - 57
				if contentheight < 0 then contentheight = 0 end
				content:SetHeight(contentheight)
				content.height = contentheight
			end,
			["Hide"] = function(self) self.frame:Hide() end,
			["Show"] = function(self) self.frame:Show() end,
		}

		local function Constructor()
			local frame = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
			frame:Hide()

			frame:EnableMouse(true)
			frame:SetMovable(true)
			frame:SetFrameStrata("FULLSCREEN_DIALOG")
			frame:SetBackdropColor(0, 0, 0, 1)
			-- SetResizable + the bounds fork used to be spelled out here. `grips = false` is the
			-- framework's "bounds, no drag handles": the floor is a scale-1.0 value that the handle
			-- re-applies on every scale change, which two bare SetMinResize calls cannot do.
			assert(lib:MakeResizable(frame, { minW = 400, minH = 200, grips = false }),
				"GroupFrame: MakeResizable refused its own frame")
			frame:SetToplevel(true)
			frame:SetScript("OnShow", Frame_OnShow)
			frame:SetScript("OnHide", Frame_OnClose)
			frame:SetScript("OnMouseDown", Frame_OnMouseDown)

			-- Container support
			local content = CreateFrame("Frame", nil, frame)
			content:SetPoint("TOPLEFT", 17, -27)
			content:SetPoint("BOTTOMRIGHT", -17, 40)

			local widget = {
				content = content,
				frame   = frame,
				type    = Type,
			}
			for method, func in pairs(methods) do
				widget[method] = func
			end

			widget = AceGUI:RegisterAsContainer(widget)
			frame:HookScript("OnSizeChanged", lib.ResizeOnSizeChanged)   -- see ClearFrame: AceGUI's SetScript replaced it
			return widget
		end

		AceGUI:RegisterWidgetType(Type, Constructor, Version)
	end
end

-- ===========================================================================
-- TLabel — text + optional icon, with multi-line tooltip support
-- ===========================================================================
do
	-- 26 -> 28 to break a TIE with FastGuildInvite's vendored fork, which also registers `TLabel` at
	-- 26. See the note on `GroupFrame` above for the mechanism -- equal versions resolve by load order,
	-- which neither addon controls, so a declared dependency on this library did not guarantee that
	-- this library's widget is the one a consumer got. Peer review finding 12.
	-- 28 -> 29 alongside the other two; see the GroupFrame note for why they move together.
	-- 29 -> 30: the label follows the UI scale (MINOR 29) -- SetFontObject resolves through
	-- ScaledFont, SetImageSize takes scale-1.0 sizes, and the widget re-lays on a change.
	-- 32 with ClearFrame (SetHeaderButton, MINOR 40); nothing here changed.
	-- 33 with ClearFrame (live re-layout, MINOR 41); nothing here changed.
	-- 34 (MINOR 45): the tooltip anchors through AnchorTooltip, so a raising owner is reported and falls
	-- back to the built-in placement. At 33 an older copy loaded first would keep the bare owner call.
	local Type, Version = "TLabel", 34
	local AceGUI = LibStub("AceGUI-3.0", true)
	if AceGUI and (AceGUI:GetWidgetVersion(Type) or 0) < Version then
		local max, select, pairs = math.max, select, pairs
		local CreateFrame, UIParent = CreateFrame, UIParent

		local function UpdateImageAnchor(self)
			if self.resizing then return end
			local frame = self.frame
			local width = frame.width or frame:GetWidth() or 0
			local image = self.image
			local label = self.label
			local height

			label:ClearAllPoints()
			image:ClearAllPoints()

			if self.imageshown then
				local imagewidth = image:GetWidth()
				if (width - imagewidth) < 200 or (label:GetText() or "") == "" then
					-- image on top, centered, when the text is cramped or absent
					image:SetPoint("TOP")
					label:SetPoint("TOP", image, "BOTTOM")
					label:SetPoint("LEFT")
					label:SetWidth(width)
					height = image:GetHeight() + label:GetStringHeight()
				else
					-- image on the left
					image:SetPoint("TOPLEFT")
					if image:GetHeight() > label:GetStringHeight() then
						label:SetPoint("LEFT", image, "RIGHT", 4, 0)
					else
						label:SetPoint("TOPLEFT", image, "TOPRIGHT", 4, 0)
					end
					label:SetWidth(width - imagewidth - 4)
					height = max(image:GetHeight(), label:GetStringHeight())
				end
			else
				-- no image
				label:SetPoint("TOPLEFT")
				label:SetWidth(width)
				height = label:GetStringHeight()
			end

			-- avoid zero-height labels (they can be used as spacers)
			if not height or height == 0 then
				height = 1
			end

			self.resizing = true
			frame:SetHeight(height)
			frame.height = height
			self.resizing = nil
		end

		local function Control_OnEnter(frame)
			local obj = frame.obj
			if obj.tooltip ~= nil and obj.tooltip ~= "" then
				-- Through AnchorTooltip like every other tooltip here: the consumer's tooltipOwner, reported
				-- and falling back to the built-in placement if it raises (Peer Review a3b7d5e7), and the
				-- MINOR 42 raise above a TOOLTIP-strata panel. It called the owner bare before.
				-- And like showTooltip (Peer Review NEW-4 on 3028f298): put back whatever the last showing
				-- raised, and record who the tooltip went to, so the leave below never hides a tooltip
				-- another frame or addon has taken since.
				restoreTip()
				lib:AnchorTooltip(frame)
				if GameTooltip.GetOwner then frame._lagwTipHeldBy = GameTooltip:GetOwner() end
				-- multi-line tooltips: split on newlines
				local lines = { strsplit("\n", obj.tooltip) }
				if #lines > 0 then
					GameTooltip:SetText(lines[1], 1, 1, 1, 1, true)
					for i = 2, #lines do
						if lines[i] and lines[i] ~= "" then
							GameTooltip:AddLine(lines[i], 1, 1, 1, true)
						end
					end
				end
				GameTooltip:Show()
			end
		end

		local function Control_OnLeave(frame)
			lib:HideTooltip(frame)
		end

		-- The font has already followed (ScaledFont re-sizes in place); the image and the height
		-- computed from both have not.
		local function TLabel_OnScaleChanged(_, _, self)
			if self._imageW then self:SetImageSize(self._imageW, self._imageH) else UpdateImageAnchor(self) end
		end

		local methods = {
			["OnAcquire"] = function(self)
				-- flag stops constant size updates during setup
				self.resizing = true
				self:SetWidth(200)
				self:SetText()
				self:SetImage(nil)
				self:SetImageSize(16, 16)
				self:SetColor()
				self:SetFontObject()
				self:SetJustifyH("LEFT")
				self:SetJustifyV("TOP")
				-- AceGUI pools the label: the last owner's tooltip must not show on the next owner's hover
				-- (Peer Review R4 on dfd1e1a5).
				self.tooltip = nil
				self.resizing = nil
				UpdateImageAnchor(self)
			end,

			["OnWidthSet"] = function(self)
				UpdateImageAnchor(self)
			end,

			["SetText"] = function(self, text)
				self.label:SetText(text)
				UpdateImageAnchor(self)
			end,

			["SetColor"] = function(self, r, g, b)
				if not (r and g and b) then
					r, g, b = 1, 1, 1
				end
				self.label:SetVertexColor(r, g, b)
			end,

			["SetImage"] = function(self, path, ...)
				local image = self.image
				image:SetTexture(path)
				if image:GetTexture() then
					self.imageshown = true
					local n = select("#", ...)
					if n == 4 or n == 8 then
						image:SetTexCoord(...)
					else
						image:SetTexCoord(0, 1, 0, 1)
					end
				else
					self.imageshown = nil
				end
				UpdateImageAnchor(self)
			end,

			-- An explicit (path, height, flags) is taken literally, as a consumer that spells out a
			-- pixel height has asked for exactly that; it does not follow the scale.
			["SetFont"] = function(self, font, height, flags)
				self.label:SetFont(font, height, flags)
			end,

			-- Through ScaledFont, so the label follows the scale in place. This used to copy the
			-- base's (path, size, flags) into SetFont, which froze the size at the moment of the call.
			["SetFontObject"] = function(self, font)
				local base = font or GameFontHighlightSmall
				local scaled = lib:ScaledFont(base)
				if scaled then
					self.label:SetFontObject(scaled)
				else
					self.label:SetFont(base:GetFont())
				end
			end,

			-- Scale-1.0 sizes, kept so a scale change can re-apply them.
			["SetImageSize"] = function(self, width, height)
				self._imageW, self._imageH = width, height
				self.image:SetWidth(lib:ScaledSize(width))
				self.image:SetHeight(lib:ScaledSize(height))
				UpdateImageAnchor(self)
			end,

			["SetJustifyH"] = function(self, justifyH)
				self.label:SetJustifyH(justifyH)
			end,

			["SetJustifyV"] = function(self, justifyV)
				self.label:SetJustifyV(justifyV)
			end,

			["SetTooltip"] = function(self, tooltip)
				self.tooltip = tooltip
			end,
		}

		local function Constructor()
			local frame = CreateFrame("Frame", nil, UIParent)
			frame:Hide()
			frame:SetScript("OnEnter", Control_OnEnter)
			frame:SetScript("OnLeave", Control_OnLeave)

			frame.tooltip = ""

			local label = frame:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
			local image = frame:CreateTexture(nil, "BACKGROUND")

			local widget = {
				label = label,
				image = image,
				frame = frame,
				type  = Type,
			}
			for method, func in pairs(methods) do
				widget[method] = func
			end
			lib:OnScaleChanged(widget, TLabel_OnScaleChanged)

			return AceGUI:RegisterAsWidget(widget)
		end

		AceGUI:RegisterWidgetType(Type, Constructor, Version)
	end
end

-- ===========================================================================
-- Character counter -- a live "n / max" on any EditBox (Ultimate Guild Roster inbox 31133c51, item 2)
-- ===========================================================================
-- `W:AttachCharCounter(target[, opts])` -> the counter FontString. `target` is a raw EditBox (single- or
-- multi-line) or an AceGUI widget with an `.editbox` / `.editBox` (EditBox, MultiLineEditBox,
-- LAGW-SearchBox). The library has no multi-line box of its own, so this is the multi-line answer. The
-- counter reads "n / max", follows the box's SetMaxLetters (hooked, so a later SetMaxLetters re-draws it)
-- and every text change (typed or SetText), and HIDES while the max is 0 -- the client's "no limit". At
-- the limit it turns red. `W:DetachCharCounter(target)` removes it; an AceGUI widget target detaches by
-- itself on Release, so a pooled box never carries a counter into its next owner.
--
-- COUNTED THE WAY THE CLIENT COUNTS THE LIMIT: `GetNumLetters()` against `GetMaxLetters()`. That is the
-- pair Blizzard's own counters use -- `InputScrollFrame_OnTextChanged`
-- (Blizzard_SharedXML/SecureUIPanelTemplates.lua:142, `GetMaxLetters() - GetNumLetters()`) and the macro
-- frame's limit line (Blizzard_MacroUI.xml:121), both in the Classic Era tree -- so the counter and the
-- refusal of the next keystroke cannot disagree, whatever unit "letters" is. A box without GetNumLetters
-- falls back to strlenutf8, then the byte length.
--
-- opts (all optional):
--   parent                  what the FontString is created on (default: the widget's frame, or the box)
--   point, relativeTo, relPoint, x, y   its anchor. Default: an AceGUI widget's TOPRIGHT, on the label
--                           line; a raw box's TOPRIGHT, just above it (the counter's BOTTOMRIGHT, 2px up).
--   onUpdate(fs, visible, reserve)      after every redraw; `reserve` is the width of the widest text at
--                           this max ("max / max"), so a layout can make room without jittering per
--                           keystroke. LAGW-SearchBox uses it to shrink its box beside the counter.
-- Calling it again on the same box re-anchors and redraws the same counter.
-- luacheck: read globals strlenutf8
local function CharCounter_Count(eb)
	if eb.GetNumLetters then return eb:GetNumLetters() or 0 end
	local text = eb:GetText() or ""
	if strlenutf8 then return strlenutf8(text) end
	return #text
end

local function CharCounter_Update(eb)
	local rec = eb._lagwCounter
	if not rec then return end
	local fs = rec.fs
	local max = (eb.GetMaxLetters and eb:GetMaxLetters()) or 0
	local visible = max > 0
	local reserve = 0
	if visible then
		fs:SetFontObject(lib:ScaledFont("GameFontDisableSmall"))
		fs:SetText(max .. " / " .. max)
		reserve = math.ceil(fs:GetStringWidth() or 0)
		local n = CharCounter_Count(eb)
		fs:SetText(n .. " / " .. max)
		if n >= max then fs:SetTextColor(1, 0.3, 0.3) else fs:SetTextColor(0.6, 0.6, 0.6) end
		fs:Show()
	else
		fs:SetText("")
		fs:Hide()
	end
	if rec.onUpdate then safeCall(rec.onUpdate, fs, visible, reserve) end
end

local function CharCounter_OnScale(_, _, rec) CharCounter_Update(rec.eb) end

-- The box, and the AceGUI widget when the target is one. AceGUI's EditBox names its box `editbox`;
-- its MultiLineEditBox names it `editBox` (AceGUIWidget-MultiLineEditBox.lua, e.g. :60).
local function CharCounter_Resolve(target)
	if type(target) ~= "table" then return nil end
	if type(target.frame) == "table" then
		local eb = target.editbox or target.editBox
		if type(eb) == "table" then return eb, target end
	end
	return target, nil
end

function lib:AttachCharCounter(target, opts)
	local eb, widget = CharCounter_Resolve(target)
	if not (eb and eb.HookScript and eb.GetText) then return nil end
	opts = opts or {}
	local parent = opts.parent or (widget and widget.frame) or eb

	-- The two hooks go on ONCE per box and are inert while no counter is attached (`_lagwCounter` nil),
	-- which is what lets a pooled box carry them harmlessly.
	if not eb._lagwCounterHooked then
		eb._lagwCounterHooked = true
		eb:HookScript("OnTextChanged", CharCounter_Update)
		if hooksecurefunc and eb.SetMaxLetters then hooksecurefunc(eb, "SetMaxLetters", CharCounter_Update) end
	end

	local rec = eb._lagwCounter
	if not rec then
		local fs = eb._lagwCounterFS
		if not (fs and fs:GetParent() == parent) then
			if fs then fs:Hide() end
			fs = parent:CreateFontString(nil, "OVERLAY")
			fs:SetFontObject(self:ScaledFont("GameFontDisableSmall"))
			fs:SetJustifyH("RIGHT")
			eb._lagwCounterFS = fs
		end
		rec = { eb = eb, fs = fs }
		eb._lagwCounter = rec
		self:OnScaleChanged(rec, CharCounter_OnScale)
	end
	rec.onUpdate = opts.onUpdate

	local fs = rec.fs
	fs:ClearAllPoints()
	if opts.point then
		fs:SetPoint(opts.point, opts.relativeTo or eb, opts.relPoint or opts.point, opts.x or 0, opts.y or 0)
	elseif widget then
		fs:SetPoint("TOPRIGHT", widget.frame, "TOPRIGHT", 0, 0)
	else
		fs:SetPoint("BOTTOMRIGHT", eb, "TOPRIGHT", 0, 2)
	end

	if widget then
		self:OnWidgetRelease(widget, "lagw:charcounter", function(w) lib:DetachCharCounter(w) end)
	end
	CharCounter_Update(eb)
	return fs
end

--- Remove the counter `AttachCharCounter` put on `target` (a box or an AceGUI widget), now. Its
--- `onUpdate` hears one last `(fs, false, 0)` so a layout that made room gives it back.
function lib:DetachCharCounter(target)
	local eb, widget = CharCounter_Resolve(target)
	local rec = eb and eb._lagwCounter
	if not rec then return end
	eb._lagwCounter = nil
	self:OnScaleChanged(rec, nil)
	rec.fs:SetText("")
	rec.fs:Hide()
	-- Protected: a raise here used to skip the OnWidgetRelease removal below.
	if rec.onUpdate then safeCall(rec.onUpdate, rec.fs, false, 0) end
	if widget then self:OnWidgetRelease(widget, "lagw:charcounter", false) end
end

-- ===========================================================================
-- LAGW-SearchBox — CreateSearchBox as an AceGUI widget, for Flow / Table layouts (MINOR 35)
-- ===========================================================================
-- Requested by Questbook (inbox 293177a6, 2026-09-26). `CreateSearchBox` hands back a RAW frame for a
-- manual layout, so two consumers wrapped it as their own AceGUI type to drop it into a Flow row --
-- TOGBankClassic's `TOGBankSearchBox` and Questbook's `QuestbookSearchBox`, a copy of the first. This
-- is that wrapper, once, with the union of both copies' methods so either can switch without losing one.
--
--   local box = AceGUI:Create("LAGW-SearchBox")
--   box:SetWidth(200)
--   box:SetPlaceholder("Quest or zone")
--   box:SetCallback("OnTextChanged", function(widget, event, text) filter(text) end)
--   strip:AddChild(box)
--
-- The contract, the one both copies meet:
--   * SetText is PROGRAMMATIC and fires nothing, as AceGUI's EditBox:SetText fires nothing -- a tab
--     that writes its saved query back into the box on redraw must not loop.
--   * The player's TYPING fires OnTextChanged(text): the editbox's userInput path, hooked, not replaced,
--     so the template's own handler still runs the clear-X and the placeholder.
--   * The clear-X fires OnTextChanged("") from the button's own OnClick, because the template empties
--     the box with a programmatic SetText("") that the typing hook rightly ignores.
--   * SetPlaceholder(text); nil restores the template's "Search".
--   * OnEnter / OnLeave pass through, so a strip's hover tooltip works; OnEnterPressed(text) too.
--   * GetText; SetMaxLetters(n); SetDisabled(bool); SetFocus / ClearFocus / HasFocus.
--   * Released EMPTY and unfocused; every setting above is reset on acquire.
--   * SetShowCounter(bool) (Version 2, Ultimate Guild Roster inbox 31133c51): a live "n / max" at the
--     right of the widget through W:AttachCharCounter, following SetMaxLetters and every text change,
--     hidden while the max is 0. The box shrinks beside it, by the width of "max / max", so the text never
--     runs under it and does not jitter as the count grows. `widget.counter` is the FontString while shown.
--     Off on acquire. Feature-detect with `AceGUI:GetWidgetVersion("LAGW-SearchBox") >= 2`.
-- Height is a scale-1.0 24 and follows the UI scale, as the box's own font does (CreateSearchBox,
-- MINOR 29). Feature-detect with `AceGUI:GetWidgetVersion("LAGW-SearchBox")`, or `LibStub.minors`.
do
	-- 1: a new type with no competing copy under this name.
	-- 2: SetShowCounter -- a counter FontString on the frame, and the box re-anchored beside it.
	local Type, Version = "LAGW-SearchBox", 2
	local HEIGHT, WIDTH = 24, 200
	local AceGUI = LibStub("AceGUI-3.0", true)
	if AceGUI and (AceGUI:GetWidgetVersion(Type) or 0) < Version then
		local pairs = pairs
		local CreateFrame, UIParent = CreateFrame, UIParent

		-- AceGUI's SetHeight does not re-run the parent's layout, and a strip centres on this height.
		local function SearchWidget_OnScaleChanged(_, _, self)
			self:SetHeight(lib:ScaledSize(HEIGHT))
			local parent = self.parent
			if parent and parent.DoLayout then parent:DoLayout() end
		end

		local methods = {
			["OnAcquire"] = function(self)
				self:SetHeight(lib:ScaledSize(HEIGHT))
				self:SetWidth(WIDTH)
				self:SetDisabled(false)
				self:SetText("")
				self:SetPlaceholder(nil)
				self:SetMaxLetters(0)
				self:SetShowCounter(false)
			end,

			["SetShowCounter"] = function(self, show)
				if show then
					self.counter = lib:AttachCharCounter(self.editbox, {
						parent = self.frame, point = "RIGHT", relativeTo = self.frame, relPoint = "RIGHT", x = -2,
						onUpdate = self._counterLayout,
					})
				else
					lib:DetachCharCounter(self.editbox)
					self.counter = nil
				end
			end,

			["OnRelease"] = function(self)
				self:SetText("")
				self.editbox:ClearFocus()
			end,

			["SetText"] = function(self, text)
				self._settingText = true
				self.editbox:SetText(text or "")
				self._settingText = nil
			end,

			["GetText"] = function(self)
				return self.editbox:GetText() or ""
			end,

			-- The client's own localised `SEARCH` global is the template's default wording.
			["SetPlaceholder"] = function(self, text)
				local ins = self.editbox.Instructions
				if ins then ins:SetText(text or rawget(_G, "SEARCH") or "Search") end
			end,

			["SetMaxLetters"] = function(self, n)
				self.editbox:SetMaxLetters(n or 0)
			end,

			["SetDisabled"] = function(self, disabled)
				self.disabled = disabled
				self.editbox:EnableMouse(not disabled)
				if disabled then self.editbox:ClearFocus() end
			end,

			["SetFocus"] = function(self) self.editbox:SetFocus() end,
			["ClearFocus"] = function(self) self.editbox:ClearFocus() end,
			["HasFocus"] = function(self) return self.editbox:HasFocus() end,
		}

		local function Constructor()
			local frame = CreateFrame("Frame", nil, UIParent)
			frame:Hide()

			local editbox = lib:CreateSearchBox(frame, {})
			-- The template draws its own art; a 2px inset keeps two boxes side by side from touching.
			editbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -1)
			editbox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 1)

			local widget = {
				frame   = frame,
				editbox = editbox,
				type    = Type,
			}
			for method, func in pairs(methods) do
				widget[method] = func
			end
			-- The counter's room: the box ends 4px short of the widest "max / max", or at the 2px inset.
			widget._counterLayout = function(_, visible, reserve)
				editbox:ClearAllPoints()
				editbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -1)
				editbox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", visible and -(2 + reserve + 4) or -2, 1)
			end

			editbox:HookScript("OnTextChanged", function(eb, userInput)
				if widget._settingText or not userInput then return end
				widget:Fire("OnTextChanged", eb:GetText() or "")
			end)
			if editbox.clearButton and editbox.clearButton.HookScript then
				editbox.clearButton:HookScript("OnClick", function()
					widget:Fire("OnTextChanged", editbox:GetText() or "")
				end)
			end
			editbox:HookScript("OnEnterPressed", function(eb)
				widget:Fire("OnEnterPressed", eb:GetText() or "")
			end)
			editbox:HookScript("OnEnter", function() widget:Fire("OnEnter") end)
			editbox:HookScript("OnLeave", function() widget:Fire("OnLeave") end)

			lib:OnScaleChanged(widget, SearchWidget_OnScaleChanged)
			return AceGUI:RegisterAsWidget(widget)
		end

		AceGUI:RegisterWidgetType(Type, Constructor, Version)
	end
end

-- ===========================================================================
-- LAGW-Stepper — CreateStepper as an AceGUI widget (MINOR 36, TOGProfessionMaster inbox ea8db903)
-- ===========================================================================
--   local q = AceGUI:Create("LAGW-Stepper")
--   q:SetBounds(1, function() return craftable() end)
--   q:SetMaxButton(true)
--   q:SetCallback("OnValueChanged", function(widget, event, value) ... end)
--
-- Fires OnValueChanged(value) for the player's changes only; SetValue is silent. Everything is reset on
-- acquire (min 0, no max, step 1, value 0, no MAX button, enabled), and the box is unfocused on release,
-- so a pooled stepper carries nothing to the next addon.
do
	local Type, Version = "LAGW-Stepper", 1   -- 1: a new type, no competing copy under this name
	local AceGUI = LibStub("AceGUI-3.0", true)
	if AceGUI and (AceGUI:GetWidgetVersion(Type) or 0) < Version then
		local methods = {
			["OnAcquire"] = function(self)
				self.stepper:SetDisabled(false)
				self.stepper:SetStep(1)
				self.stepper:SetBounds(0, nil)
				self.stepper:SetValue(0)
				self:SetMaxButton(false)
			end,
			["OnRelease"] = function(self)
				self.stepper.edit:ClearFocus()
			end,
			["SetValue"] = function(self, v) self.stepper:SetValue(v) end,
			["GetValue"] = function(self) return self.stepper:GetValue() end,
			["SetBounds"] = function(self, mn, mx) self.stepper:SetBounds(mn, mx) end,
			["SetStep"] = function(self, n) self.stepper:SetStep(n) end,
			["SetDisabled"] = function(self, off)
				self.disabled = off
				self.stepper:SetDisabled(off)
			end,
			["Refresh"] = function(self) self.stepper:Refresh() end,
			-- The MAX button is built with every stepper and shown only when asked, so a pooled widget can
			-- switch it without being rebuilt; the widget's width follows.
			["SetMaxButton"] = function(self, on)
				local st = self.stepper
				st.maxButton:SetShown(on and true or false)
				st._maxShown = on and true or false
				self:_fit()
				st:Refresh()
			end,
			["_fit"] = function(self)
				local st = self.stepper
				st:_layout()   -- first, whichever scale listener ran first: the width is read from it
				local w = st:GetWidth()
				if not st._maxShown then w = w - lib:ScaledSize(STEPPER_MAX_W) - lib:ScaledSize(STEPPER_GAP) end
				self:SetWidth(w)
				self:SetHeight(st:GetHeight())
			end,
		}

		local function Constructor()
			local frame = CreateFrame("Frame", nil, UIParent)
			frame:Hide()
			local widget = { frame = frame, type = Type }
			local st = lib:CreateStepper(frame, {
				maxButton = true,
				onValueChanged = function(v) widget:Fire("OnValueChanged", v) end,
			})
			st:SetPoint("LEFT", frame, "LEFT", 0, 0)
			widget.stepper = st
			for method, func in pairs(methods) do widget[method] = func end
			lib:OnScaleChanged(widget, function(_, _, w) w:_fit() end)
			return AceGUI:RegisterAsWidget(widget)
		end

		AceGUI:RegisterWidgetType(Type, Constructor, Version)
	end
end

-- ===========================================================================
-- LAGW-CopyField — ShowCopyBox's box, inline, as an AceGUI widget (MINOR 38, TOGTools inbox 513d5779)
-- ===========================================================================
--   local f = AceGUI:Create("LAGW-CopyField")
--   f:SetLabel("Discord")                  -- optional; no label takes no height
--   f:SetText("https://discord.gg/...")
--   f:SetFullWidth(true)                   -- or SetWidth; works in List and Flow
--
-- The box follows ShowCopyBox's rules exactly: the copy glyph (COPY_ICON) at the field's LEFT +1,-1 on
-- OVERLAY, 14px scaled, the text inset 20 to clear it, the magnifier's tint (white while focused or
-- holding text, 0.6 grey otherwise); READ-ONLY -- a user edit is put back and selected again; the whole
-- text selected on focus and on mouse up; long text scrolls inside the box. Enter and Escape drop focus.
-- No callbacks fire: there is nothing for a consumer to hear.
--
-- Geometry is AceGUI's EditBox's (AceGUIWidget-EditBox.lua): a 19px box 6px in from the left, a
-- GameFontNormalSmall label on top, 44px tall with a label and 26 without, scaled. Released with no text
-- and no label, unfocused. The glyph and the read-only guard belong to this widget type's own frames, so
-- the pool only ever hands them to another CopyField. If the glyph file cannot be set, no glyph is drawn
-- and the text is not inset. Feature-detect with `AceGUI:GetWidgetVersion("LAGW-CopyField")`.
do
	-- 2: the label has its font from construction. 1 raised "Font not set" on every Create in game;
	-- TOGTools only creates it at >= 2, and the bump makes this copy win over a 1 already registered.
	local Type, Version = "LAGW-CopyField", 2
	local AceGUI = LibStub("AceGUI-3.0", true)
	if AceGUI and (AceGUI:GetWidgetVersion(Type) or 0) < Version then
		local BOX_H, LABEL_H, WITH_LABEL_H, BARE_H = 19, 18, 44, 26

		local function tint(self)
			local icon = self.glyph
			if not icon then return end
			local eb = self.editbox
			local v = (eb:HasFocus() or (self.text or "") ~= "") and 1.0 or 0.6
			icon:SetVertexColor(v, v, v)
		end

		local function layout(self)
			local S = function(px) return lib:ScaledSize(px) end
			local eb = self.editbox
			eb:SetHeight(S(BOX_H))
			if self.glyph then
				self.glyph:SetSize(S(COPY_GLYPH), S(COPY_GLYPH))
				eb:SetTextInsets(S(COPY_INSET), 0, 3, 3)
			else
				eb:SetTextInsets(0, 0, 3, 3)
			end
			self.label:SetFontObject(lib:ScaledFont("GameFontNormalSmall"))
			self.label:SetHeight(S(LABEL_H))
			local hasLabel = (self.label:GetText() or "") ~= ""
			self.label:SetShown(hasLabel)
			self:SetHeight(S(hasLabel and WITH_LABEL_H or BARE_H))
			self.alignoffset = hasLabel and S(30) or S(12)
		end

		local function EditBox_OnTextChanged(eb, userInput)
			local self = eb.obj
			if not userInput then return end
			if eb:GetText() ~= (self.text or "") then eb:SetText(self.text or "") end
			eb:HighlightText()
		end

		local function EditBox_SelectAll(eb)
			eb:HighlightText()
			tint(eb.obj)
		end

		local methods = {
			["OnAcquire"] = function(self)
				self:SetWidth(200)
				self.label:SetText("")
				self:SetText("")
				layout(self)
			end,

			["OnRelease"] = function(self)
				self.editbox:ClearFocus()
				self.text = nil
				self.editbox:SetText("")
				self.label:SetText("")
			end,

			["SetText"] = function(self, text)
				if text == nil then text = "" end
				self.text = tostring(text)
				self.editbox:SetText(self.text)
				self.editbox:SetCursorPosition(0)
				tint(self)
			end,

			["GetText"] = function(self) return self.text or "" end,

			["SetLabel"] = function(self, text)
				self.label:SetText(text or "")
				layout(self)
			end,
		}

		local function Constructor()
			local frame = CreateFrame("Frame", nil, UIParent)
			frame:Hide()

			-- The font is set HERE, before anything calls SetText: the client refuses SetText on a
			-- FontString with no font ("FontString:SetText(): Font not set"). Version 1 set it only in
			-- layout(), which OnAcquire reached after its SetText(""), and every Create raised in game
			-- (TOGTools peer review 63629c29, 2026-09-29).
			local label = frame:CreateFontString(nil, "OVERLAY")
			label:SetFontObject(lib:ScaledFont("GameFontNormalSmall"))
			label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -2)
			label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -2)
			label:SetJustifyH("LEFT")

			local eb = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
			lib:_trackFocus(eb)
			eb:SetAutoFocus(false)
			if eb.SetFontObject then eb:SetFontObject(lib:ScaledFont("ChatFontNormal")) end
			eb:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 0)
			eb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
			eb:HookScript("OnTextChanged", EditBox_OnTextChanged)
			eb:HookScript("OnEditFocusGained", EditBox_SelectAll)
			eb:HookScript("OnMouseUp", EditBox_SelectAll)
			eb:HookScript("OnEditFocusLost", function(box) tint(box.obj) end)
			eb:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
			eb:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

			-- The glyph, exactly as CopyBox_ShowGlyph draws it; nil when the file cannot be set.
			local tex = eb:CreateTexture(nil, "OVERLAY")
			tex:SetPoint("LEFT", eb, "LEFT", 1, -1)
			local ok = tex:SetTexture(COPY_ICON)
			local icon = (ok and tex:GetTexture()) and tex or nil
			if not icon then tex:Hide() end

			local widget = { frame = frame, label = label, editbox = eb, glyph = icon, type = Type }
			eb.obj = widget
			for method, func in pairs(methods) do widget[method] = func end
			lib:OnScaleChanged(widget, function(_, _, w)
				if w.editbox.SetFontObject then w.editbox:SetFontObject(lib:ScaledFont("ChatFontNormal")) end
				layout(w)
				local parent = w.parent
				if parent and parent.DoLayout then parent:DoLayout() end
			end)
			return AceGUI:RegisterAsWidget(widget)
		end

		AceGUI:RegisterWidgetType(Type, Constructor, Version)
	end
end

-- ===========================================================================
-- LAGW-Chip — one on/off pill button, sized to its label (MINOR 40, Grouper inbox c98a1eab)
-- ===========================================================================
-- Grouper's operator, 2026-10-02: "ask widgets to add a toggle chip, i think it could be good". A filter
-- that is a multi-select dropdown reads "Dungeon, Raid,..." when closed and costs open-click-close per
-- change; a row of chips shows the whole state and changes it in one click.
--
--   local chip = AceGUI:Create("LAGW-Chip")
--   chip:SetText("Dungeon")
--   chip:SetValue(true)
--   chip:SetCallback("OnValueChanged", function(widget, event, value) ... end)
--   W:StripAdd(strip, chip)                 -- or any container; W:AddChips builds a row of them
--
-- Like AceGUI's CheckBox: a CLICK toggles and fires OnValueChanged(value); SetValue is silent. A disabled
-- chip ignores clicks and is drawn dimmed. OnEnter / OnLeave pass through, and the frame is a Button, so
-- W:AttachWidgetTooltip(chip, ...) answers on it.
--
-- Looks: ON is the library accent -- a tinted fill, an accent border and white text; OFF is the dark fill
-- and grey border of CreateDropdownBox with grey text. Hover adds the same ButtonHilight. Height is a
-- scale-1.0 22, the width is the label plus 10 a side, and both follow the UI scale with the font.
-- Everything is reset on acquire (no text, off, enabled). Feature-detect with
-- `AceGUI:GetWidgetVersion("LAGW-Chip")` or `if W.AddChips then`.
--
-- AS AN AceConfig-3.0 TOGGLE (Version 2, Ultimate Guild Roster inbox 20d63ff4): `dialogControl =
-- "LAGW-Chip"` on a `type = "toggle"` option. AceConfigDialog-3.0.lua:1197-1219 calls SetLabel,
-- SetTriState, SetValue, SetCallback("OnValueChanged"), SetDescription (descStyle "inline" only) and
-- SetImage (an `image` only); its common init (:1441-1465) then sets the width and SetDisabled. So:
--   * SetLabel(text) is SetText. SetImage / SetImageSize are accepted and ignored -- a chip has no icon.
--   * SetTriState(bool) is accepted, but a chip is TWO-state: a nil (the third state) draws as OFF, and a
--     click from it goes to ON. GetValue stays a boolean.
--   * SetDescription(text) becomes the chip's hover tooltip (title = the label), drawn through
--     ShowTooltip, so `lib.config.tooltipOwner` places it. nil or "" removes it; release clears it.
--     With the default descStyle AceConfigDialog draws `desc` in its own tooltip from OnEnter, which
--     the chip passes through -- SetDescription is not called then, so the two never both show.
--   * WIDTH: AceConfigDialog gives EVERY control a width, 170px (its `width_multiplier`, :49) when the
--     option names none. A chip in that mode (entered by SetTriState, which only a CheckBox-shaped caller
--     sends) treats exactly that default as "no width" and stays sized to its label, so a row of chips
--     packs in the Flow group. Any OTHER width -- "half", "double", a number other than 1, "relative",
--     "full" -- is the option author's explicit choice and is honoured. `width = 1` / "normal" therefore
--     reads as label-sized: that is the one value this cannot tell from the default.
lib.CHIP_HEIGHT, lib.CHIP_PAD = 22, 10
do
	-- 2: the AceConfig toggle methods above, the description tooltip, and the label-sized width mode.
	local Type, Version = "LAGW-Chip", 2
	-- AceConfigDialog-3.0.lua:49, `local width_multiplier = 170`: the width it hands a control that asked
	-- for none (:1456).
	local ACD_DEFAULT_WIDTH = 170
	local AceGUI = LibStub("AceGUI-3.0", true)
	if AceGUI and (AceGUI:GetWidgetVersion(Type) or 0) < Version then
		local function paint(self)
			local f, fs = self.frame, self.text
			if self.value then
				local r, g, b = lib:AccentRGB()
				f:SetBackdropColor(r * 0.45, g * 0.45, b * 0.45, 0.9)
				f:SetBackdropBorderColor(r, g, b)
				fs:SetTextColor(1, 1, 1)
			else
				f:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
				f:SetBackdropBorderColor(0.45, 0.45, 0.45)
				fs:SetTextColor(0.6, 0.6, 0.6)
			end
			f:SetAlpha(self.disabled and 0.5 or 1)
		end

		-- AceGUI's WidgetBase.SetWidth (AceGUI-3.0.lua:307), written out because the chip's own SetWidth
		-- (below) has to be able to reach it without going through itself.
		local function baseSetWidth(self, w)
			self.frame:SetWidth(w)
			self.frame.width = w
		end

		-- AceGUI's SetWidth/SetHeight do not re-run the parent's layout, and a strip wraps on this width.
		-- A width set explicitly through SetWidth (`_fixedWidth`) survives a relabel: an AceConfig option's
		-- "double", or a consumer's own SetWidth, must not shrink to the label on a language switch (Peer
		-- Review on audit 509928c3). Only the label-sized chip follows its text.
		local function fit(self)
			self.text:SetFontObject(lib:ScaledFont("GameFontHighlightSmall"))
			local w = self._fixedWidth
				or (math.ceil(self.text:GetStringWidth() or 0) + 2 * lib:ScaledSize(lib.CHIP_PAD))
			baseSetWidth(self, w)
			self:SetHeight(lib:ScaledSize(lib.CHIP_HEIGHT))
			local parent = self.parent
			if parent and parent.DoLayout then parent:DoLayout() end
		end

		-- The description tooltip (Version 2): drawn after the OnEnter dispatch, so a consumer's own
		-- callback (AceConfigDialog's included) has run first; put away only if the chip drew it.
		local function Chip_OnEnter(frame)
			local self = frame.obj
			self:Fire("OnEnter")
			if self.desc then
				self._descShown = lib:ShowTooltip(frame, self.text:GetText(), self.desc) or nil
			end
		end
		local function Chip_OnLeave(frame)
			local self = frame.obj
			self:Fire("OnLeave")
			if self._descShown then
				self._descShown = nil
				lib:HideTooltip(frame)
			end
		end

		local function Chip_OnClick(frame)
			local self = frame.obj
			if self.disabled then return end
			self.value = not self.value
			if PlaySound and SOUNDKIT then
				PlaySound(self.value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			end
			paint(self)
			self:Fire("OnValueChanged", self.value)
		end

		local methods = {
			["OnAcquire"] = function(self)
				self.value, self.disabled = false, false
				self.desc, self.tristate, self.labelSized, self._descShown = nil, nil, nil, nil
				self._fixedWidth = nil
				self.frame:Enable()
				self.text:SetText("")
				fit(self)
				paint(self)
			end,
			-- A pooled chip must not take a description tooltip -- or one it is still showing -- to its
			-- next owner.
			["OnRelease"] = function(self)
				if self._descShown then lib:HideTooltip(self.frame) end
				self.desc, self.tristate, self.labelSized, self._descShown = nil, nil, nil, nil
				self._fixedWidth = nil
			end,
			["SetText"] = function(self, text)
				self.text:SetText(text or "")
				fit(self)
			end,
			["GetText"] = function(self) return self.text:GetText() or "" end,
			-- AceConfig-3.0 toggle surface (Version 2; see the header). SetLabel IS SetText.
			["SetLabel"] = function(self, text) self:SetText(text) end,
			["SetTriState"] = function(self, enabled)
				self.tristate = enabled and true or nil
				self.labelSized = true
			end,
			["SetDescription"] = function(self, desc)
				if desc == "" then desc = nil end
				self.desc = desc and tostring(desc) or nil
			end,
			["SetImage"] = function() end,
			["SetImageSize"] = function() end,
			-- WidgetBase.SetWidth, except that in the AceConfig mode its default width means "no width".
			-- The Flow layout also calls SetWidth for a "fill" or "relative" child (AceGUI-3.0.lua:762,
			-- :775), and a row that happens to be 170px wide must not read as the default.
			["SetWidth"] = function(self, width)
				if self.labelSized and width == ACD_DEFAULT_WIDTH
					and self.width ~= "fill" and self.width ~= "relative" then
					self._fixedWidth = nil
					fit(self)
					return
				end
				-- A fill / relative width is the layout's, re-handed on every pass; recording it would leave a
				-- stale row width behind once full width is turned off (Peer Review, b555ce7e).
				if self.width == "fill" or self.width == "relative" then
					self._fixedWidth = nil
				else
					self._fixedWidth = width
				end
				baseSetWidth(self, width)
			end,
			["SetValue"] = function(self, value)
				self.value = value and true or false
				paint(self)
			end,
			["GetValue"] = function(self) return self.value end,
			["SetDisabled"] = function(self, disabled)
				self.disabled = disabled and true or false
				if self.disabled then self.frame:Disable() else self.frame:Enable() end
				paint(self)
			end,
		}

		local function Constructor()
			local frame = CreateFrame("Button", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
			frame:Hide()
			frame:SetBackdrop({
				bgFile   = "Interface\\Buttons\\WHITE8x8",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
			frame:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			-- The font before any SetText: the client refuses SetText on a FontString with no font
			-- (LAGW-CopyField version 1 raised "Font not set" on every Create for exactly this).
			local text = frame:CreateFontString(nil, "OVERLAY")
			text:SetFontObject(lib:ScaledFont("GameFontHighlightSmall"))
			text:SetPoint("CENTER", frame, "CENTER", 0, 0)
			text:SetWordWrap(false)

			local widget = { frame = frame, text = text, type = Type }
			frame.obj = widget
			for method, func in pairs(methods) do widget[method] = func end
			frame:SetScript("OnClick", Chip_OnClick)
			frame:SetScript("OnEnter", Chip_OnEnter)
			frame:SetScript("OnLeave", Chip_OnLeave)
			-- A disabled chip still shows its tooltip; feature-detected as AttachWidgetTooltip does.
			if frame.SetMotionScriptsWhileDisabled then frame:SetMotionScriptsWhileDisabled(true) end
			lib:OnScaleChanged(widget, function(_, _, w) fit(w) end)
			return AceGUI:RegisterAsWidget(widget)
		end

		AceGUI:RegisterWidgetType(Type, Constructor, Version)
	end
end

-- ===========================================================================
-- LAGW-TabStrip — a row of runtime tabs that scrolls with < and > (MINOR 40, Dibs inbox cb965300)
-- ===========================================================================
-- Dibs' operator, 2026-09-30: "all you have to do is have < and > arrows at either side of the tabs so
-- you can scroll back and forth between tabs" -- one tab per item being rolled, created as items arrive,
-- so the count is not bounded by the window's width.
--
--   local tabs = AceGUI:Create("LAGW-TabStrip")
--   tabs:SetFullWidth(true)
--   tabs:SetCallback("OnTabSelected", function(widget, event, value) showRolls(value) end)
--   tabs:AddTab(itemID, itemName)          -- appended; a value already present is re-labelled
--   tabs:SelectTab(itemID)                 -- silent; scrolls the tab into view
--   tabs:RemoveTab(itemID); tabs:ClearTabs()
--
-- THE STRIP ONLY: no content pane. The consumer draws what a tab shows, on OnTabSelected(value), which
-- fires for a PLAYER's click only -- SelectTab from code is silent, as SetValue is on every widget here,
-- so a consumer that selects in its own redraw cannot loop. Clicking the selected tab fires nothing.
--
-- Each tab is its label plus 10 a side, capped at SetMaxTabWidth (scale-1.0, default 140): a longer label
-- is cut short and the full label shows as a tooltip on hover. When the tabs do not all fit, < sits at the
-- left end and > at the right end and each scrolls one tab; < is disabled at the first tab, > once the last
-- tab is in view. When they fit, there are no arrows. Removing the selected tab selects nothing.
-- Height 22, arrows 20 wide, gaps 2: scale-1.0, following the UI scale. Released with no tabs.
-- Feature-detect with `AceGUI:GetWidgetVersion("LAGW-TabStrip")`.
lib.TABSTRIP_HEIGHT, lib.TABSTRIP_ARROW, lib.TABSTRIP_GAP, lib.TABSTRIP_MAX_TAB = 22, 20, 2, 140
do
	local Type, Version = "LAGW-TabStrip", 1   -- 1: a new type, no competing copy under this name
	local AceGUI = LibStub("AceGUI-3.0", true)
	if AceGUI and (AceGUI:GetWidgetVersion(Type) or 0) < Version then
		local TAB_BACKDROP = {
			bgFile   = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
		}

		local function paintTab(btn, selected)
			if selected then
				local r, g, b = lib:AccentRGB()
				btn:SetBackdropColor(r * 0.45, g * 0.45, b * 0.45, 0.9)
				btn:SetBackdropBorderColor(r, g, b)
				btn.label:SetTextColor(1, 1, 1)
			else
				btn:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
				btn:SetBackdropBorderColor(0.45, 0.45, 0.45)
				btn.label:SetTextColor(0.6, 0.6, 0.6)
			end
		end

		local layout   -- defined below; the buttons' scripts call it

		local function Tab_OnClick(btn)
			local self = btn.strip
			local tab = btn.tab
			if not tab or tab.value == self.selected then return end
			if PlaySound then PlaySound(841) end   -- SOUNDKIT.IG_CHARACTER_INFO_TAB, as AceGUI's TabGroup
			self.selected = tab.value
			layout(self)
			self:Fire("OnTabSelected", tab.value)
		end

		local function Tab_OnEnter(btn)
			local tab = btn.tab
			if tab and btn.truncated then lib:ShowTooltip(btn, tab.text) end
		end

		local function Arrow_OnClick(btn)
			local self = btn.strip
			self.first = math.max(1, math.min(#self.tabs, self.first + btn.step))
			layout(self)
		end

		local function makeArrow(self, text, step)
			local b = CreateFrame("Button", nil, self.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
			b:SetBackdrop(TAB_BACKDROP)
			b:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
			b:SetBackdropBorderColor(0.45, 0.45, 0.45)
			b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			local fs = b:CreateFontString(nil, "OVERLAY")
			fs:SetFontObject(lib:ScaledFont("GameFontHighlightSmall"))
			fs:SetPoint("CENTER", b, "CENTER", 0, 0)
			fs:SetText(text)
			b.label, b.strip, b.step = fs, self, step
			b:SetScript("OnClick", Arrow_OnClick)
			b:Hide()
			return b
		end

		-- One button per tab slot, made on demand and kept for the widget's life (they belong to this
		-- widget type's frame, so the pool only ever hands them to another tab strip).
		local function buttonFor(self, i)
			local b = self.buttons[i]
			if b then return b end
			b = CreateFrame("Button", nil, self.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
			b:SetBackdrop(TAB_BACKDROP)
			b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			local fs = b:CreateFontString(nil, "OVERLAY")
			fs:SetFontObject(lib:ScaledFont("GameFontHighlightSmall"))
			fs:SetWordWrap(false)
			b.label, b.strip = fs, self
			b:SetScript("OnClick", Tab_OnClick)
			b:SetScript("OnEnter", Tab_OnEnter)
			b:SetScript("OnLeave", function(btn) lib:HideTooltip(btn) end)
			self.buttons[i] = b
			return b
		end

		local function indexOf(self, value)
			for i, tab in ipairs(self.tabs) do
				if tab.value == value then return i end
			end
		end

		-- The width each tab wants: its label plus the padding, capped. Measured on a scratch FontString
		-- with no width set, so a label cut short by its button still reports its whole width.
		local function tabWidth(self, tab)
			local m = self.measure
			m:SetFontObject(lib:ScaledFont("GameFontHighlightSmall"))
			m:SetText(tab.text)
			local natural = math.ceil(m:GetStringWidth() or 0) + 2 * lib:ScaledSize(lib.CHIP_PAD)
			return math.min(natural, lib:ScaledSize(self.maxTab)), natural
		end

		-- Lay the tabs out from `self.first`. `reveal` (an index) scrolls first so that tab is in view.
		layout = function(self, reveal)
			local S = function(px) return lib:ScaledSize(px) end
			local h, gap, arrowW = S(lib.TABSTRIP_HEIGHT), S(lib.TABSTRIP_GAP), S(lib.TABSTRIP_ARROW)
			local pad = S(lib.CHIP_PAD)
			local avail = self.frame:GetWidth() or 0
			local n = #self.tabs
			local widths, naturals, total = {}, {}, 0
			for i, tab in ipairs(self.tabs) do
				widths[i], naturals[i] = tabWidth(self, tab)
				total = total + widths[i] + (i > 1 and gap or 0)
			end
			local overflow = avail > 0 and total > avail
			local left, inner = 0, avail
			if overflow then
				left = arrowW + gap
				inner = avail - 2 * (arrowW + gap)
			else
				self.first = 1
			end
			self.first = math.max(1, math.min(self.first or 1, math.max(n, 1)))

			-- The last tab that fits when starting at `first`; at least `first` itself.
			local function lastFrom(first)
				local x, last = 0, first
				for i = first, n do
					local w = widths[i]
					if i > first and x + w > inner then break end
					last, x = i, x + w + gap
				end
				return last
			end
			if overflow and reveal then
				if reveal < self.first then self.first = reveal end
				while lastFrom(self.first) < reveal and self.first < reveal do self.first = self.first + 1 end
			end
			local last = (n > 0) and (overflow and lastFrom(self.first) or n) or 0

			local x = left
			for i = 1, math.max(n, #self.buttons) do
				local b = (i <= n) and buttonFor(self, i) or self.buttons[i]
				local tab = self.tabs[i]
				if tab and i >= self.first and i <= last then
					local w = widths[i]
					if overflow and w > inner then w = math.max(inner, 0) end
					b.tab = tab
					b.label:SetFontObject(lib:ScaledFont("GameFontHighlightSmall"))
					b.label:ClearAllPoints()
					b.label:SetPoint("LEFT", b, "LEFT", pad, 0)
					b.label:SetPoint("RIGHT", b, "RIGHT", -pad, 0)
					b.label:SetText(tab.text)
					b.truncated = naturals[i] > w
					b:SetSize(w, h)
					b:ClearAllPoints()
					b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, 0)
					paintTab(b, tab.value == self.selected)
					b:Show()
					x = x + w + gap
				elseif b then
					b.tab = nil
					b:Hide()
				end
			end

			for _, a in ipairs({ self.prev, self.next }) do
				a:SetSize(arrowW, h)
				a.label:SetFontObject(lib:ScaledFont("GameFontHighlightSmall"))
				a:SetShown(overflow)
			end
			self.prev:ClearAllPoints()
			self.prev:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
			self.next:ClearAllPoints()
			self.next:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0)
			local canBack, canOn = self.first > 1, last < n
			if canBack then self.prev:Enable() else self.prev:Disable() end
			if canOn then self.next:Enable() else self.next:Disable() end
			self.prev:SetAlpha(canBack and 1 or 0.4)
			self.next:SetAlpha(canOn and 1 or 0.4)
			self.lastShown = last
		end

		local methods = {
			["OnAcquire"] = function(self)
				self.maxTab = lib.TABSTRIP_MAX_TAB
				self:SetHeight(lib:ScaledSize(lib.TABSTRIP_HEIGHT))
				self:SetWidth(300)
				self:ClearTabs()
			end,
			["OnRelease"] = function(self)
				self:ClearTabs()
			end,
			["OnWidthSet"] = function(self) layout(self) end,

			["AddTab"] = function(self, value, text)
				local i = indexOf(self, value)
				if i then
					self.tabs[i].text = tostring(text or value)
				else
					self.tabs[#self.tabs + 1] = { value = value, text = tostring(text or value) }
				end
				layout(self)
			end,
			["SetTabText"] = function(self, value, text)
				local i = indexOf(self, value)
				if not i then return false end
				self.tabs[i].text = tostring(text or value)
				layout(self)
				return true
			end,
			["RemoveTab"] = function(self, value)
				local i = indexOf(self, value)
				if not i then return false end
				table.remove(self.tabs, i)
				if self.selected == value then self.selected = nil end
				if self.first > i then self.first = self.first - 1 end
				layout(self)
				return true
			end,
			["ClearTabs"] = function(self)
				self.tabs, self.selected, self.first = {}, nil, 1
				layout(self)
			end,
			["SelectTab"] = function(self, value)
				local i = indexOf(self, value)
				if not i then return false end
				self.selected = value
				layout(self, i)
				return true
			end,
			["GetSelected"] = function(self) return self.selected end,
			["GetTabs"] = function(self)
				local out = {}
				for i, tab in ipairs(self.tabs) do out[i] = tab.value end
				return out
			end,
			["SetMaxTabWidth"] = function(self, px)
				self.maxTab = tonumber(px) or lib.TABSTRIP_MAX_TAB
				layout(self)
			end,
			-- The first and last tab indexes in view, for a consumer's own "n more" hint.
			["GetVisibleRange"] = function(self) return self.first, self.lastShown or 0 end,
		}

		local function Constructor()
			local frame = CreateFrame("Frame", nil, UIParent)
			frame:Hide()
			local widget = { frame = frame, type = Type, tabs = {}, buttons = {}, first = 1,
				maxTab = lib.TABSTRIP_MAX_TAB }
			widget.measure = frame:CreateFontString(nil, "OVERLAY")
			widget.measure:SetFontObject(lib:ScaledFont("GameFontHighlightSmall"))
			widget.measure:Hide()
			widget.prev = makeArrow(widget, "<", -1)
			widget.next = makeArrow(widget, ">", 1)
			for method, func in pairs(methods) do widget[method] = func end
			lib:OnScaleChanged(widget, function(_, _, w)
				w:SetHeight(lib:ScaledSize(lib.TABSTRIP_HEIGHT))
				layout(w)
				local parent = w.parent
				if parent and parent.DoLayout then parent:DoLayout() end
			end)
			return AceGUI:RegisterAsWidget(widget)
		end

		AceGUI:RegisterWidgetType(Type, Constructor, Version)
	end
end

-- ===========================================================================
-- LAGW-Strip — a row of captioned controls on one caption line and one centre line (MINOR 35)
-- ===========================================================================
-- Requested by Questbook (inbox c2be4737, 2026-09-26), from its FilterStrip.lua. The operator's words:
-- "strip layout is one of the more fidgety things, and having it done once and sharable is desirable."
--
-- AceGUI's Flow cannot line a filter strip up, and the reason is in its widgets: a labelled EditBox is a
-- 44px frame with its box 25px down, a labelled Dropdown a 40px frame with its box 14px down
-- (AceGUIWidget-EditBox.lua / -DropDown.lua), and Flow aligns them by a per-type `alignoffset`. Buttons,
-- checkboxes and LAGW-SearchBox are 24px with no label. So no two kinds share a caption line or a box
-- line, and the gaps are whatever each frame's padding happens to be.
--
-- So controls go in UNLABELLED (an unlabelled EditBox or Dropdown is a 26px box from its frame's top)
-- and a caption is a separate TLabel, registered against its control:
--
--   local strip = W:NewStrip()
--   window:AddChild(strip)
--   W:StripAdd(strip, searchBox)                -- no caption: the placeholder is its caption
--   W:StripAdd(strip, zoneDropdown, "Zone")
--   W:FitCheckBox(forMe); W:StripAdd(strip, forMe)
--   ... W:StripRowWidth(strip) is the widest row, for a window floor or a no-wrap spec
--
-- The layout puts every caption on ONE line at the top of its row, left-aligned over its control, and
-- centres every control on ONE line under it. A row where no control has a caption has no caption line
-- (MINOR 40). ONE gap between every pair of controls. A row that runs out
-- of content width wraps. A control whose frame is hidden takes no space and its caption hides with it;
-- call DoLayout after hiding or showing one. A caption takes no horizontal space of its own and is given
-- its control's width, so a caption wider than its control wraps -- keep them short.
--
-- Sizes are scale-1.0 and follow the UI scale: the gap, the row gap and the caption line (its font is
-- scaled too). The row is at least 26px -- the unscaled AceGUI box -- and grows to its tallest control,
-- so a scaled LAGW-SearchBox still centres. The strip re-lays itself on a scale change.
--
-- State lives in the group's `userdata`, which AceGUI empties on Release, so a pooled group can never
-- read a caption from its previous owner. Feature-detect with `if W.NewStrip then`.
lib.STRIP_LAYOUT = "LAGW-Strip"
lib.STRIP_GAP, lib.STRIP_ROW_GAP, lib.STRIP_CAPTION, lib.STRIP_ROW = 8, 6, 14, 26

--- The AceGUI layout function for "LAGW-Strip". `content.obj` is the group widget.
function lib.StripLayout(content, children)
	local obj = content.obj
	local ud = (obj and obj.userdata) or {}
	local captions = ud.lagwCaptions or {}
	local isCaption = {}
	for _, label in pairs(captions) do isCaption[label] = true end
	local gap, rowGap = lib:ScaledSize(lib.STRIP_GAP), lib:ScaledSize(lib.STRIP_ROW_GAP)
	local capH = lib:ScaledSize(lib.STRIP_CAPTION)
	local maxWidth = content:GetWidth() or 0

	-- Pass 1: which row each control is on, and its x. Pass 2 needs a whole row to know its height.
	local rows, row, x, right = {}, nil, 0, 0
	for _, child in ipairs(children) do
		if not isCaption[child] then
			local frame = child.frame
			if not frame:IsShown() then
				if captions[child] then captions[child].frame:Hide() end
			else
				local width = frame:GetWidth() or 0
				-- Wrap only when there is a width to wrap against: a frame not yet sized reports 0.
				if row and #row > 0 and maxWidth > 0 and x + width > maxWidth then row = nil end
				if not row then
					row, x = {}, 0
					rows[#rows + 1] = row
				end
				row[#row + 1] = { child = child, x = x, width = width }
				right = math.max(right, x + width)
				x = x + width + gap
			end
		end
	end

	local top = 0
	for r, items in ipairs(rows) do
		local rowH = lib.STRIP_ROW
		-- A row with no caption at all takes no caption line (MINOR 40, Grouper inbox c98a1eab): a
		-- captionless second row sat under an empty band.
		local rowCap = 0
		for _, item in ipairs(items) do
			rowH = math.max(rowH, item.child.frame:GetHeight() or 0)
			if captions[item.child] then rowCap = capH end
		end
		for _, item in ipairs(items) do
			local frame = item.child.frame
			local height = frame:GetHeight() or rowH
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", content, "TOPLEFT", item.x, -(top + rowCap + (rowH - height) / 2))
			local caption = captions[item.child]
			if caption then
				caption:SetWidth(item.width)
				caption.frame:ClearAllPoints()
				caption.frame:SetPoint("TOPLEFT", content, "TOPLEFT", item.x, -top)
				caption.frame:Show()
			end
		end
		top = top + rowCap + rowH
		if r < #rows then top = top + rowGap end
	end

	ud.lagwRowWidth = right
	if obj and obj.LayoutFinished then obj:LayoutFinished(nil, top) end
end

do
	local AceGUI = LibStub("AceGUI-3.0", true)
	if AceGUI then AceGUI:RegisterLayout(lib.STRIP_LAYOUT, lib.StripLayout) end
end

-- A pooled group handed to another owner is no longer a strip; its listener takes itself off.
local function Strip_OnScaleChanged(_, _, group)
	if group.userdata and group.userdata.lagwStrip then
		group:DoLayout()
	else
		lib:OnScaleChanged(group, nil)
	end
end

--- A full-width SimpleGroup on the strip layout, with no captions yet. `height` is optional: the group
--- takes its height from the layout once it has children.
function lib:NewStrip(height)
	local AceGUI = LibStub("AceGUI-3.0")
	local group = AceGUI:Create("SimpleGroup")
	group:SetFullWidth(true)
	if height then group:SetHeight(height) end
	group.userdata.lagwStrip = true
	group.userdata.lagwCaptions = {}
	group:SetLayout(lib.STRIP_LAYOUT)
	self:OnScaleChanged(group, Strip_OnScaleChanged)
	return group
end

--- Add `control` (an AceGUI widget, UNLABELLED) to a strip, with `caption` above it, or nil for none.
--- Returns the caption widget (a TLabel in the gold of AceGUI's own control labels), or nil.
function lib:StripAdd(group, control, caption)
	local label
	if caption ~= nil then
		label = LibStub("AceGUI-3.0"):Create("TLabel")
		label:SetText(caption)
		label:SetFontObject(GameFontNormalSmall)
		label:SetColor(1, 0.82, 0)
		group.userdata.lagwCaptions = group.userdata.lagwCaptions or {}
		group.userdata.lagwCaptions[control] = label
		group:AddChild(label)
	end
	group:AddChild(control)
	return label
end

--- The width of the widest row the strip's last layout used; 0 before one ran.
function lib:StripRowWidth(group)
	return (group and group.userdata and group.userdata.lagwRowWidth) or 0
end

--- Size an AceGUI CheckBox to its own words: the box, the text, and 6px of air. Returns the width.
function lib:FitCheckBox(checkbox)
	local box = checkbox.checkbg and checkbox.checkbg:GetWidth() or 24
	local text = checkbox.text and checkbox.text:GetStringWidth() or 0
	local width = box + math.ceil(text) + 6
	checkbox:SetWidth(width)
	return width
end

--- `W:AddChips(container, order, labels, values, onChanged)` (MINOR 40): one LAGW-Chip per key in
--- `order`, labelled `labels[key]` (or the key), lit from `values[key]`, added to `container` (through
--- StripAdd on a strip, AddChild otherwise). A click WRITES `values[key]` and then calls
--- `onChanged(key, value, chip)` when given. Returns the chips keyed by key, for SetDisabled or a
--- tooltip. `values` is the consumer's table (a saved filter set, say); nil makes a fresh one.
function lib:AddChips(container, order, labels, values, onChanged)
	local AceGUI = LibStub("AceGUI-3.0")
	labels, values = labels or {}, values or {}
	local isStrip = container.userdata and container.userdata.lagwStrip
	local chips = {}
	for _, key in ipairs(order or {}) do
		local chip = AceGUI:Create("LAGW-Chip")
		chip:SetText(labels[key] or tostring(key))
		chip:SetValue(values[key])
		chip:SetCallback("OnValueChanged", function(widget, _, value)
			values[key] = value
			if onChanged then onChanged(key, value, widget) end
		end)
		if isStrip then self:StripAdd(container, chip) else container:AddChild(chip) end
		chips[key] = chip
	end
	return chips
end
