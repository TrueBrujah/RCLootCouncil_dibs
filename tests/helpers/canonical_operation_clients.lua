local host = _G
local disputeFixtures = host.require("helpers.dispute_fixtures")
local M = {}

local function isClientGlobal(name)
  return name == "Dibs"
    or name == "DibsDB"
    or name == "RCLootCouncil"
    or (type(name) == "string" and (name:match("^Dibs") or name:match("^RCLootCouncil_dibs")))
end

local function clone(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do
    result[clone(key, seen)] = clone(item, seen)
  end
  return result
end

local function sameValue(first, second, seen)
  if type(first) ~= type(second) then return false end
  if type(first) ~= "table" then return first == second end
  seen = seen or {}
  if seen[first] == second then return true end
  seen[first] = second
  for key, value in pairs(first) do
    if not sameValue(value, second[key], seen) then return false end
  end
  for key in pairs(second) do
    if first[key] == nil then return false end
  end
  return true
end

local function encode(value, active)
  local valueType = type(value)
  if valueType == "string" then return string.format("%q", value) end
  if valueType == "number" or valueType == "boolean" then return tostring(value) end
  if valueType ~= "table" then error("unsupported wire value: " .. valueType, 2) end

  active = active or {}
  if active[value] then error("cyclic wire value", 2) end
  active[value] = true
  local keys, parts = {}, {}
  for key in pairs(value) do
    if type(key) ~= "number" and type(key) ~= "string" then
      error("unsupported wire key: " .. type(key), 2)
    end
    keys[#keys + 1] = key
  end
  table.sort(keys, function(first, second)
    if type(first) ~= type(second) then return type(first) < type(second) end
    return first < second
  end)
  for _, key in ipairs(keys) do
    parts[#parts + 1] = "[" .. encode(key, active) .. "]=" .. encode(value[key], active)
  end
  active[value] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end

local function decode(payload)
  local chunk, loadError = host.load("return " .. payload, "canonical client wire", "t", {})
  if not chunk then return nil, loadError end
  local ok, value = pcall(chunk)
  if not ok then return nil, value end
  return value
end

local function makeEnvironment()
  local environment = {}
  setmetatable(environment, {
    __index = function(_, name)
      if isClientGlobal(name) then return nil end
      return host[name]
    end,
  })
  environment._G = environment
  environment.register_reset = function() end
  environment.require = function(name)
    if name == "helpers.wow_api" then
      local chunk, loadError = host.loadfile("tests/helpers/wow_api.lua", "t", environment)
      if not chunk then error(loadError, 2) end
      return chunk()
    end
    return host.require(name)
  end
  return environment
end

local function normalizeName(name)
  return tostring(name or ""):gsub("%s+", ""):lower()
end

function M.new(options)
  options = options or {}
  local world = {
    clients = {},
    packets = {},
    deliveries = {},
    names = options.names or { "Coordinator-Realm", "Player-Realm", "Officer-Realm" },
    ranks = options.ranks or { [1] = 0, [2] = 3, [3] = 1 },
    online = options.online or { [1] = true, [2] = true, [3] = true },
  }

  function world:Load(name, savedVariables)
    assert(self.clients[name] == nil, "client already loaded: " .. tostring(name))
    local environment = makeEnvironment()
    local loaderChunk, loaderError = host.loadfile("tests/helpers/load_addon.lua", "t", environment)
    if not loaderChunk then error(loaderError, 2) end
    local loader = loaderChunk()
    local roster = {}
    for index, memberName in ipairs(self.names) do
      roster[index] = memberName
    end
    local _, dibs = loader.load({
      withAce3 = true,
      environment = environment,
      savedVariables = clone(savedVariables),
      wow = {
        playerName = name,
        playerGUID = "Player-RF0012-" .. name,
        guildLeader = name == self.names[1],
        guildMembers = roster,
        guildRankIndices = clone(self.ranks),
        guildOnline = clone(self.online),
      },
    })
    if not dibs then error("Dibs failed to initialize for " .. tostring(name), 2) end

    local client = {
      name = name,
      env = environment,
      dibs = dibs,
      failureInjector = disputeFixtures.newFailureInjector(),
    }
    dibs.Ace3.Serialize = encode
    dibs.Ace3.Deserialize = function(payload)
      return decode(payload)
    end
    dibs.Ace3.SendComm = function(prefix, envelope, channel, target)
      if type(envelope) ~= "table" then return false, "INVALID_TEST_ENVELOPE" end
      local ok, payload = pcall(encode, envelope)
      if not ok then return false, tostring(payload) end
      self.packets[#self.packets + 1] = {
        prefix = prefix,
        payload = payload,
        channel = channel,
        target = target,
        sender = name,
      }
      return true
    end
    self.clients[name] = client
    return client
  end

  function world:ActivateV2()
    local coordinator = self.clients[self.names[1]] or self:Load(self.names[1])
    local dibs = coordinator.dibs
    assert(dibs.Governance.AdoptInitial(nil, { reason = "RF-0012 test authority" }))
    local baseline = assert(dibs.HistoricalBaseline.FinalizeBaseline(nil))
    local identity = assert(dibs.Identity.CreateSnapshot(self.names[1]))
    assert(dibs.Governance.Change(nil, { future = { authority = {
      schema = 1,
      state = "ACTIVE",
      coordinator = identity,
      ledgerEpoch = 7,
      transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
    } } }))
    assert(dibs.Governance.EnableV2(nil, { self.names[1] }))
    assert(dibs.Governance.IsV2Enforced())
    assert(dibs.Seasons.Create("RF-0012 test season"))
    assert(dibs.Ledger.Grant(
      self.names[2],
      1,
      "RF-0012 test allocation",
      "test",
      dibs.GetCurrentSeasonId()
    ))
    self:TakePackets()
    return coordinator
  end

  function world:ArmFailure(name, point)
    local client = assert(self.clients[name], "unknown test client: " .. tostring(name))
    client.failureInjector:Arm(point)
  end

  function world:HitFailure(name, point)
    local client = assert(self.clients[name], "unknown test client: " .. tostring(name))
    return client.failureInjector:Hit(point)
  end

  function world:ResetFailures(name)
    local client = assert(self.clients[name], "unknown test client: " .. tostring(name))
    client.failureInjector:Reset()
  end

  function world:TakePackets()
    local packets = self.packets
    self.packets = {}
    return packets
  end

  -- RF-0035 helper: a client that is "offline" does not receive any
  -- packet. The packets stay queued in the world, exactly like a message
  -- that crossed the network while the client was disconnected.
  function world:SetOnline(name, online)
    self.onlineState = self.onlineState or {}
    self.onlineState[name] = online ~= false
  end

  function world:IsOnline(name)
    local state = self.onlineState or {}
    if state[name] == nil then return true end
    return state[name] == true
  end

  -- Delivers a single round of queued packets. The packets queued by the
  -- handlers of this round are left for the next call, so an intermediate
  -- state can be observed.
  function world:DeliverOnce()
    if #self.packets == 0 then return 0 end
    local batch = self.packets
    self.packets = {}
    local held = {}
    local deliveredCount = 0
    for _, packet in ipairs(batch) do
      local recipients = {}
      if packet.channel == "GUILD" then
        for name in pairs(self.clients) do
          if name ~= packet.sender then recipients[#recipients + 1] = name end
        end
      elseif packet.channel == "WHISPER" then
        for name in pairs(self.clients) do
          if normalizeName(name) == normalizeName(packet.target) then recipients[#recipients + 1] = name end
        end
      else
        error("unsupported test transport channel: " .. tostring(packet.channel), 2)
      end
      table.sort(recipients)
      local pending = {}
      for _, name in ipairs(recipients) do
        if self:IsOnline(name) then
          local receiver = self.clients[name]
          local accepted, reason = receiver.dibs.Sync.OnAddonMessage(
            packet.prefix, packet.payload, packet.channel, packet.sender)
          self.deliveries[#self.deliveries + 1] = {
            sender = packet.sender, receiver = name, accepted = accepted, reason = reason,
          }
          deliveredCount = deliveredCount + 1
        else
          pending[#pending + 1] = name
        end
      end
      if #pending > 0 then held[#held + 1] = packet end
    end
    for _, packet in ipairs(held) do self.packets[#self.packets + 1] = packet end
    return deliveredCount
  end

  -- Delivers every queued packet to the online recipients. A packet whose
  -- only recipients are offline is kept for a later round, so a real
  -- disconnection does not silently drop the message.
  --
  -- A packet that still has an offline recipient is **not** re-queued in
  -- the same call: it would be redelivered on every round and the
  -- delivery would never quiesce. The held packets stay in the queue for
  -- the next `Deliver` or `Reconnect` call.
  function world:Deliver(maxRounds)
    maxRounds = maxRounds or 50
    local deliveredCount = 0
    for _ = 1, maxRounds do
      if #self.packets == 0 then return deliveredCount end
      local batch = self.packets
      self.packets = {}
      local held = {}
      for _, packet in ipairs(batch) do
        local recipients = {}
        if packet.channel == "GUILD" then
          for name in pairs(self.clients) do
            if name ~= packet.sender then recipients[#recipients + 1] = name end
          end
        elseif packet.channel == "WHISPER" then
          for name in pairs(self.clients) do
            if normalizeName(name) == normalizeName(packet.target) then recipients[#recipients + 1] = name end
          end
        else
          error("unsupported test transport channel: " .. tostring(packet.channel), 2)
        end
        table.sort(recipients)
        local pending = {}
        for _, name in ipairs(recipients) do
          if self:IsOnline(name) then
            local receiver = self.clients[name]
            local accepted, reason = receiver.dibs.Sync.OnAddonMessage(
              packet.prefix,
              packet.payload,
              packet.channel,
              packet.sender
            )
            self.deliveries[#self.deliveries + 1] = {
              sender = packet.sender,
              receiver = name,
              accepted = accepted,
              reason = reason,
            }
            deliveredCount = deliveredCount + 1
          else
            pending[#pending + 1] = name
          end
        end
        -- A packet that still has an offline recipient is held for the
        -- reconnection.
        if #pending > 0 then held[#held + 1] = packet end
      end
      -- The handlers queued their answers in `self.packets` while the
      -- batch was being delivered. They are delivered in the next round,
      -- so a request/response exchange settles.
      self.held = self.held or {}
      for _, packet in ipairs(held) do self.held[#self.held + 1] = packet end
    end
    return deliveredCount
  end

  -- Delivers the packets that were held for an offline client, simulating
  -- the reconnection.
  function world:Reconnect(name)
    self:SetOnline(name, true)
    -- The packets held while the client was offline go back into the
    -- queue, together with the packets the other clients queued in the
    -- meantime.
    local held = self.held or {}
    self.held = {}
    for _, packet in ipairs(held) do self.packets[#self.packets + 1] = packet end
    return self:Deliver()
  end

  function world:Snapshot(client)
    return clone(client.env.RCLootCouncil_dibsDB)
  end

  function world:Pump(maxRounds)
    maxRounds = maxRounds or 50
    local deliveredCount = 0
    for _ = 1, maxRounds do
      if #self.packets == 0 then return deliveredCount end
      local packets = self:TakePackets()
      for _, packet in ipairs(packets) do
        if type(packet.payload) ~= "string" then error("non-serialized packet in test queue", 2) end
        local recipients = {}
        if packet.channel == "GUILD" then
          for name in pairs(self.clients) do
            if name ~= packet.sender then recipients[#recipients + 1] = name end
          end
        elseif packet.channel == "WHISPER" then
          for name in pairs(self.clients) do
            if normalizeName(name) == normalizeName(packet.target) then recipients[#recipients + 1] = name end
          end
        else
          error("unsupported test transport channel: " .. tostring(packet.channel), 2)
        end
        if #recipients == 0 then error("no test client receives packet from " .. tostring(packet.sender), 2) end
        table.sort(recipients)
        for _, name in ipairs(recipients) do
          local receiver = self.clients[name]
          local accepted, reason = receiver.dibs.Sync.OnAddonMessage(
            packet.prefix,
            packet.payload,
            packet.channel,
            packet.sender
          )
          self.deliveries[#self.deliveries + 1] = {
            sender = packet.sender,
            receiver = name,
            accepted = accepted,
            reason = reason,
          }
          deliveredCount = deliveredCount + 1
        end
      end
    end
    error("serialized message queue did not quiesce after " .. tostring(maxRounds) .. " rounds", 2)
  end

  return world
end

M.DeepEqual = sameValue
M.DeepCopy = clone

return M
