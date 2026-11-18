local M = {}

-- Private test seams, available only through Lua debug introspection. There is
-- deliberately no production setting that can enable these release gates.
function M.setUpvalue(writer, name, value)
  for index = 1, 64 do
    local key = debug.getupvalue(writer, index)
    if not key then break end
    if key == name then debug.setupvalue(writer, index, value); return end
  end
  error("Missing canonical test seam: " .. name)
end

function M.enable(dibs)
  dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
  M.setUpvalue(dibs.Ledger.CommitDisputeOperation, "DISPUTE_OPERATION_WRITES_ENABLED", true)
end

function M.activate(dibs)
  require("helpers.configured_addon").foundation(dibs)
  local baseline = assert(dibs.HistoricalBaseline.GetBaseline())
  assert_true(dibs.Governance.Change(nil, { future = { authority = {
    schema = 1, state = "ACTIVE", coordinator = assert(dibs.Identity.CreateSnapshot(dibs.GetPlayerName())),
    ledgerEpoch = 1, transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
  } } }))
  assert_true(dibs.Governance.EnableV2(nil, { dibs.GetPlayerName() }))
  M.enable(dibs)
end

return M
