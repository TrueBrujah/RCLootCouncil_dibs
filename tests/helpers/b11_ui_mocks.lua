local M = {}

function M.installMSA()
  local state = { created = 0, initialized = 0, shown = 0 }
  _G.MSA_DropDownMenu_Create = function(name, parent)
    state.created = state.created + 1
    return { name = name, parent = parent, SetPoint = function() end, Show = function() end }
  end
  _G.MSA_DropDownMenu_Initialize = function(frame, callback)
    state.initialized = state.initialized + 1
    frame._initialize = callback
  end
  _G.MSA_DropDownMenu_CreateInfo = function() return {} end
  _G.MSA_DropDownMenu_AddButton = function() end
  _G.MSA_ToggleDropDownMenu = function() state.shown = state.shown + 1 end
  _G.MSA_DropDownMenu_SetText = function(frame, text) frame.text = text end
  _G.MSA_DropDownMenu_SetWidth = function() end
  _G.MSA_DropDownMenu_JustifyText = function() end
  _G.MSA_DropDownMenu_SetSelectedValue = function() end
  return state
end

function M.installLibraries(previous)
  local media = {
    Fetch = function(_, kind, name)
      if kind == "font" and name == "Test Font" then return "Interface\\Fonts\\Test.ttf" end
      if kind == "statusbar" and name == "Test Bar" then return "Interface\\Textures\\Test" end
      return nil
    end,
  }
  local window = {}
  window.RegisterConfig = function(frame, config, names) window.last = { frame = frame, config = config, names = names } end
  window.RestorePosition = function(frame) window.restored = frame end
  window.MakeDraggable = function(frame) window.draggable = frame end
  window.SavePosition = function(frame) window.saved = frame end
  _G.LibStub = function(name, silent)
    if name == "LibSharedMedia-3.0" then return media end
    if name == "LibWindow-1.1" then return window end
    return previous(name, silent)
  end
  return media, window
end

function M.clear()
  _G.MSA_DropDownMenu_Create = nil
  _G.MSA_DropDownMenu_Initialize = nil
  _G.MSA_DropDownMenu_CreateInfo = nil
  _G.MSA_DropDownMenu_AddButton = nil
  _G.MSA_ToggleDropDownMenu = nil
  _G.MSA_DropDownMenu_SetText = nil
  _G.MSA_DropDownMenu_SetWidth = nil
  _G.MSA_DropDownMenu_JustifyText = nil
  _G.MSA_DropDownMenu_SetSelectedValue = nil
end

return M
