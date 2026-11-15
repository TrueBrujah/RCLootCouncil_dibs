-- Portable transport only: inner package bytes and accounting semantics are unchanged.
local Dibs = _G.Dibs
local M = {}
Dibs.BackupTransport = M
M.PREFIX = "DIBS-COMP-1|"
M.MAX_ENCODED_SIZE = 250000
M.MAX_RAW_SIZE = 32 * 1024 * 1024
local RAW_PREFIX = "DIBS-PKG-1|"
local floor, char, byte = math.floor, string.char, string.byte
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local alphabetValues = {}
for i = 1, #alphabet do alphabetValues[alphabet:sub(i, i)] = i - 1 end

local function encode64(text)
  local out = {}
  for i = 1, #text, 3 do
    local a, b, c = byte(text, i), byte(text, i + 1), byte(text, i + 2)
    local value = a * 65536 + (b or 0) * 256 + (c or 0)
    out[#out + 1] = alphabet:sub(floor(value / 262144) + 1, floor(value / 262144) + 1)
      .. alphabet:sub(floor(value / 4096) % 64 + 1, floor(value / 4096) % 64 + 1)
      .. (b and alphabet:sub(floor(value / 64) % 64 + 1, floor(value / 64) % 64 + 1) or "=")
      .. (c and alphabet:sub(value % 64 + 1, value % 64 + 1) or "=")
  end
  return table.concat(out)
end

local function decode64(text)
  if #text == 0 or #text % 4 ~= 0 or text:find("[^A-Za-z0-9+/=]") then return nil end
  local out = {}
  for i = 1, #text, 4 do
    local a, b = alphabetValues[text:sub(i, i)], alphabetValues[text:sub(i + 1, i + 1)]
    local cs, ds = text:sub(i + 2, i + 2), text:sub(i + 3, i + 3)
    local c, d = alphabetValues[cs], alphabetValues[ds]
    if not a or not b then return nil end
    if cs == "=" then
      if ds ~= "=" or i + 3 ~= #text or b % 16 ~= 0 then return nil end
      out[#out + 1] = char(a * 4 + floor(b / 16))
    elseif ds == "=" then
      if not c or i + 3 ~= #text or c % 4 ~= 0 then return nil end
      local value = a * 262144 + b * 4096 + c * 64
      out[#out + 1] = char(floor(value / 65536), floor(value / 256) % 256)
    else
      if not c or not d then return nil end
      local value = a * 262144 + b * 4096 + c * 64 + d
      out[#out + 1] = char(floor(value / 65536), floor(value / 256) % 256, value % 256)
    end
  end
  return table.concat(out)
end

local function backend()
  local native = _G.C_EncodingUtil
  if type(native) == "table" and type(native.CompressString) == "function"
    and type(native.DecompressString) == "function" and type(native.EncodeBase64) == "function"
    and type(native.DecodeBase64) == "function" then return "native", native end
  local stub = _G.LibStub
  if stub then
    local ok, lib = pcall(function() return stub("LibDeflate", true) end)
    if ok and type(lib) == "table" and type(lib.CompressDeflate) == "function"
      and type(lib.DecompressDeflate) == "function" then return "libdeflate", lib end
  end
end
function M.GetStatus()
  local name = backend()
  return { available = name ~= nil, backend = name }
end

-- RFC 1951 preflight: count expanded bytes without building the expanded string.
-- The native and bundled decompressors have no output-limit parameter. Never call
-- them for untrusted input until this pass has established the actual output budget.
local LENGTH_BASE = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local LENGTH_BITS = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local DIST_BASE = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local DIST_BITS = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local CODE_ORDER = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}

local function preflight(input, expected)
  local position, offset, produced, work = 1, 0, 0, 0
  local workLimit = #input * 64 + 4096
  local function tick(n)
    work = work + (n or 1)
    if work > workLimit then error("DEFLATE_WORK_LIMIT", 0) end
  end
  local function bits(n)
    tick()
    local result, shift = 0, 0
    while n > 0 do
      local current = byte(input, position)
      if not current then error("INVALID_DEFLATE", 0) end
      local take = math.min(n, 8 - offset)
      result = result + floor(current / 2 ^ offset) % 2 ^ take * 2 ^ shift
      offset, n, shift = offset + take, n - take, shift + take
      if offset == 8 then position, offset = position + 1, 0 end
    end
    return result
  end
  local function tree(lengths, count, singleAllowed, emptyAllowed)
    local counts, nextCode, nodes, total, maxLength = {}, {}, {}, 0, 0
    for symbol = 0, count - 1 do
      tick()
      local length = lengths[symbol] or 0
      if length < 0 or length > 15 then error("INVALID_DEFLATE", 0) end
      if length > 0 then counts[length] = (counts[length] or 0) + 1; total = total + 1; maxLength = math.max(maxLength, length) end
    end
    if total == 0 then
      if emptyAllowed then return { codes = {}, max = 0 } end
      error("INVALID_DEFLATE", 0)
    end
    local remaining, code = 1, 0
    for length = 1, 15 do
      remaining = remaining * 2 - (counts[length] or 0)
      if remaining < 0 then error("INVALID_DEFLATE", 0) end
      code = (code + (counts[length - 1] or 0)) * 2
      nextCode[length] = code
    end
    if remaining ~= 0 and not (singleAllowed and total == 1 and maxLength == 1) then error("INVALID_DEFLATE", 0) end
    for symbol = 0, count - 1 do
      local length = lengths[symbol] or 0
      if length > 0 then
        nodes[length] = nodes[length] or {}
        nodes[length][nextCode[length]] = symbol
        nextCode[length] = nextCode[length] + 1
      end
    end
    return { codes = nodes, max = maxLength }
  end
  local function symbol(codeTree)
    local code = 0
    for length = 1, codeTree.max do
      code = code * 2 + bits(1)
      local value = codeTree.codes[length] and codeTree.codes[length][code]
      if value ~= nil then return value end
    end
    error("INVALID_DEFLATE", 0)
  end
  local function add(n)
    produced = produced + n
    if produced > expected or produced > M.MAX_RAW_SIZE then error("DECOMPRESSED_SIZE_LIMIT", 0) end
  end
  local final = 0
  repeat
    tick()
    final = bits(1)
    local kind = bits(2)
    if kind == 0 then
      if offset ~= 0 then bits(8 - offset) end
      local length, complement = bits(16), bits(16)
      if length + complement ~= 65535 or position + length - 1 > #input then error("INVALID_DEFLATE", 0) end
      add(length); position = position + length
    elseif kind == 1 or kind == 2 then
      local literalTree, distanceTree
      if kind == 1 then
        local literalLengths, distanceLengths = {}, {}
        for i = 0, 287 do literalLengths[i] = i <= 143 and 8 or (i <= 255 and 9 or (i <= 279 and 7 or 8)) end
        for i = 0, 31 do distanceLengths[i] = 5 end
        literalTree, distanceTree = tree(literalLengths, 288), tree(distanceLengths, 32)
      else
        local literalCount, distanceCount, codeCount = bits(5) + 257, bits(5) + 1, bits(4) + 4
        if literalCount > 286 then error("INVALID_DEFLATE", 0) end
        local codeLengths = {}
        for i = 1, codeCount do codeLengths[CODE_ORDER[i]] = bits(3) end
        local codeTree = tree(codeLengths, 19)
        local lengths, index, previous = {}, 0, nil
        while index < literalCount + distanceCount do
          local value, repetitions = symbol(codeTree), 1
          if value == 16 then
            if previous == nil then error("INVALID_DEFLATE", 0) end
            value, repetitions = previous, bits(2) + 3
          elseif value == 17 then value, repetitions = 0, bits(3) + 3
          elseif value == 18 then value, repetitions = 0, bits(7) + 11 end
          if index + repetitions > literalCount + distanceCount then error("INVALID_DEFLATE", 0) end
          for _ = 1, repetitions do tick(); lengths[index] = value; index = index + 1 end
          previous = value
        end
        if (lengths[256] or 0) == 0 then error("INVALID_DEFLATE", 0) end
        local distances = {}
        for i = 0, distanceCount - 1 do distances[i] = lengths[literalCount + i] end
        literalTree, distanceTree = tree(lengths, literalCount, true), tree(distances, distanceCount, true, true)
      end
      while true do
        local value = symbol(literalTree)
        if value < 256 then add(1)
        elseif value == 256 then break
        elseif value <= 285 then
          local index = value - 256
          local length = LENGTH_BASE[index] + bits(LENGTH_BITS[index])
          local distanceCode = symbol(distanceTree)
          if distanceCode > 29 then error("INVALID_DEFLATE", 0) end
          local distance = DIST_BASE[distanceCode + 1] + bits(DIST_BITS[distanceCode + 1])
          if distance > produced then error("INVALID_DEFLATE", 0) end
          add(length)
        else error("INVALID_DEFLATE", 0) end
      end
    else error("INVALID_DEFLATE", 0) end
  until final == 1
  if position + (offset > 0 and 1 or 0) ~= #input + 1 then error("DEFLATE_TRAILING_DATA", 0) end
  if produced ~= expected then error("DECOMPRESSED_LENGTH_MISMATCH", 0) end
  return true
end

local function checksum(text)
  return Dibs.ImportExport.Checksum(text)
end
function M.Wrap(raw)
  if type(raw) ~= "string" or raw:sub(1, #RAW_PREFIX) ~= RAW_PREFIX then return nil, "INVALID_INNER_PACKAGE" end
  if #raw > M.MAX_RAW_SIZE then return nil, "DECOMPRESSED_SIZE_LIMIT" end
  local name, codec = backend()
  if not name then return nil, "COMPRESSION_UNAVAILABLE" end
  local ok, compressed = pcall(function()
    if name == "native" then return codec.CompressString(raw) end
    return codec:CompressDeflate(raw)
  end)
  if not ok or type(compressed) ~= "string" then return nil, "COMPRESSION_FAILED" end
  local verified = pcall(preflight, compressed, #raw)
  if not verified then return nil, "COMPRESSION_FAILED" end
  local encoded
  if name == "native" then
    ok, encoded = pcall(codec.EncodeBase64, compressed)
    if not ok or type(encoded) ~= "string" or decode64(encoded) ~= compressed then return nil, "BASE64_ENCODING_FAILED" end
  else encoded = encode64(compressed) end
  local wire = M.PREFIX .. tostring(#raw) .. "|" .. checksum(raw) .. "|" .. encoded
  if #wire > M.MAX_ENCODED_SIZE then return nil, "PACKAGE_TOO_LARGE" end
  return wire, { rawBytes = #raw, encodedBytes = #wire, backend = name }
end
function M.Unwrap(wire)
  if type(wire) ~= "string" or #wire > M.MAX_ENCODED_SIZE then return nil, "INVALID_PACKAGE_SIZE" end
  if wire:sub(1, #M.PREFIX) ~= M.PREFIX then return nil, "UNSUPPORTED_TRANSPORT_VERSION" end
  local lengthText, expectedChecksum, encoded = wire:sub(#M.PREFIX + 1):match("^(%d+)|([0-9a-f]+)|(.+)$")
  local length = tonumber(lengthText)
  if not length or lengthText ~= tostring(length) or length < #RAW_PREFIX or length > M.MAX_RAW_SIZE
    or not expectedChecksum or #expectedChecksum ~= 8 then return nil, "INVALID_TRANSPORT_HEADER" end
  local compressed = decode64(encoded)
  if not compressed then return nil, "INVALID_BASE64" end
  local verified, reason = pcall(preflight, compressed, length)
  if not verified then return nil, tostring(reason) end
  local name, codec = backend()
  if not name then return nil, "COMPRESSION_UNAVAILABLE" end
  local ok, raw = pcall(function()
    if name == "native" then return codec.DecompressString(compressed) end
    local text, remaining = codec:DecompressDeflate(compressed)
    if remaining ~= 0 then return nil end
    return text
  end)
  if not ok or type(raw) ~= "string" then return nil, "DECOMPRESSION_FAILED" end
  if #raw ~= length or #raw > M.MAX_RAW_SIZE then return nil, "DECOMPRESSED_LENGTH_MISMATCH" end
  if checksum(raw) ~= expectedChecksum then return nil, "TRANSPORT_CHECKSUM_MISMATCH" end
  if raw:sub(1, #RAW_PREFIX) ~= RAW_PREFIX then return nil, "INVALID_INNER_PACKAGE" end
  return raw, { rawBytes = #raw, encodedBytes = #wire, backend = name }
end
return M
