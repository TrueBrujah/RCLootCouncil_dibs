# Contract: Independent Raid Session API

**Feature**: `020-multi-ledger-independent-raid`
**Date**: 2026-10-12
**Layer**: Raid Session / Integration (`Dibs.IndependentRaid` & `Dibs.RCLootCouncil`)

## 1. Independent Raid Module (`Dibs.IndependentRaid`)

### 1.1 `Dibs.IndependentRaid.StartSession(sessionName, startingPoints)`
Initializes a new local-only independent raid session on the Master Looter's client.

- **Inputs**:
  - `sessionName` (`string`): Display name for the session (default: `"Independent Raid - [Date]"`).
  - `startingPoints` (`number|nil`): Initial points assigned to each attendee (default: `1`).
- **Returns**: `table` result: `{ ok = boolean, sessionId = string|nil, reasonCode = string|nil }`
- **Side Effects**:
  - Populates `db.independentSessions[sessionId]`.
  - Sets `Dibs.IndependentRaid.GetActiveSessionId() = sessionId`.
  - Inhibits all guild-bound network sync messages for this session.

### 1.2 `Dibs.IndependentRaid.GetActiveSession()`
Returns the active independent session object, or `nil` if none is active.

- **Inputs**: None
- **Returns**: `table|nil` session

### 1.3 `Dibs.IndependentRaid.ConcludeSession(sessionId)`
Marks an active session as concluded, freezing balances and preventing further point deductions.

- **Inputs**:
  - `sessionId` (`string|nil`): Session to conclude (defaults to active session).
- **Returns**: `table` result: `{ ok = boolean, reasonCode = string|nil }`

### 1.4 `Dibs.IndependentRaid.GetPastSessions()`
Returns an array of all past independent raid sessions stored on the local client.

- **Inputs**: None
- **Returns**: `table` array of session summaries.

### 1.5 `Dibs.IndependentRaid.ReconcileAward(actor, sessionId, awardId, targetLedgerId)`
Allows an authorized Officer or GM to import a specific award from an independent session into an official guild ledger.

- **Inputs**:
  - `actor` (`string`): Acting officer.
  - `sessionId` (`string`): Source independent session.
  - `awardId` (`string`): Identifier of the award to import.
  - `targetLedgerId` (`string`): Approved guild ledger to receive the debit.
- **Returns**: `table` result: `{ ok = boolean, transactionId = string|nil, reasonCode = string|nil }`
- **Permissions**: Requires Officer or GM rank.

---

## 2. RCLootCouncil Adapter Integration in Independent Mode

When RCLootCouncil fires `RCMLAwardSuccess`:

```lua
-- Workflow in Dibs.RCLootCouncil.HandleAwardCallback
if Dibs.IndependentRaid and Dibs.IndependentRaid.IsSessionActive() then
  local session = Dibs.IndependentRaid.GetActiveSession()
  local winner = evidence.recipient
  local response = evidence.response

  if isDibResponse(response) then
    local currentBalance = session.balances[winner] or session.startingPoints
    if currentBalance > 0 then
      session.balances[winner] = currentBalance - 1
      session.awards[#session.awards + 1] = {
        awardId = "AWD-" .. time() .. "-" .. #session.awards,
        timestamp = time(),
        recipient = winner,
        itemID = evidence.itemID,
        itemLink = evidence.itemLink,
        response = response,
        dibsSpent = 1,
        reconciled = false,
      }
      return { ok = true, outcome = "independent_consumed", remainingBalance = session.balances[winner] }
    else
      return { ok = false, outcome = "insufficient_points", reasonCode = "INDEPENDENT_NO_POINTS" }
    end
  else
    -- Non-DIB award
    session.awards[#session.awards + 1] = {
      awardId = "AWD-" .. time() .. "-" .. #session.awards,
      timestamp = time(),
      recipient = winner,
      itemID = evidence.itemID,
      itemLink = evidence.itemLink,
      response = response,
      dibsSpent = 0,
      reconciled = false,
    }
    return { ok = true, outcome = "independent_free_award" }
  end
end
```
