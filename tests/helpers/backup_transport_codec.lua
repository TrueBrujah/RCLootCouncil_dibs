local M = {}
local cached
function M.Base64(text)
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local bits = text:gsub(".", function(c)
    local value, result = c:byte(), ""
    for i = 7, 0, -1 do result = result .. (math.floor(value / 2 ^ i) % 2 == 1 and "1" or "0") end
    return result
  end) .. "0000"
  local result = bits:gsub("%d%d%d?%d?%d?%d?", function(group)
    if #group < 6 then return "" end
    local value = 0
    for i = 1, 6 do value = value * 2 + tonumber(group:sub(i, i)) end
    return alphabet:sub(value + 1, value + 1)
  end)
  return result .. ({ "", "==", "=" })[#text % 3 + 1]
end
function M.Native()
  local lib = M.GetLibrary()
  return {
    CompressString = function(text) return lib:CompressDeflate(text) end,
    DecompressString = function(text) return lib:DecompressDeflate(text) end,
    EncodeBase64 = M.Base64,
    DecodeBase64 = function() error("Strict transport decoder should validate Base64 itself") end,
  }
end
function M.Stored(text)
  local parts = {}
  for first = 1, #text, 65535 do
    local block = text:sub(first, first + 65534)
    local size, inverse = #block, 65535 - #block
    parts[#parts + 1] = string.char(first + size > #text and 1 or 0,
      size % 256, math.floor(size / 256), inverse % 256, math.floor(inverse / 256)) .. block
  end
  return table.concat(parts)
end
function M.GetLibrary()
  if cached then return cached end
  local env = setmetatable({ LibStub = false, arg = false }, { __index = _G })
  -- LibDeflate 1.0.2 targets Lua 5.1 doubles. Fengari's Lua 5.3 integers are
  -- 32-bit, so its byte4*16777216 intermediate otherwise overflows before
  -- reaching the floating-point bit cache. Preserve the production numeric
  -- semantics in this isolated environment, without editing the vendor source.
  env.string = setmetatable({ byte = function(...)
    local values = { string.byte(...) }
    for i = 1, #values do values[i] = values[i] * 1.0 end
    return (table.unpack or unpack)(values)
  end }, { __index = string })
  env._G = env
  local chunk, reason
  if setfenv then
    chunk, reason = loadfile("src/libs/LibDeflate/LibDeflate.lua")
    if chunk then setfenv(chunk, env) end
  else chunk, reason = loadfile("src/libs/LibDeflate/LibDeflate.lua", "t", env) end
  assert(chunk, reason)
  cached = chunk()
  return cached
end
function M.Install()
  local original, lib = _G.LibStub, M.GetLibrary()
  _G.LibStub = function(name, silent)
    if name == "LibDeflate" then return lib end
    if original then return original(name, silent) end
  end
  return lib
end
return M
