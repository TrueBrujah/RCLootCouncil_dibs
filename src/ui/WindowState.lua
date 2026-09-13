--[[
Module: Dibs.WindowState
Layer: Local presentation persistence
Purpose: Restore local window position and scale through LibWindow when available.
Non-responsibilities: Guild policy, sync, authority, and domain state.
]]

local Dibs = _G.Dibs
Dibs.WindowState = Dibs.WindowState or {}
local WindowState = Dibs.WindowState

local function storage()
  local root = _G.RCLootCouncil_dibsLocalDB
  if type(root) ~= "table" then root = {}; _G.RCLootCouncil_dibsLocalDB = root end
  root.schemaVersion = 1
  root.presentation = root.presentation or {}
  root.presentation.windows = root.presentation.windows or {}
  return root.presentation.windows
end

local function getLibrary()
  if type(_G.LibStub) ~= "function" and type(_G.LibStub) ~= "table" then return nil end
  local ok, library = pcall(_G.LibStub, "LibWindow-1.1", true)
  return ok and type(library) == "table" and library or nil
end

function WindowState.Register(frame, id)
  if not frame or not id then return false end
  local config = storage()
  config[id] = config[id] or {}
  local library = getLibrary()
  if library and type(library.RegisterConfig) == "function" then
    pcall(library.RegisterConfig, frame, config, { prefix = tostring(id) .. "." })
    if type(library.RestorePosition) == "function" then pcall(library.RestorePosition, frame) end
    if type(library.MakeDraggable) == "function" then pcall(library.MakeDraggable, frame) end
    return true
  end
  return false
end

function WindowState.Save(frame, id)
  if not frame or not id then return false end
  local library = getLibrary()
  if library and type(library.SavePosition) == "function" then
    local ok = pcall(library.SavePosition, frame)
    return ok
  end
  return false
end

function WindowState.Get(id)
  local value = storage()[id]
  if type(value) ~= "table" then return {} end
  return Dibs.DeepCopy and Dibs.DeepCopy(value) or value
end

return WindowState
