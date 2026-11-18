local loader = require("helpers.load_addon")
local codecs = require("helpers.backup_transport_codec")

describe("Bounded compressed backup transport", function()
  local dibs, transport, oldNative
  local function wire(raw, encoded, length, sum)
    return "DIBS-COMP-1|" .. tostring(length or #raw) .. "|" .. (sum or dibs.ImportExport.Checksum(raw)) .. "|" .. encoded
  end
  before_each(function()
    oldNative = _G.C_EncodingUtil
    _G.C_EncodingUtil = nil
    _, dibs = loader.load({ wow = { guildLeader = true } })
    codecs.Install()
    transport = dibs.BackupTransport
  end)
  after_each(function() _G.C_EncodingUtil = oldNative end)

  it("round trips real bundled DEFLATE with unchanged original package bytes", function()
    local raw = assert(dibs.ImportExport.Export("local"))
    local encoded, info = assert(transport.Wrap(raw))
    assert_true(encoded:find("DIBS-COMP-1|", 1, true) == 1)
    assert_equal(#raw, info.rawBytes)
    assert_equal(#encoded, info.encodedBytes)
    assert_equal("libdeflate", info.backend)
    assert_equal(raw, assert(transport.Unwrap(encoded)))
    assert_equal(dibs.ImportExport.Decode(raw).checksum, dibs.ImportExport.Decode(encoded).checksum)
  end)

  it("reads independent Node zlib stored and fixed fixtures with standard Base64", function()
    local fixtures = {
      { "DIBS-PKG-1|hello", "ARAA7/9ESUJTLVBLRy0xfGhlbGxv" },
      { "DIBS-PKG-1|hello hello hello", "c/F0CtYN8HbXNazJSM3JyVdAIgE=" },
    }
    for _, fixture in ipairs(fixtures) do assert_equal(fixture[1], assert(transport.Unwrap(wire(fixture[1], fixture[2])))) end
  end)

  it("reads an independent dynamic Huffman fixture", function()
    local raw = "DIBS-PKG-1|" .. string.rep("compressible historical data ", 4000)
    local encoded = "7cm5CYAwAADAVbKAhSuIIGIjOEF8wEBEMZYO7xg2d+21fTNV49BV9bucx3VvpaQ5b2FP5TnvtMQc1vjEIKWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSil/zw8="
    assert_equal(raw, assert(transport.Unwrap(wire(raw, encoded))))
  end)

  it("prefers the native API adapter with real DEFLATE and cross-decodes via fallback", function()
    _G.C_EncodingUtil = codecs.Native()
    local raw = "DIBS-PKG-1|" .. string.rep("native interop ", 100)
    local encoded, info = assert(transport.Wrap(raw))
    assert_equal("native", info.backend)
    _G.C_EncodingUtil = nil
    assert_equal(raw, assert(transport.Unwrap(encoded)))
  end)

  it("rejects expansion beyond declared size before allocating decompression", function()
    local raw = "DIBS-PKG-1|" .. string.rep("x", 100000)
    local compressed = codecs.GetLibrary():CompressDeflate(raw)
    local calls = 0
    _G.C_EncodingUtil = codecs.Native()
    _G.C_EncodingUtil.DecompressString = function() calls = calls + 1; error("must not run") end
    local result, reason = transport.Unwrap(wire(raw, codecs.Base64(compressed), 20))
    assert_nil(result)
    assert_equal("DECOMPRESSED_SIZE_LIMIT", reason)
    assert_equal(0, calls)
  end)

  it("rejects invalid headers, versions, Base64 and raw budget before decompression", function()
    local calls = 0
    _G.C_EncodingUtil = codecs.Native()
    _G.C_EncodingUtil.DecompressString = function() calls = calls + 1 end
    for _, text in ipairs({
      "DIBS-COMP-2|16|00000000|AAAA", "DIBS-COMP-1|033|00000000|AAAA",
      "DIBS-COMP-1|33554433|00000000|AAAA", "DIBS-COMP-1|16|00000000|A===",
      "DIBS-COMP-1|16|00000000|AA=A", "DIBS-COMP-1|16|00000000|AB==",
      "DIBS-COMP-1|16|00000000|AA!A", string.rep("x", 250001),
    }) do assert_nil(transport.Unwrap(text)) end
    assert_equal(0, calls)
  end)

  it("rejects truncated, reserved and trailing-data streams before decompression", function()
    local raw = "DIBS-PKG-1|hello"
    for _, encoded in ipairs({ "Bw==", "ARAA7/9ESQ==", "ARAA7/9ESUJTLVBLRy0xfGhlbGxvAA==" }) do
      assert_nil(transport.Unwrap(wire(raw, encoded)))
    end
  end)

  it("checks returned length/checksum and catches native decompressor failures", function()
    local raw = "DIBS-PKG-1|hello"
    local encoded = wire(raw, "ARAA7/9ESUJTLVBLRy0xfGhlbGxv")
    _G.C_EncodingUtil = codecs.Native()
    _G.C_EncodingUtil.DecompressString = function() return raw .. "x" end
    assert_nil(transport.Unwrap(encoded))
    _G.C_EncodingUtil.DecompressString = function() return raw:sub(1, -2) .. "!" end
    local result, reason = transport.Unwrap(encoded)
    assert_nil(result); assert_equal("TRANSPORT_CHECKSUM_MISMATCH", reason)
    _G.C_EncodingUtil.DecompressString = function() error("runtime error") end
    result, reason = transport.Unwrap(encoded)
    assert_nil(result); assert_equal("DECOMPRESSION_FAILED", reason)
  end)

  it("reports unavailable/partial native capability and catches encoder failures", function()
    local raw = "DIBS-PKG-1|hello"
    _G.LibStub, _G.C_EncodingUtil = nil, { CompressString = function() end }
    assert_false(transport.GetStatus().available)
    local result, reason = transport.Wrap(raw)
    assert_nil(result); assert_equal("COMPRESSION_UNAVAILABLE", reason)
    _G.C_EncodingUtil = codecs.Native()
    _G.C_EncodingUtil.CompressString = function() error("runtime error") end
    assert_nil(transport.Wrap(raw))
    _G.C_EncodingUtil = codecs.Native()
    _G.C_EncodingUtil.EncodeBase64 = function() return "bad!" end
    assert_nil(transport.Wrap(raw))
  end)

  it("rejects nested transport as inner data and retains the portable cap", function()
    local nested = "DIBS-COMP-1|16|00000000|AAAA"
    local compressed = codecs.GetLibrary():CompressDeflate(nested)
    local result, reason = transport.Unwrap(wire(nested, codecs.Base64(compressed)))
    assert_nil(result); assert_equal("INVALID_INNER_PACKAGE", reason)
    assert_nil(transport.Wrap(nested))
    assert_equal(250000, transport.MAX_ENCODED_SIZE)
    assert_equal(32 * 1024 * 1024, transport.MAX_RAW_SIZE)
  end)

  it("accepts exactly 250000 encoded characters and refuses the next encoded quartet", function()
    _G.C_EncodingUtil = codecs.Native()
    _G.C_EncodingUtil.CompressString = codecs.Stored
    local raw = "DIBS-PKG-1|" .. string.rep("x", 187453)
    local encoded = assert(transport.Wrap(raw))
    assert_equal(250000, #encoded)
    assert_equal(raw, assert(transport.Unwrap(encoded)))
    local text, reason = transport.Wrap(raw .. "x")
    assert_nil(text); assert_equal("PACKAGE_TOO_LARGE", reason)
  end)
end)
