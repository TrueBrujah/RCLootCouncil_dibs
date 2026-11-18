-- LibAceGUIWidgets — DatePicker widget.
-- An AceGUI-3.0 widget type, "LAGW-DatePicker": a label, a text field showing a date as YYYY-MM-DD,
-- and a button that opens a small month-calendar popup (prev/next month, a day grid, Today, Clear).
-- Its value is a plain number -- `time()` of LOCAL MIDNIGHT on the chosen day -- or nil for "no
-- limit". The consumer does the range arithmetic; the widget only ever hands over a day.
--
-- Requested by TOGBankClassic (inbox 3ecad6a6, 2026-09-13) for the Since/Until filters on its guild
-- bank log. Their standing rule -- "we need the since and until to be date pickers" -- is why the
-- calendar is the primary affordance and typing is the fallback, not the other way round.
--
--   local AceGUI = LibStub("AceGUI-3.0")
--   local since = AceGUI:Create("LAGW-DatePicker")
--   since:SetLabel("Since")
--   since:SetWidth(140)
--   since:SetValue(nil)                                  -- no lower bound
--   since:SetCallback("OnValueChanged", function(widget, event, ts)
--       filter.since = ts                                -- a midnight timestamp, or nil
--       refresh()
--   end)
--   group:AddChild(since)
--
-- The EditBox-shaped contract: SetLabel, SetWidth (AceGUI base), SetValue(ts|nil), GetValue() ->
-- ts|nil, SetDisabled(bool), and the OnValueChanged(widget, "OnValueChanged", ts|nil) callback.
-- Since MINOR 30 (Version 3; ClassicCalendar inbox 4d698ce3): SetRange(minTs, maxTs),
-- SetTodayFunc(fn -> y, m, d), SetRequired(bool) and SetFirstWeekday(1..7), all reset on acquire.
-- `SetValue` is PROGRAMMATIC and fires nothing, exactly as AceGUI's EditBox `SetText` fires nothing;
-- every user action (a day click, Today, Clear, a typed date committed with Enter or by leaving the
-- field) fires OnValueChanged, and only when the value actually changed. A SetValue is also
-- NORMALISED to midnight of the local day it falls in, so GetValue never returns a mid-day stamp
-- whatever the consumer handed in -- a range filter built on this widget then compares like with
-- like.
--
-- Typing: `YYYY-MM-DD` (also `/` or `.` as the separator, and a trailing ` HH:MM` that is accepted
-- and dropped, since the widget is a DAY picker and the field re-renders as the day it kept). An
-- unparseable entry reverts the field to the current value on commit and fires nothing; an empty
-- field commits nil. Escape reverts and closes the popup.
--
-- THE POPUP IS ONE SHARED FRAME PER LIBRARY INSTANCE, re-anchored and re-owned per widget. It lives
-- on UIParent at TOOLTIP strata for the same reason the library's menus do (see `OpenMenu` in the
-- core file): a frame parented INTO a consumer's window inherits that window's clipping and strata,
-- and a popup inside an AceGUI ScrollFrame would be cut off at the scroll region's edge. So it is not
-- literally re-parented, as the request phrased it; it is re-owned, which is the property the request
-- was after -- "a widget handed back with the popup open must not leave it on screen". It closes on:
--   * Escape       -- the popup's global name is in UISpecialFrames, the client's own Escape list;
--                     and Escape inside the text field (OnEscapePressed) closes it too
--   * click-outside -- GLOBAL_MOUSE_DOWN while shown, anywhere not over the popup or its owner
--   * owner hidden -- the owning widget's frame OnHide (window closed, tab released), hooked once
--   * OnRelease    -- the owner being handed back to the pool
--   * SetDisabled  -- a disabled owner cannot have its calendar open
--
-- The day cells are PLAIN BUTTONS with a font string and the stock quest-title highlight -- no
-- Blizzard calendar textures. Classic Era is missing many of the textures later clients have
-- (TOGBankClassic BROOM-001), and a grid that always renders beats a prettier one that goes blank.
--
-- Everything date-shaped is a PURE function on `lib.DatePicker` so it can be pinned without a frame:
-- `midnight(y, m, d)`, `daysInMonth(y, m)`, `parse(text)`, `format(ts)`, `ymd(ts)`, `grid(y, m)`.

-- luacheck: read globals LibStub CreateFrame UIParent GameTooltip BackdropTemplateMixin UISpecialFrames
-- luacheck: read globals time date GameFontHighlightSmall GameFontNormalSmall GameFontDisableSmall
-- luacheck: ignore 212

local lib = LibStub and LibStub("LibAceGUIWidgets-1.0", true)
if not lib or lib._staleCopy then return end   -- _staleCopy: an older copy's satellite (see the core)

-- ---------------------------------------------------------------------------
-- Pure date arithmetic
-- ---------------------------------------------------------------------------
local DatePicker = lib.DatePicker or {}
lib.DatePicker = DatePicker

local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

-- Years the client's `time{}` can represent on every platform WoW ships on. `os.time` on Windows
-- returns nil below 1970, and the far end is a sanity bound: a typo like 20260 must not produce a
-- "valid" date a thousand years out.
local YEAR_MIN, YEAR_MAX = 1970, 2200

function DatePicker.isLeap(y)
	return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
end

-- Computed rather than read back from `date("*t", time{day = 0})`: the day-0 normalisation is a C
-- library habit, not a documented contract, and this has to be right on every client.
function DatePicker.daysInMonth(y, m)
	if m == 2 and DatePicker.isLeap(y) then return 29 end
	return MONTH_DAYS[m]
end

-- `time()` of local midnight on y-m-d, or nil when that is not a real calendar day. Validated
-- BEFORE the call rather than after: `time{month = 2, day = 30}` normalises to March 2nd instead of
-- failing, so a bare call would silently accept an impossible date and hand back a different one.
function DatePicker.midnight(y, m, d)
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not (y and m and d) then return nil end
	if y ~= math.floor(y) or m ~= math.floor(m) or d ~= math.floor(d) then return nil end
	if y < YEAR_MIN or y > YEAR_MAX then return nil end
	if m < 1 or m > 12 then return nil end
	if d < 1 or d > DatePicker.daysInMonth(y, m) then return nil end
	return time({ year = y, month = m, day = d, hour = 0, min = 0, sec = 0 })
end

-- The local calendar day a timestamp falls in, as three numbers. nil in, nil out.
function DatePicker.ymd(ts)
	ts = tonumber(ts)
	if not ts then return nil end
	local t = date("*t", ts)
	if type(t) ~= "table" then return nil end
	return t.year, t.month, t.day
end

-- Snap any timestamp to the midnight that starts its local day.
function DatePicker.snap(ts)
	local y, m, d = DatePicker.ymd(ts)
	if not y then return nil end
	return DatePicker.midnight(y, m, d)
end

-- "YYYY-MM-DD" for a timestamp; "" for nil, which is what the empty field shows.
function DatePicker.format(ts)
	local y, m, d = DatePicker.ymd(ts)
	if not y then return "" end
	return string.format("%04d-%02d-%02d", y, m, d)
end

-- Text -> timestamp. Returns the midnight timestamp, or nil plus a reason. The separator may be
-- `-`, `/` or `.`; one- or two-digit month and day are fine; a trailing time of day (` 14:30`, or
-- `T14:30`, with optional seconds) is accepted and ignored, because the value is a day. Anything
-- else is rejected rather than guessed at -- "13/09/2026" is not silently read as a month 13.
function DatePicker.parse(text)
	if type(text) ~= "string" then return nil, "not text" end
	local s = text:match("^%s*(.-)%s*$")
	if s == "" then return nil, "empty" end
	local y, m, d, rest = s:match("^(%d%d%d%d)[-/.](%d%d?)[-/.](%d%d?)(.*)$")
	if not y then return nil, "not YYYY-MM-DD" end
	if rest ~= "" and not rest:match("^[%sT]+%d%d?:%d%d[:%d]*$") then return nil, "trailing text" end
	local ts = DatePicker.midnight(y, m, d)
	if not ts then return nil, "not a calendar day" end
	return ts
end

-- A week start as the widget stores it: an integer 1 (Sunday) .. 7 (Saturday), the client's `wday`
-- numbering. Anything else is Sunday, so a bad setting shows a normal calendar rather than a skewed one.
function DatePicker.weekStart(firstWeekday)
	local fw = tonumber(firstWeekday)
	if not fw or fw ~= math.floor(fw) or fw < 1 or fw > 7 then return 1 end
	return fw
end

-- The 6x7 grid of a month as 42 slots: a day number, or false for a padding cell. Six rows always, so
-- the popup never changes height between months. The week starts on `firstWeekday` (1 = Sunday, the
-- default, .. 7 = Saturday; MINOR 30). The second return is the column the 1st falls in.
function DatePicker.grid(y, m, firstWeekday)
	local first = DatePicker.midnight(y, m, 1)
	if not first then return nil end
	local wday = date("*t", first).wday   -- 1 = Sunday, the client's and C's convention
	local col = (wday - DatePicker.weekStart(firstWeekday)) % 7 + 1
	local cells = {}
	local n = DatePicker.daysInMonth(y, m)
	for i = 1, 42 do
		local d = i - col + 1
		cells[i] = (d >= 1 and d <= n) and d or false
	end
	return cells, col
end

-- Is `ts` inside [minTs, maxTs]? Inclusive at both ends; a nil bound is open; a nil `ts` is never in
-- range. Bounds are compared as given, so the widget snaps them to midnight before storing them.
function DatePicker.inRange(ts, minTs, maxTs)
	if ts == nil then return false end
	if minTs and ts < minTs then return false end
	if maxTs and ts > maxTs then return false end
	return true
end

-- The month (y, m) pulled into the months the range touches: before the first bound's month -> that
-- month, after the last bound's month -> that month, otherwise unchanged.
function DatePicker.clampMonth(y, m, minTs, maxTs)
	local key = y * 12 + m
	local lo = minTs and { DatePicker.ymd(minTs) }
	local hi = maxTs and { DatePicker.ymd(maxTs) }
	if lo and lo[1] and key < lo[1] * 12 + lo[2] then return lo[1], lo[2] end
	if hi and hi[1] and key > hi[1] * 12 + hi[2] then return hi[1], hi[2] end
	return y, m
end

-- Midnight of "today": the day `todayFunc` names (it returns y, m, d -- ClassicCalendar hands in the
-- SERVER date, which is a day off local time for an Oceanic player on a US realm), or local time()
-- when there is no function or it names no real day. A raising function goes through the core's
-- safeCall: the error is REPORTED to the client's error handler with its stack, not swallowed, so a
-- broken clock is still visible -- and the popup falls back to local time instead of failing to draw.
-- safeCall hands back one value and this returns three, so they travel as a table.
function DatePicker.today(todayFunc)
	if type(todayFunc) == "function" then
		local ok, ymd = lib._safeCall(function() return { todayFunc() } end)
		local ts = ok and ymd and DatePicker.midnight(ymd[1], ymd[2], ymd[3])
		if ts then return ts end
	end
	return DatePicker.snap(time())
end

-- The month before / after (y, m), wrapping the year.
function DatePicker.stepMonth(y, m, delta)
	m = m + delta
	while m < 1 do m = m + 12; y = y - 1 end
	while m > 12 do m = m - 12; y = y + 1 end
	return y, m
end

-- ---------------------------------------------------------------------------
-- The shared popup
-- ---------------------------------------------------------------------------
local POPUP_NAME = "LibAceGUIWidgets_DatePickerPopup"
-- Scale-1.0 values (MINOR 29). `popupMetrics` multiplies them and `layoutPopup` places every
-- region from the result, at build and again on every scale change.
-- CELL_W was 22 until 2026-09-17 and the weekday header paid for it: the operator's screenshot of the
-- popup in TOGBankClassic read `Sun M... Tue W... Thu Fri Sat`. The labels are `date("%a")` and are
-- clamped to one cell, so the two abbreviations built from the widest letters -- Mon and Wed -- were
-- ellipsised while the other five fitted. The old comment beside them claimed "'Sun' fits a 22px cell in
-- the small font anyway", which is true of Sun and was never checked against M or W. 26 is the fix and is
-- NOT verified in a client yet; the harness has no text metrics, so no spec here can measure a glyph.
local CELL_W, CELL_H = 26, 20
local PAD            = 12                 -- inset from the frame edge; clears FrameBackdrop's 8px border
local HEADER_H       = 20                 -- the prev / month-year / next row
local WEEKDAY_H      = 14
local FOOTER_H       = 22                 -- Today / Clear
local NAV_W          = 20                 -- the < and > buttons

local function popupMetrics()
	local S = function(px) return lib:ScaledSize(px) end
	local m = {
		cellW = S(CELL_W), cellH = S(CELL_H), pad = S(PAD), headerH = S(HEADER_H),
		weekdayH = S(WEEKDAY_H), footerH = S(FOOTER_H), navW = S(NAV_W),
		gapA = S(4), gapB = S(6),   -- header -> weekday row; grid -> footer
	}
	m.gridW   = m.cellW * 7
	m.popupW  = m.gridW + m.pad * 2
	m.popupH  = m.pad + m.headerH + m.gapA + m.weekdayH + m.cellH * 6 + m.gapB + m.footerH + m.pad
	m.gridTop = m.pad + m.headerH + m.gapA + m.weekdayH
	return m
end

local HIGHLIGHT_TEX  = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

-- The in-field calendar glyph: the same treatment SearchBoxTemplate gives its magnifying glass, read
-- from `Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml:35` and `.lua:21-43` rather than
-- eyeballed -- at the field's LEFT +1,-1 on the OVERLAY layer, the text inset to clear it, vertex
-- colour 0.6 grey while idle and empty, white while focused or holding text.
--
-- THE PICTURE IS A FILE THIS LIBRARY SHIPS: `Textures/calendar.tga`, a 64x64 32-bit TGA of a white
-- line-art calendar page (outline, header rule, two binder rings, three day dots) with an alpha channel,
-- tinted by the same rule as the magnifier. It used to be the Wrath+ minimap calendar button cropped to
-- 10px; seen on Classic Era (TOGBankClassic inbox 62583e69, operator screenshot 2026-09-13) that
-- full-colour gold art read as "a small gold-ish square blob" beside the magnifier's crisp grey line
-- work. A bundled file renders identically on every flavour, which is the property a library-owned
-- widget needs; the header layout is the one TOGBankClassic's own broom.tga uses, known to load on
-- Era, TBC and retail. `SetTexture` documents a `success` return
-- (SimpleTextureBaseAPIDocumentation.lua:429); a miss -- the file absent from a checkout -- falls back
-- to a page silhouette drawn from flat colour, which cannot go blank. `.pkgmeta` must never ignore
-- `Textures`, or every player gets the fallback.
local CALENDAR_ICON  = "Interface\\AddOns\\RCLootCouncil_dibs\\libs\\LibAceGUIWidgets\\Textures\\calendar.tga"
local GLYPH_SIZE     = 14          -- the magnifier is drawn larger than its declared 10; 12-14 was asked for
local GLYPH_INSET    = GLYPH_SIZE + 6   -- left text inset: the glyph, its 1px offset and the magnifier's gap
local ICON_IDLE, ICON_LIT = 0.6, 1.0
DatePicker.GLYPH = CALENDAR_ICON   -- public, so a spec (or a consumer) can assert which file is drawn

-- A known Sunday, used only to ask `date("%a")` for the seven weekday abbreviations in whatever
-- language the client's C locale renders them. Midday, so no DST edge can move it a day.
local A_SUNDAY = { year = 2023, month = 1, day = 1, hour = 12 }

local function closePopup(self)
	local p = self._datePopup
	if p and p:IsShown() then p:Hide() end
end

local function setEnabled(btn, on)
	if on then btn:Enable() else btn:Disable() end
end

-- Paint the month `p.year`/`p.month` for the owner's current value and settings. Every per-widget
-- setting (range, today function, required, week start) is read from the OWNER here, on every paint,
-- because the popup is shared: nothing one widget set may survive into the next widget's paint.
local function renderPopup(self)
	local p = self._datePopup
	local owner = p.owner
	local minTs, maxTs = owner and owner.rangeMin, owner and owner.rangeMax
	local firstWeekday = DatePicker.weekStart(owner and owner.firstWeekday)
	local firstOfMonth = DatePicker.midnight(p.year, p.month, 1)
	local cells = firstOfMonth and DatePicker.grid(p.year, p.month, firstWeekday) or {}
	local ownerY, ownerM, ownerD = DatePicker.ymd(owner and owner.value)
	local todayTs = DatePicker.today(owner and owner.todayFunc)
	local todayY, todayM, todayD = DatePicker.ymd(todayTs)
	local r, g, b = self:AccentRGB()
	p.title:SetText(firstOfMonth and date("%B %Y", firstOfMonth + 43200) or "")   -- midday; DST-proof
	for c = 1, 7 do
		p.weekdays[c]:SetText(p.weekdayNames[(firstWeekday - 1 + c - 1) % 7 + 1] or "")
	end
	for i = 1, 42 do
		local btn, d = p.days[i], cells[i]
		btn.day = d or nil
		if d then
			btn.text:SetText(tostring(d))
			local selected = ownerY == p.year and ownerM == p.month and ownerD == d
			local isToday  = todayY == p.year and todayM == p.month and todayD == d
			local allowed  = DatePicker.inRange(DatePicker.midnight(p.year, p.month, d), minTs, maxTs)
			setEnabled(btn, allowed)
			if selected then
				btn.text:SetTextColor(r, g, b)
				btn:LockHighlight()
			else
				btn:UnlockHighlight()
				if not allowed then btn.text:SetTextColor(0.5, 0.5, 0.5)
				elseif isToday then btn.text:SetTextColor(r, g, b)
				else btn.text:SetTextColor(1, 1, 1) end
			end
			btn:Show()
		else
			btn.text:SetText("")
			btn:UnlockHighlight()
			btn:Hide()
		end
	end
	-- Stepping stops at the months the range touches; Today is refused when today is outside it; a
	-- required picker has nothing to Clear to.
	for btn, delta in pairs({ [p.prev] = -1, [p.next] = 1 }) do
		local sy, sm = DatePicker.stepMonth(p.year, p.month, delta)
		local cy, cm = DatePicker.clampMonth(sy, sm, minTs, maxTs)
		setEnabled(btn, cy == sy and cm == sm)   -- the step lands inside the range's months
	end
	setEnabled(p.today, DatePicker.inRange(todayTs, minTs, maxTs))
	setEnabled(p.clear, not (owner and owner.required))
end

local function Day_OnClick(btn)
	local p = btn:GetParent()
	local owner = p.owner
	if not (owner and btn.day and btn:IsEnabled()) then return end
	if owner:_Commit(DatePicker.midnight(p.year, p.month, btn.day)) then closePopup(lib) end
end

-- The guards on IsEnabled are for a caller that invokes the script directly; the client never
-- delivers OnClick to a disabled button.
local function Prev_OnClick(btn)
	if not btn:IsEnabled() then return end
	local p = btn:GetParent()
	p.year, p.month = DatePicker.stepMonth(p.year, p.month, -1)
	renderPopup(lib)
end

local function Next_OnClick(btn)
	if not btn:IsEnabled() then return end
	local p = btn:GetParent()
	p.year, p.month = DatePicker.stepMonth(p.year, p.month, 1)
	renderPopup(lib)
end

local function Today_OnClick(btn)
	local owner = btn:GetParent().owner
	if not (owner and btn:IsEnabled()) then return end
	if owner:_Commit(DatePicker.today(owner.todayFunc)) then closePopup(lib) end
end

local function Clear_OnClick(btn)
	local owner = btn:GetParent().owner
	if not (owner and btn:IsEnabled()) then return end
	if owner:_Commit(nil) then closePopup(lib) end
end

-- Click-outside is `lib:OwnFloating`'s (MINOR 30); this is only the "what counts as MINE" half -- the
-- owning widget's field and arrow, which must not close the popup that their own click just opened.
local function Popup_IsOverOwner(p)
	local owner = p.owner
	return (owner and (owner.editbox:IsMouseOver() or owner.button:IsMouseOver())) and true or false
end

-- Registering/unregistering is OwnFloating's; forgetting the owner is this popup's own bookkeeping.
local function Popup_OnHide(p) p.owner = nil end

local function plainButton(parent)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetHighlightTexture(HIGHLIGHT_TEX, "ADD")
	local fs = btn:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(lib:ScaledFont("GameFontHighlightSmall"))
	fs:SetAllPoints(btn)
	fs:SetJustifyH("CENTER")
	btn.text = fs
	return btn
end

-- Every size and anchor in the popup, from the current metrics. The fonts follow in place; this
-- is the geometry around them.
local function layoutPopup(p)
	local m = popupMetrics()
	p:SetSize(m.popupW, m.popupH)
	p.prev:SetSize(m.navW, m.headerH)
	p.prev:ClearAllPoints()
	p.prev:SetPoint("TOPLEFT", p, "TOPLEFT", m.pad, -m.pad)
	p.next:SetSize(m.navW, m.headerH)
	p.next:ClearAllPoints()
	p.next:SetPoint("TOPRIGHT", p, "TOPRIGHT", -m.pad, -m.pad)
	p.title:SetHeight(m.headerH)
	for c = 1, 7 do
		local fs = p.weekdays[c]
		fs:SetSize(m.cellW, m.weekdayH)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", p, "TOPLEFT", m.pad + (c - 1) * m.cellW, -(m.pad + m.headerH + m.gapA))
	end
	for i = 1, 42 do
		local row, col = math.floor((i - 1) / 7), (i - 1) % 7
		local btn = p.days[i]
		btn:SetSize(m.cellW, m.cellH)
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", p, "TOPLEFT", m.pad + col * m.cellW, -(m.gridTop + row * m.cellH))
	end
	p.today:SetSize(m.gridW / 2 - 2, m.footerH)
	p.today:ClearAllPoints()
	p.today:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", m.pad, m.pad)
	p.clear:SetSize(m.gridW / 2 - 2, m.footerH)
	p.clear:ClearAllPoints()
	p.clear:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -m.pad, m.pad)
end

local function Popup_OnScaleChanged(_, _, p)
	layoutPopup(p)
end

-- Build once; every widget shares it. Public so a consumer (or a spec) can reach the day grid.
function lib:DatePickerPopup()
	local p = self._datePopup
	if p then
		-- Built by an older MINOR earlier this session (the popup lives on the lib table, which an
		-- upgrade keeps): it has no Sunday-first name list, and renderPopup rotates from it.
		if not p.weekdayNames then
			p.weekdayNames = {}
			local sunday = time(A_SUNDAY)
			for c = 1, 7 do p.weekdayNames[c] = date("%a", sunday + (c - 1) * 86400) or "" end
		end
		return p
	end
	-- The shared floating shape (MINOR 30): UIParent, TOOLTIP strata above the FULLSCREEN_DIALOG window,
	-- the library backdrop, the opaque fill the menus carry, and -- because it is NAMED -- the client's
	-- own Escape list. Level 130 puts it above a menu, which tops out at 100 + depth * 10.
	p = lib:CreateFloatingFrame({ name = POPUP_NAME, level = 130 })
	p:Hide()

	-- Header: < Month YYYY >
	p.prev = plainButton(p)
	p.prev.text:SetText("<")
	p.prev:SetScript("OnClick", Prev_OnClick)
	p.next = plainButton(p)
	p.next.text:SetText(">")
	p.next:SetScript("OnClick", Next_OnClick)
	p.title = p:CreateFontString(nil, "OVERLAY")
	p.title:SetFontObject(lib:ScaledFont("GameFontNormalSmall"))
	p.title:SetPoint("LEFT",  p.prev, "RIGHT", 2, 0)
	p.title:SetPoint("RIGHT", p.next, "LEFT", -2, 0)
	p.title:SetJustifyH("CENTER")

	-- Weekday row in the client's own abbreviations. `weekdayNames` is Sunday-first (the `wday`
	-- numbering); renderPopup rotates it into the columns for the owner's week start on every paint.
	p.weekdays, p.weekdayNames = {}, {}
	local sunday = time(A_SUNDAY)
	for c = 1, 7 do
		local fs = p:CreateFontString(nil, "OVERLAY")
		fs:SetFontObject(lib:ScaledFont("GameFontDisableSmall"))
		fs:SetJustifyH("CENTER")
		-- The whole abbreviation, not a byte-truncation of it: a two-byte cut through a multi-byte
		-- locale name is a broken glyph. The CELL WIDTH is what has to fit it (see CELL_W above), not
		-- a shorter string -- a locale whose abbreviations are wider still will clip, and the remedy
		-- is the same one: widen the cell.
		p.weekdayNames[c] = date("%a", sunday + (c - 1) * 86400) or ""
		fs:SetText(p.weekdayNames[c])
		p.weekdays[c] = fs
	end

	-- Day grid: 6 rows x 7 columns of plain buttons.
	p.days = {}
	for i = 1, 42 do
		local btn = plainButton(p)
		btn:SetScript("OnClick", Day_OnClick)
		p.days[i] = btn
	end

	-- Footer: Today | Clear
	p.today = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.today:SetText("Today")
	p.today:SetScript("OnClick", Today_OnClick)
	lib._scaleButtonFonts(lib, p.today)
	p.clear = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.clear:SetText("Clear")
	p.clear:SetScript("OnClick", Clear_OnClick)
	lib._scaleButtonFonts(lib, p.clear)

	layoutPopup(p)
	lib:OnScaleChanged(p, Popup_OnScaleChanged)

	p:SetScript("OnHide", Popup_OnHide)
	-- Click-outside, and the GLOBAL_MOUSE_DOWN registration that only runs while shown: the shared
	-- implementation (MINOR 30). Escape came with the NAME, through CreateFloatingFrame above.
	lib:OwnFloating(p, { isOver = Popup_IsOverOwner })

	self._datePopup = p
	return p
end

-- Open (or re-own) the popup for `widget`, showing the month of its value or of today.
local function openPopup(self, widget)
	local p = self:DatePickerPopup()
	local y, m = DatePicker.ymd(widget.value)
	if not y then y, m = DatePicker.ymd(DatePicker.today(widget.todayFunc)) end
	y, m = DatePicker.clampMonth(y, m, widget.rangeMin, widget.rangeMax)
	p.owner, p.year, p.month = widget, y, m
	p:ClearAllPoints()
	p:SetPoint("TOPLEFT", widget.editbox, "BOTTOMLEFT", -6, -2)
	-- A popup must not outlive its owner's visibility: the owner's window closing or its tab being
	-- released fires OnHide on the widget frame. Hooked once per frame, and only acts while this
	-- widget still owns the popup -- the same shape as OpenMenu's anchor hook.
	local f = widget.frame
	if not f._lagwDateHideHook then
		f._lagwDateHideHook = true
		f:HookScript("OnHide", function()
			local pop = self._datePopup
			if pop and pop.owner == f.obj then pop:Hide() end
		end)
	end
	renderPopup(self)
	p:Show()
end

-- ===========================================================================
-- The widget type
-- ===========================================================================
do
	-- 1: a new type with no competing copy anywhere, so there is no tie to break (see the notes on
	-- ClearFrame / GroupFrame / TLabel in the core file for why THOSE sit at 30).
	-- 1 -> 2: the widget follows the UI scale (MINOR 29) -- fonts, the field and button heights,
	-- the glyph and the popup all re-lay on a change. A MINOR-28 copy at 1 must lose to this one.
	-- 2 -> 3: range, today function, required mode and week start (MINOR 30, ClassicCalendar inbox
	-- 4d698ce3). A Version-2 copy has none of the four methods, so it must lose to this one.
	local Type, Version = "LAGW-DatePicker", 3
	local AceGUI = LibStub("AceGUI-3.0", true)
	if AceGUI and (AceGUI:GetWidgetVersion(Type) or 0) < Version then
		local pairs = pairs

		-- Drop keyboard focus WITHOUT committing what is in the field. Every ClearFocus the widget
		-- itself initiates goes through here: after an Enter (already committed), on Escape (reverted),
		-- on SetDisabled and on OnRelease. The last one is the reason this exists -- a widget handed
		-- back to the pool mid-typing must not fire OnValueChanged into a consumer that has let go of
		-- it, and AceGUI clears the callback table only AFTER OnRelease returns.
		local function dropFocus(self)
			self._silentBlur = true
			self.editbox:ClearFocus()
			self._silentBlur = false
		end

		local function EditBox_OnEnterPressed(eb)
			local self = eb.obj
			self:_CommitText(eb:GetText())
			dropFocus(self)
		end

		-- Leaving the field by clicking elsewhere commits what was typed, the way a form field does.
		local function EditBox_OnEditFocusLost(eb)
			local self = eb.obj
			if not self._silentBlur then self:_CommitText(eb:GetText()) end
			self:_TintGlyph()
		end

		local function EditBox_OnEditFocusGained(eb)
			AceGUI:SetFocus(eb.obj)
			eb.obj:_TintGlyph()
		end

		local function EditBox_OnEscapePressed(eb)
			local self = eb.obj
			self:_RenderText()
			dropFocus(self)
			self:CloseCalendar()
		end

		local function Button_OnClick(btn)
			local self = btn.obj
			if self.disabled then return end
			if self:IsCalendarOpen() then self:CloseCalendar() else self:OpenCalendar() end
		end

		-- A click IN THE FIELD opens the calendar too. The field is ~110px of the widget and the arrow
		-- 20px; with only the arrow as an opener, the operator clicked the field, got a caret, and
		-- concluded there was no picker at all (TOGBankClassic inbox bb9c59be, 2026-09-13). OPENS ONLY --
		-- never toggles: a second click in the field is the user placing the caret, and closing the
		-- popup under it would fight typing. The arrow keeps its toggle; focus is untouched, so typing
		-- still works with the calendar open; the popup's click-outside handler already ignores a
		-- mouse-down over the owner's field, so the opening click cannot also close it.
		local function EditBox_OnMouseDown(eb)
			local self = eb.obj
			if self.disabled or self:IsCalendarOpen() then return end
			self:OpenCalendar()
		end

		-- The in-field glyph. Returns the list of texture regions that make it up, so the tint can be
		-- applied to all of them whichever branch built it: one region for the real calendar page, two
		-- (a body and a header band) for the drawn fallback. Sizes are `layoutGlyph`'s.
		local function buildCalendarGlyph(editbox)
			local icon = editbox:CreateTexture(nil, "OVERLAY")
			icon:SetPoint("LEFT", editbox, "LEFT", 1, -1)
			local ok = icon:SetTexture(CALENDAR_ICON)
			if ok and icon:GetTexture() then
				return { icon }, false   -- the whole file, no crop: the TGA is the glyph
			end
			-- Fallback (the file missing from a checkout): a page silhouette -- a translucent body
			-- under a solid header band -- sized to the same box the glyph would have filled.
			icon:SetColorTexture(1, 1, 1, 0.35)
			icon:SetPoint("LEFT", editbox, "LEFT", 1, -3)
			local band = editbox:CreateTexture(nil, "OVERLAY")
			band:SetColorTexture(1, 1, 1, 1)
			band:SetPoint("BOTTOMLEFT", icon, "TOPLEFT", 0, 0)
			return { icon, band }, true
		end

		-- The glyph's box at the current scale: the whole square for the file, body + band for the
		-- drawn fallback.
		local function layoutGlyph(self)
			local size = lib:ScaledSize(GLYPH_SIZE)
			if self.glyphIsFallback then
				self.glyph[1]:SetSize(size, size - lib:ScaledSize(4))
				self.glyph[2]:SetSize(size, lib:ScaledSize(4))
			else
				self.glyph[1]:SetSize(size, size)
			end
		end

		-- The widget's own geometry at the current scale: the control heights (AceGUI's EditBox
		-- numbers, multiplied), the button and its arrow, the glyph and the text inset that clears it.
		local function layoutWidget(self)
			local S = function(px) return lib:ScaledSize(px) end
			self.button:SetSize(S(20), S(20))
			self.arrow:SetSize(S(16), S(16))
			self.editbox:SetHeight(S(19))
			self.editbox:SetTextInsets(S(GLYPH_INSET), 0, 3, 3)
			self.label:SetHeight(S(18))
			layoutGlyph(self)
			self:SetLabel(self.label:GetText())   -- re-applies the frame height for the current scale
		end

		local function Widget_OnScaleChanged(_, _, self)
			layoutWidget(self)
		end

		-- SearchBoxTemplate's rule: lit while focused or holding text, grey otherwise; dimmer still
		-- when the whole control is disabled.
		local function tintCalendarGlyph(self)
			local v
			if self.disabled then v = 0.4
			elseif self.editbox:HasFocus() or self.value ~= nil then v = ICON_LIT
			else v = ICON_IDLE end
			for _, tex in ipairs(self.glyph) do tex:SetVertexColor(v, v, v) end
		end

		local methods = {
			["OnAcquire"] = function(self)
				-- A pooled widget must not come back ranged, required, or on someone else's clock.
				self.rangeMin, self.rangeMax, self.todayFunc, self.required, self.firstWeekday = nil, nil, nil, false, nil
				self:SetHeight(lib:ScaledSize(26))
				self:SetWidth(200)
				self:SetDisabled(false)
				self:SetLabel()
				self:SetValue(nil)
			end,

			["OnRelease"] = function(self)
				self:CloseCalendar()
				dropFocus(self)
				self:SetDisabled(false)
				self.value = nil
				self.editbox:SetText("")
			end,

			-- AceGUI's own ClearFocus() (a click on a ClearFrame's body, say) reaches the focused
			-- widget through this method. That is a user leaving the field, so it commits.
			["ClearFocus"] = function(self)
				self.editbox:ClearFocus()
			end,

			-- The field is anchored to the BOTTOM of the frame at a fixed height, so a label only has
			-- to grow the frame; nothing is re-anchored. AceGUI's EditBox uses the same two heights.
			["SetLabel"] = function(self, text)
				if text and text ~= "" then
					self.label:SetText(text)
					self.label:Show()
					self:SetHeight(lib:ScaledSize(44))
					self.alignoffset = lib:ScaledSize(30)
				else
					self.label:SetText("")
					self.label:Hide()
					self:SetHeight(lib:ScaledSize(26))
					self.alignoffset = lib:ScaledSize(12)
				end
			end,

			-- PROGRAMMATIC. Fires nothing; snaps to midnight of the local day. Not range-checked: the
			-- range governs what the USER can pick, and a consumer loading a stored date must see it.
			-- A required picker handed nil takes its default day instead.
			["SetValue"] = function(self, ts)
				self.value = DatePicker.snap(ts)
				if self.value == nil and self.required then self.value = self:_DefaultDay() end
				self:_RenderText()
				self:_RepaintIfOpen()
			end,

			-- ---- MINOR 30: ClassicCalendar inbox 4d698ce3, item 1 ----

			-- Days outside [minTs, maxTs] cannot be clicked, typed or reached with Today, and month
			-- stepping stops at the months the range touches. Either bound may be nil (open); the two
			-- are snapped to their days and may be given in either order.
			["SetRange"] = function(self, minTs, maxTs)
				local lo, hi = DatePicker.snap(minTs), DatePicker.snap(maxTs)
				if lo and hi and lo > hi then lo, hi = hi, lo end
				self.rangeMin, self.rangeMax = lo, hi
				local p = lib._datePopup
				if p and p.owner == self and p:IsShown() then
					p.year, p.month = DatePicker.clampMonth(p.year, p.month, lo, hi)
				end
				self:_RepaintIfOpen()
			end,

			-- `fn()` returns year, month, day: the day "today" means for the highlight, the Today button,
			-- the month opened with no value and a required picker's default. nil restores local time().
			["SetTodayFunc"] = function(self, fn)
				self.todayFunc = type(fn) == "function" and fn or nil
				self:_RepaintIfOpen()
			end,

			-- A required picker's value is never nil: no Clear, an emptied field reverts, SetValue(nil)
			-- takes the default. Turning it on with no value sets today (inside the range), silently.
			["SetRequired"] = function(self, required)
				self.required = required and true or false
				if self.required and self.value == nil then
					self.value = self:_DefaultDay()
					self:_RenderText()
				end
				self:_RepaintIfOpen()
			end,

			-- 1 = Sunday (the default) .. 7 = Saturday, the client's weekday numbering.
			["SetFirstWeekday"] = function(self, weekday)
				self.firstWeekday = DatePicker.weekStart(weekday)
				self:_RepaintIfOpen()
			end,

			-- Today, pulled into the range: its first day if today is before it, its last if after.
			["_DefaultDay"] = function(self)
				local ts = DatePicker.today(self.todayFunc)
				if self.rangeMin and ts < self.rangeMin then return self.rangeMin end
				if self.rangeMax and ts > self.rangeMax then return self.rangeMax end
				return ts
			end,

			["_RepaintIfOpen"] = function(self)
				local p = lib._datePopup
				if p and p.owner == self and p:IsShown() then renderPopup(lib) end
			end,

			["GetValue"] = function(self) return self.value end,

			["GetText"] = function(self) return self.editbox:GetText() end,

			["SetDisabled"] = function(self, disabled)
				self.disabled = disabled
				if disabled then
					self:CloseCalendar()
					dropFocus(self)
					self.editbox:EnableMouse(false)
					self.editbox:SetTextColor(0.5, 0.5, 0.5)
					self.label:SetTextColor(0.5, 0.5, 0.5)
					self.button:Disable()
					self.arrow:SetVertexColor(0.5, 0.5, 0.5)
				else
					self.editbox:EnableMouse(true)
					self.editbox:SetTextColor(1, 1, 1)
					-- (1, 0.82, 0) LITERALLY, and NOT `lib:AccentRGB()`. This widget sits in an
					-- AceGUI container beside stock EditBox, Slider, MultiLineEditBox and DropDown,
					-- every one of which restores its label with exactly this triple on re-enable
					-- (Ace3 on disk: AceGUIWidget-EditBox.lua:153, -Slider.lua:149,
					-- -MultiLineEditBox.lua:200, -DropDown.lua:493). It is GameFontNormalSmall's own
					-- colour -- what the label was before something disabled it -- so accenting it
					-- would make one label in a row of five follow the consumer's brand and the
					-- other four not. Re-enable must restore, not re-theme.
					self.label:SetTextColor(1, 0.82, 0)
					self.button:Enable()
					self.arrow:SetVertexColor(1, 1, 1)
				end
				self:_TintGlyph()
			end,

			["OpenCalendar"] = function(self)
				if self.disabled then return end
				openPopup(lib, self)
			end,

			["CloseCalendar"] = function(self)
				local p = lib._datePopup
				if p and p.owner == self then p:Hide() end
			end,

			["IsCalendarOpen"] = function(self)
				local p = lib._datePopup
				return (p and p.owner == self and p:IsShown()) and true or false
			end,

			-- The field always shows the value, never stale typing.
			["_RenderText"] = function(self)
				self.editbox:SetText(DatePicker.format(self.value))
				self:_TintGlyph()
			end,

			["_TintGlyph"] = tintCalendarGlyph,

			-- A USER change. Fires OnValueChanged only when the value moved. Returns whether it was
			-- ACCEPTED: nil on a required picker, or a day outside the range, is refused -- the field
			-- re-renders the value it kept and nothing fires.
			["_Commit"] = function(self, ts)
				local snapped = DatePicker.snap(ts)
				if (snapped == nil and self.required)
					or (snapped ~= nil and not DatePicker.inRange(snapped, self.rangeMin, self.rangeMax)) then
					self:_RenderText()
					return false
				end
				local before = self.value
				self.value = snapped
				self._committing = true
				self:_RenderText()
				self._committing = false
				if self.value ~= before then
					self:Fire("OnValueChanged", self.value)
				end
				return true
			end,

			-- Typed text: empty commits nil, a date commits that day, anything else reverts. Returns
			-- whether the text was accepted, for a caller that wants to know.
			["_CommitText"] = function(self, text)
				local s = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
				if s == "" then return self:_Commit(nil) end
				local ts = DatePicker.parse(s)
				if ts then return self:_Commit(ts) end
				self:_RenderText()
				return false
			end,
		}

		local function Constructor()
			local frame = CreateFrame("Frame", nil, UIParent)
			frame:Hide()

			local label = frame:CreateFontString(nil, "OVERLAY")
			label:SetFontObject(lib:ScaledFont("GameFontNormalSmall"))
			label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -2)
			label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -2)
			label:SetJustifyH("LEFT")

			-- The calendar button: the same down-arrow CreateDropdownBox uses, which is known to
			-- render on every client this library ships to.
			local button = CreateFrame("Button", nil, frame)
			button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
			button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			button:SetScript("OnClick", Button_OnClick)
			local arrow = button:CreateTexture(nil, "OVERLAY")
			arrow:SetPoint("CENTER", button, "CENTER", 0, -1)
			arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
			arrow:SetRotation(-1.5708)   -- point it downward

			-- Bottom-anchored on both sides, so the height is the SetHeight and the label only ever grows
			-- the frame above it. (A TOPLEFT + BOTTOMRIGHT pair would make the height a consequence of
			-- the anchors and silently ignore SetHeight.)
			local editbox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
			if lib._trackFocus then lib:_trackFocus(editbox) end   -- MINOR 36; a satellite may meet an older core
			editbox:SetAutoFocus(false)
			if editbox.SetFontObject then editbox:SetFontObject(lib:ScaledFont("ChatFontNormal")) end
			editbox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 7, 0)
			editbox:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", -2, 0)
			-- Height and text insets (room for the glyph on the left, as SearchBoxTemplate reserves)
			-- are layoutWidget's, applied below and on every scale change.
			editbox:SetMaxLetters(24)
			editbox:SetScript("OnEnterPressed",     EditBox_OnEnterPressed)
			editbox:SetScript("OnEscapePressed",    EditBox_OnEscapePressed)
			editbox:SetScript("OnEditFocusGained",  EditBox_OnEditFocusGained)
			editbox:SetScript("OnEditFocusLost",    EditBox_OnEditFocusLost)
			editbox:SetScript("OnMouseDown",        EditBox_OnMouseDown)

			local glyph, glyphIsFallback = buildCalendarGlyph(editbox)

			local widget = {
				frame   = frame,
				label   = label,
				editbox = editbox,
				button  = button,
				arrow   = arrow,
				glyph   = glyph,                   -- the in-field calendar picture's texture regions
				glyphIsFallback = glyphIsFallback, -- true when the drawn silhouette stood in for the file
				type    = Type,
			}
			for method, func in pairs(methods) do
				widget[method] = func
			end
			editbox.obj, button.obj = widget, widget

			-- After registration: layoutWidget goes through SetLabel -> SetHeight, and SetHeight is
			-- AceGUI's base method, present only once RegisterAsWidget has set the metatable.
			widget = AceGUI:RegisterAsWidget(widget)
			layoutWidget(widget)
			lib:OnScaleChanged(widget, Widget_OnScaleChanged)   -- AceGUI pools the widget, so the weak key lives
			return widget
		end

		AceGUI:RegisterWidgetType(Type, Constructor, Version)
	end
end
