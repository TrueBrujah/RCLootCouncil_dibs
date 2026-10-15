local Dibs = _G.Dibs
Dibs.HistoryFilters = Dibs.HistoryFilters or {}

local Filters = Dibs.HistoryFilters

local DEFAULT_FIELDS = {
  item = { "itemName", "itemLink", "itemID" },
  playerName = { "playerName", "playerKey" },
  raid = { "raidName", "instanceName" },
  boss = { "bossName", "encounterName" },
  status = { "status", "verificationState", "state" },
  source = { "source" },
  seasonId = { "seasonId" },
}

local DEFAULT_QUERY_FIELDS = {
  "itemName", "itemLink", "itemID", "playerName", "playerKey", "source",
  "status", "verificationState", "state", "raidName", "instanceName",
  "bossName", "encounterName",
}

local DEFAULT_TIMESTAMP_FIELDS = { "createdAt", "timestamp", "acquiredAt", "awardedAt" }
local DEFAULT_IDENTITY_FIELDS = { "transactionId", "acquisitionId", "requestId", "candidateId", "id" }

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function contains(value, query)
  if value == nil then return false end
  return string.find(string.lower(tostring(value)), string.lower(query), 1, true) ~= nil
end

local function matchesAnyField(record, fieldNames, query)
  for _, fieldName in ipairs(fieldNames or {}) do
    if contains(record[fieldName], query) then return true end
  end
  return false
end

local function parseDate(value)
  local text = trim(value)
  if text == "" then return nil end
  local year, month, day = text:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  if not year or year < 1 or not month or month < 1 or month > 12 then
    return nil, "INVALID_DATE"
  end
  local daysInMonth = { 31, (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) and 29 or 28,
    31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if not day or day < 1 or day > daysInMonth[month] then return nil, "INVALID_DATE" end
  if type(time) ~= "function" then return nil, "DATE_UNAVAILABLE" end
  local timestamp = time({ year = year, month = month, day = day, hour = 0, min = 0, sec = 0 })
  if type(timestamp) ~= "number" then return nil, "DATE_UNAVAILABLE" end
  local nextDay = time({ year = year, month = month, day = day + 1, hour = 0, min = 0, sec = 0 })
  if type(nextDay) ~= "number" then return nil, "DATE_UNAVAILABLE" end
  return { start = timestamp, endExclusive = nextDay }
end

local function getTimestamp(record, fields)
  for _, fieldName in ipairs(fields or DEFAULT_TIMESTAMP_FIELDS) do
    local value = tonumber(record[fieldName])
    if value then return value end
  end
end

local function getIdentity(record, fields)
  for _, fieldName in ipairs(fields or DEFAULT_IDENTITY_FIELDS) do
    local value = record[fieldName]
    if value ~= nil and tostring(value) ~= "" then return tostring(value) end
  end
  return ""
end

local function dateMatches(record, range, timestampFields)
  if not range.from and not range.to then return true end
  local timestamp = getTimestamp(record, timestampFields)
  if not timestamp then return false end
  if range.from and timestamp < range.from then return false end
  if range.to and timestamp >= range.to then return false end
  return true
end

local function recordMatches(record, criteria, options, range)
  local fieldMap = options.fieldMap or DEFAULT_FIELDS
  local query = trim(criteria.query)
  if query ~= "" and not matchesAnyField(record, options.queryFields or DEFAULT_QUERY_FIELDS, query) then
    return false
  end

  for _, fieldName in ipairs({ "item", "playerName", "raid", "boss", "status", "source" }) do
    local value = trim(criteria[fieldName])
    if value ~= "" and not matchesAnyField(record, fieldMap[fieldName] or {}, value) then
      return false
    end
  end

  local seasonId = trim(criteria.seasonId)
  if seasonId ~= "" and not matchesAnyField(record, fieldMap.seasonId or {}, seasonId) then return false end
  return dateMatches(record, range, options.timestampFields)
end

function Filters.FilterRecords(records, criteria, options)
  if type(records) ~= "table" then return nil, "INVALID_RECORDS" end
  criteria = type(criteria) == "table" and criteria or {}
  options = type(options) == "table" and options or {}

  local range = {}
  local fromDate = trim(criteria.fromDate)
  if fromDate ~= "" then
    local parsed, reason = parseDate(fromDate)
    if not parsed then return nil, reason == "DATE_UNAVAILABLE" and reason or "INVALID_FROM_DATE" end
    range.from = parsed.start
  end
  local toDate = trim(criteria.toDate)
  if toDate ~= "" then
    local parsed, reason = parseDate(toDate)
    if not parsed then return nil, reason == "DATE_UNAVAILABLE" and reason or "INVALID_TO_DATE" end
    range.to = parsed.endExclusive
    range.toDateStart = parsed.start
  end
  if range.from and range.toDateStart and range.from > range.toDateStart then
    return nil, "INVALID_DATE_RANGE"
  end

  local sorted = {}
  for index, record in ipairs(records) do
    if type(record) == "table" and recordMatches(record, criteria, options, range) then
      sorted[#sorted + 1] = {
        record = record,
        index = index,
        timestamp = getTimestamp(record, options.timestampFields) or 0,
        identity = getIdentity(record, options.identityFields),
      }
    end
  end
  table.sort(sorted, function(first, second)
    if first.timestamp ~= second.timestamp then return first.timestamp > second.timestamp end
    if first.identity ~= second.identity then return first.identity < second.identity end
    return first.index < second.index
  end)

  local result = {}
  for _, entry in ipairs(sorted) do result[#result + 1] = entry.record end
  return result
end

function Filters.ParseDate(value)
  local parsed, reason = parseDate(value)
  if not parsed then return nil, reason end
  return parsed.start, parsed.endExclusive
end
