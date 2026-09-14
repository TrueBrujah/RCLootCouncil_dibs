local Dibs = _G.Dibs
Dibs.DeveloperUI = Dibs.DeveloperUI or {}
local DeveloperUI = Dibs.DeveloperUI

function DeveloperUI.GetProjection()
  local status = Dibs.DeveloperSandbox and Dibs.DeveloperSandbox.GetStatus and Dibs.DeveloperSandbox.GetStatus() or {
    developerMode = false, active = false, provider = "production", warning = "DEVELOPER_MODE_DISABLED",
  }
  return {
    visible = status.developerMode == true,
    warning = status.warning,
    provider = status.provider,
    active = status.active,
    role = status.role or "none",
    coordinatorState = status.coordinatorState or "none",
    authorityOrigin = status.authorityOrigin or "production",
    fault = status.fault,
  }
end

function DeveloperUI.Open()
  if not DeveloperUI.GetProjection().visible then return nil, "DEVELOPER_MODE_REQUIRED" end
  if not Dibs.AceGUI or not Dibs.AceGUI.CreateWindow then return nil, "UI_UNAVAILABLE" end
  local shell = Dibs.AceGUI.CreateWindow("Dibs Developer Sandbox", 760, 520, { "CENTER", 0, 0 })
  if not shell then return nil, "UI_UNAVAILABLE" end
  local page = shell.window
  local function refresh()
    Dibs.AceGUI.Clear(page)
    local projection = DeveloperUI.GetProjection()
    Dibs.AceGUI.AddHeading(shell, page, "Developer Sandbox", "Local simulation only; production data and authority are untouched.")
    if Dibs.Midnight and Dibs.Midnight.AddSandboxBanner then
      Dibs.Midnight.AddSandboxBanner(shell, page, projection)
    end
    Dibs.AceGUI.AddLabel(shell, page, "Provider: " .. tostring(projection.provider) .. " | Role: " .. tostring(projection.role)
      .. " | Coordinator: " .. tostring(projection.coordinatorState), true)
    Dibs.AceGUI.AddLabel(shell, page, "Authority origin: " .. tostring(projection.authorityOrigin)
      .. (projection.fault and " | Fault: " .. tostring(projection.fault) or ""), true)
    local sandbox = Dibs.DeveloperSandbox
    if not projection.active then
      Dibs.AceGUI.AddButton(shell, page, "Enter sandbox (clone)", function() sandbox.EnterSandbox({ clone = true }); refresh() end, 190)
    else
      Dibs.AceGUI.AddButton(shell, page, "Refresh", function() sandbox.RefreshSandbox(); refresh() end, 110)
      Dibs.AceGUI.AddButton(shell, page, "Reset", function() sandbox.ResetSandbox(); refresh() end, 110)
      Dibs.AceGUI.AddButton(shell, page, "Exit sandbox", function() sandbox.ExitSandbox(); refresh() end, 130)
      for _, role in ipairs({ "player", "officer", "guild_master", "coordinator", "recovery" }) do
        Dibs.AceGUI.AddButton(shell, page, "Role: " .. role, function() sandbox.SetRole(role); refresh() end, 140)
      end
    end
  end
  refresh()
  return shell
end

return DeveloperUI