package.path = "tests/?.lua;tests/?/init.lua;" .. package.path

local suites = {}
local currentSuite = nil
local resetHooks = {}

local function addFailure(message, level)
  error(message or "assertion failed", (level or 1) + 1)
end

function _G.describe(name, body)
  local parent = currentSuite
  local suite = { name = tostring(name), tests = {}, beforeEach = {}, afterEach = {} }
  if parent then
    table.insert(parent.tests, { suite = suite })
  else
    table.insert(suites, suite)
  end
  currentSuite = suite
  body()
  currentSuite = parent
end

function _G.it(name, body)
  if not currentSuite then
    error("it() must be declared inside describe()", 2)
  end
  table.insert(currentSuite.tests, { name = tostring(name), body = body })
end

function _G.before_each(body)
  table.insert(currentSuite.beforeEach, body)
end

function _G.after_each(body)
  table.insert(currentSuite.afterEach, body)
end

function _G.register_reset(body)
  table.insert(resetHooks, body)
end

function _G.assert_true(value, message)
  if value ~= true then addFailure(message or "expected true", 2) end
  return value
end

function _G.assert_false(value, message)
  if value ~= false then addFailure(message or "expected false", 2) end
  return value
end

function _G.assert_nil(value, message)
  if value ~= nil then addFailure(message or ("expected nil, got " .. tostring(value)), 2) end
end

function _G.assert_not_nil(value, message)
  if value == nil then addFailure(message or "expected a non-nil value", 2) end
  return value
end

function _G.assert_equal(expected, actual, message)
  if expected ~= actual then
    addFailure(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)), 2)
  end
  return actual
end

_G.assert_eq = _G.assert_equal

function _G.assert_error(body, message)
  local ok = pcall(body)
  if ok then addFailure(message or "expected an error", 2) end
end

local function discoverTests()
  local explicit = os.getenv("DIBS_TEST_FILES")
  if explicit and explicit ~= "" then
    local result = {}
    for path in string.gmatch(explicit, "[^;]+") do table.insert(result, path) end
    return result
  end

  if io.popen then
    local pipe = io.popen('dir /s /b "tests\\*_spec.lua" 2>nul')
    if pipe then
      local files = {}
      for line in pipe:lines() do
        if line ~= "" then
          local normalized = line:gsub("\\", "/")
          local root = normalized:gsub("/tests/.*$", "")
          normalized = normalized:gsub("^" .. root .. "/", "")
          table.insert(files, normalized)
        end
      end
      pipe:close()
      table.sort(files)
      return files
    end
  end

  error("No test discovery backend available. Set DIBS_TEST_FILES.")
end

local files = discoverTests()
for _, path in ipairs(files) do
  local chunk, loadError = loadfile(path)
  if not chunk then
    io.stderr:write("Unable to load " .. path .. ": " .. tostring(loadError) .. "\n")
    os.exit(1)
  end
  local ok, declarationError = pcall(chunk)
  if not ok then
    io.stderr:write("Unable to declare " .. path .. ": " .. tostring(declarationError) .. "\n")
    os.exit(1)
  end
end

local passed, failed = 0, 0
local function runSuite(suite, prefix, inheritedBefore, inheritedAfter)
  local name = prefix == "" and suite.name or (prefix .. " / " .. suite.name)
  local before = {}
  local after = {}
  for _, hook in ipairs(inheritedBefore or {}) do table.insert(before, hook) end
  for _, hook in ipairs(suite.beforeEach) do table.insert(before, hook) end
  for _, hook in ipairs(suite.afterEach) do table.insert(after, hook) end
  for _, hook in ipairs(inheritedAfter or {}) do table.insert(after, hook) end

  for _, entry in ipairs(suite.tests) do
    if entry.suite then
      runSuite(entry.suite, name, before, after)
    else
      for _, hook in ipairs(resetHooks) do pcall(hook) end
      local ok, testError = pcall(function()
        for _, hook in ipairs(before) do hook() end
        entry.body()
      end)
      for _, hook in ipairs(after) do
        local cleanupOK, cleanupError = pcall(hook)
        if not cleanupOK and ok then ok, testError = false, cleanupError end
      end
      if ok then
        passed = passed + 1
        io.write("PASS " .. name .. " / " .. entry.name .. "\n")
      else
        failed = failed + 1
        io.stderr:write("FAIL " .. name .. " / " .. entry.name .. "\n  " .. tostring(testError) .. "\n")
      end
    end
  end
end

for _, suite in ipairs(suites) do runSuite(suite, "", {}, {}) end

io.write(string.format("\n%d passed, %d failed (%d files)\n", passed, failed, #files))
if failed > 0 then os.exit(1) end
