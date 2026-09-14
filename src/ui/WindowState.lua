--[[
Module: Dibs.WindowState
Layer: Local presentation persistence
Purpose: Restore local window position and scale through LibWindow when available.
Non-responsibilities: Guild policy, sync, authority, and domain state.
]]

local Dibs = _G.Dibs
Dibs.WindowState = Dibs.WindowState or {}
local WindowState = Dibs.WindowState
local registrations = setmetatable({}, { __mode = "k" })
local storage, getLibrary

local function debugPosition(stage, frame, id)
  if not (Dibs.DebugLogs and type(Dibs.DebugLogs.Add) == "function") then return end
  local point, relativeTo, relativePoint, x, y
  if frame and type(frame.GetPoint) == "function" then
    point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
  end
  local effectiveScale = frame and type(frame.GetEffectiveScale) == "function" and frame:GetEffectiveScale() or frame and type(frame.GetScale) == "function" and frame:GetScale() or 1
  local parent = frame and type(frame.GetParent) == "function" and frame:GetParent() or _G.UIParent
  local parentScale = parent and type(parent.GetEffectiveScale) == "function" and parent:GetEffectiveScale() or parent and type(parent.GetScale) == "function" and parent:GetScale() or 1
  Dibs.DebugLogs.Add("ui", 4, string.format(
    "POSITION_%s KEY=%s POINT=%s RELATIVE_POINT=%s X=%s Y=%s LEFT=%s TOP=%s EFFECTIVE_SCALE=%s UIPARENT_SCALE=%s",
    tostring(stage), tostring(id or "unknown"), tostring(point or "nil"), tostring(relativePoint or "nil"),
    tostring(x or "nil"), tostring(y or "nil"), tostring(frame and frame.GetLeft and frame:GetLeft() or "nil"),
    tostring(frame and frame.GetTop and frame:GetTop() or "nil"), tostring(effectiveScale), tostring(parentScale)))
end

local function storedPosition(id)
  local record = storage()[id]
  if type(record) ~= "table" then return "nil" end
  return string.format("point=%s x=%s y=%s", tostring(record.point or "nil"), tostring(record.x or "nil"), tostring(record.y or "nil"))
end

local function restoreIfOffscreen(frame, id)
  if not frame or type(frame.GetLeft) ~= "function" or type(frame.GetTop) ~= "function" then return end
  local left, top = frame:GetLeft(), frame:GetTop()
  local width = type(frame.GetWidth) == "function" and frame:GetWidth() or 0
  local height = type(frame.GetHeight) == "function" and frame:GetHeight() or 0
  local parent = type(frame.GetParent) == "function" and frame:GetParent() or _G.UIParent
  local parentWidth = parent and type(parent.GetWidth) == "function" and parent:GetWidth() or nil
  local parentHeight = parent and type(parent.GetHeight) == "function" and parent:GetHeight() or nil
  if not left or not top or not parentWidth or not parentHeight then return end
  local invalid = left + width < 0 or top - height > parentHeight or left > parentWidth or top < 0
  if not invalid then return end
  debugPosition("BEFORE_RECOVERY", frame, id)
  if frame.ClearAllPoints then frame:ClearAllPoints() end
  if frame.SetPoint then frame:SetPoint("CENTER", parent, "CENTER", 0, 0) end
  debugPosition("AFTER_RECOVERY", frame, id)
end

local function savePosition(frame, id, source)
  debugPosition("BEFORE_SAVE_" .. tostring(source or "UNKNOWN"), frame, id)
  local library = getLibrary()
  if not (library and type(library.SavePosition) == "function") then return false end
  local ok = pcall(library.SavePosition, frame)
  if ok then
    debugPosition("AFTER_SAVE_" .. tostring(source or "UNKNOWN"), frame, id)
    if Dibs.DebugLogs and type(Dibs.DebugLogs.Add) == "function" then
      Dibs.DebugLogs.Add("ui", 4, "POSITION_STORED KEY=" .. tostring(id) .. " " .. storedPosition(id))
    end
  end
  return ok
end

local function installDragOwnership(frame, id)
  if not frame then return end
  frame._dibsPositionKey = id
  if frame._dibsPositionHooksInstalled then return end
  frame._dibsPositionHooksInstalled = true
  local function dragStart()
    local key = frame._dibsPositionKey
    if frame._dibsPositionScriptStart then return end
    debugPosition("DRAG_START", frame, key)
  end
  local function dragStop()
    local key = frame._dibsPositionKey
    if frame._dibsPositionScriptStop then return end
    debugPosition("DRAG_STOP", frame, key)
    savePosition(frame, key, "TITLE")
  end
  if type(_G.hooksecurefunc) == "function" then
    pcall(_G.hooksecurefunc, frame, "StartMoving", dragStart)
    pcall(_G.hooksecurefunc, frame, "StopMovingOrSizing", dragStop)
  end
  if type(frame.SetMovable) == "function" then frame:SetMovable(true) end
  if type(frame.RegisterForDrag) == "function" then frame:RegisterForDrag("LeftButton") end
  if type(frame.SetScript) == "function" then
    frame:SetScript("OnDragStart", function(self)
      self._dibsPositionScriptStart = true
      debugPosition("DRAG_START", self, self._dibsPositionKey)
      if self.StartMoving then self:StartMoving() end
      self._dibsPositionScriptStart = nil
    end)
    frame:SetScript("OnDragStop", function(self)
      self._dibsPositionScriptStop = true
      if self.StopMovingOrSizing then self:StopMovingOrSizing() end
      self._dibsPositionScriptStop = nil
      debugPosition("DRAG_STOP", self, self._dibsPositionKey)
      savePosition(self, self._dibsPositionKey, "FRAME")
    end)
  end
end

function storage()
  local root = _G.RCLootCouncil_dibsLocalDB
  if type(root) ~= "table" then root = {}; _G.RCLootCouncil_dibsLocalDB = root end
  root.schemaVersion = 1
  root.presentation = root.presentation or {}
  root.presentation.windows = root.presentation.windows or {}
  return root.presentation.windows
end

function getLibrary()
  if type(_G.LibStub) ~= "function" and type(_G.LibStub) ~= "table" then return nil end
  local ok, library = pcall(_G.LibStub, "LibWindow-1.1", true)
  return ok and type(library) == "table" and library or nil
end

function WindowState.Register(frame, id)
  if not frame or not id then return false end
  if registrations[frame] and registrations[frame].id == id then return true end
  local config = storage()
  config[id] = config[id] or {}
  for _, field in ipairs({ "point", "x", "y", "scale" }) do
    local legacyKey = tostring(id) .. "." .. field
    if config[id][field] == nil and config[legacyKey] ~= nil then
      config[id][field] = config[legacyKey]
    end
  end
  local library = getLibrary()
  if library and type(library.RegisterConfig) == "function" then
    pcall(library.RegisterConfig, frame, config[id], {})
    if type(library.RestorePosition) == "function" then pcall(library.RestorePosition, frame) end
    debugPosition("AFTER_RESTORE", frame, id)
    restoreIfOffscreen(frame, id)
    installDragOwnership(frame, id)
    registrations[frame] = { id = id }
    return true
  end
  return false
end

function WindowState.Unregister(frame)
  if frame then frame._dibsPositionKey = nil end
  registrations[frame] = nil
end

function WindowState.Save(frame, id)
  if not frame or not id then return false end
  return savePosition(frame, id, "EXPLICIT")
end

function WindowState.Get(id)
  local value = storage()[id]
  if type(value) ~= "table" then return {} end
  return Dibs.DeepCopy and Dibs.DeepCopy(value) or value
end

return WindowState
