-- Isolated production addon instances, synthetic wire/roster and persisted reloads.
local loader = require("helpers.load_addon")
local M = {}
local function encode(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) ~= "table" then return tostring(value) end
  local keys, parts = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do parts[#parts + 1] = "[" .. encode(key) .. "]=" .. encode(value[key]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

function M.new()
  local world = { clients = {}, packets = {}, clock = 1792000000, epoch = 1,
    names = { "Coordinator-Realm", "Player-Realm", "Officer-Realm" }, online = {}, ranks = { 0, 3, 1 } }
  function world:Save()
    if not self.active then return end
    self.active.saved = self.dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
    self.active.personal = self.dibs.DeepCopy(_G.RCLootCouncil_dibsLocalDB)
  end
  function world:Activate(name)
    self:Save()
    local client = self.clients[name] or { name = name }
    self.clients[name], self.active = client, nil
    local _, dibs = loader.load({ withAce3 = true, skipInitialize = true,
      wow = { playerName = name, playerGUID = "Player-test-" .. name, guildLeader = name == self.names[1],
        guildMembers = self.names, guildRankIndices = self.ranks, guildOnline = self.online },
      savedVariables = client.saved, localVariables = client.personal })
    _G.time = function() return self.clock end
    dibs.Ace3.Serialize = encode
    dibs.Ace3.Deserialize = function(payload)
      local chunk = load("return " .. payload, "synthetic request wire", "t", {})
      return chunk and chunk() or nil
    end
    dibs.Ace3.SendComm = function(prefix, envelope, channel, target)
      self.packets[#self.packets + 1] = { prefix = prefix, payload = encode(envelope),
        channel = channel, target = target, sender = name, envelope = dibs.DeepCopy(envelope) }
      return true
    end
    dibs.Governance.GetAuthorityState = function()
      local coordinator = dibs.Identity.ResolveRosterMember(self.names[1])
      return { state = "ACTIVE", coordinator = { memberKey = coordinator.memberKey,
        displayName = coordinator.displayName }, ledgerEpoch = self.epoch }
    end
    dibs.Initialize()
    self.active, self.dibs = client, dibs
    return dibs
  end
  function world:Advance(seconds) self.clock = self.clock + seconds end
  function world:Hello(name)
    local dibs = self:Activate(name)
    dibs.Sync.Send({ type = "HELLO" }, "GUILD")
    local packets = self.packets
    self.packets = {}
    for _, target in ipairs(self.names) do
      if target ~= name then
        local receiver = self:Activate(target)
        for _, packet in ipairs(packets) do
          if packet.sender == name and packet.envelope.type == "HELLO" then
            receiver.Sync.OnAddonMessage("DIBS", packet.payload, "GUILD", name)
          end
        end
      end
    end
    self.packets = {}
  end
  function world:Deliver(target, packets)
    local dibs = self:Activate(target)
    local results = {}
    for _, packet in ipairs(packets) do
      if packet.target == target then
        results[#results + 1] = { dibs.Sync.OnAddonMessage(packet.prefix, packet.payload, packet.channel, packet.sender) }
      end
    end
    self:Save()
    return dibs, results
  end
  function world:TakePackets()
    local packets = self.packets
    self.packets = {}
    return packets
  end
  return world
end
return M
