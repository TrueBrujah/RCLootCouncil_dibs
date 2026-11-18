# Guided Setup Projection and Orchestration Contract

## `Dibs.Wizard.GetNavigationAccess(actor?, dbOverride?)`

Read-only presentation projection, without persisted completion markers or
administrative payloads. Returns `firstInstall`, `foundationReady`, `sections`,
`routes` (set of allowed Officer route IDs), `reasonCode`, `dependencies`
(`seasonConfigured`, `rosterConfigured`, `ranksPublished`, `ledgerReady`) and `preservedHistory`.
A fresh installation allows `wizard` only. History/migration access is preserved
when data exists. Configuration routes unlock after foundation setup, so later
configuration is possible; operational pages require their own dependencies.
This projection grants no mutation permission, never activates a season or adopts
policy, and does not replace the existing service gates. Consumers refresh it on
context/setup changes and apply it to direct route access as well as menus.
`rosterConfigured` covers published registration configuration before accounting
activation; PlayerUI must not require `seasonConfigured` to let members enroll.

## `Dibs.Wizard.GetProfiles()`

Returns an ordered copy of available setup profiles. Callers cannot mutate module
definitions through the returned table.

```lua
{
  {
    id = "progression",
    label = "Progression raid",
    summary = "...",
    benefits = { "..." },
    changes = { "..." },
    preserves = { "..." },
  },
}
```

## `Dibs.Wizard.PreviewProfile(profileId, actor?, options?)`

Returns a deterministic preview derived from current authoritative state.

```lua
{
  profileId = "progression",
  canApply = true,
  actions = {
    {
      id = "initialize",
      disposition = "APPLY",
      title = "Initialize guild configuration",
      explanation = "...",
      outcome = "...",
    },
  },
  preserved = { "Existing ledger transactions", "Historical evidence" },
  deferred = {},
}
```

Unknown profiles return `nil, "UNKNOWN_SETUP_PROFILE"`.

Optional `options = {seasonDraft = <SeasonalRoster.CreateSeason input>,
seasonOperationId = <stable service operation ID>}` adds a `seasonDraft` action.
No option preserves the existing behavior. Invalid requested input returns
`canApply=false` with its reasonCode before any mutation. Existing seasonal rosters
produce ALREADY_READY without edits; disabled module produces DEFERRED/MODULE_DISABLED.
The form always requests DRAFT registration/lifecycle; no publish/activate is implied.

## `Dibs.Wizard.ApplyProfile(profileId, actor?, options?)`

Runs only actions marked applicable by a fresh preview. It delegates every mutation to
existing public service boundaries.

```lua
{
  ok = true,
  profileId = "progression",
  actions = {
    { id = "initialize", outcome = "APPLIED" },
    { id = "lootRules", outcome = "APPLIED" },
    { id = "guildPolicy", outcome = "DEFERRED", reasonCode = "GM_CONFIRMATION_REQUIRED" },
  },
}
```

Contract rules:

1. Unknown profiles fail explicitly.
2. `custom` performs no automatic mutation.
3. Existing ready actions return `ALREADY_READY`.
4. A failed action returns `FAILED` with its source reason.
5. The overall result cannot be `ok = true` when any applicable action failed.
6. Deferred GM-only actions do not masquerade as applied.
7. No ledger transaction is created, rewritten, or deleted by profile application.
8. Repeated application is idempotent.
9. Invalid season options fail before applying any action. The season action requires
   real foundation readiness, then rechecks current seasons/module state and calls
   SeasonalRoster.CreateSeason with the supplied stable operation ID. Source errors
   remain visible; no direct SavedVariables write or module enablement is allowed.
10. Custom ignores automatic preparation. Existing seasons are never rewritten;
    creating a draft does not publish it, open registration or change the active ledger.

## `Dibs.Wizard.GetTurnkeyStatus(actor?)`

Returns the three stages and fresh verification results.

```lua
{
  currentStage = "choose",
  selectedProfileId = "progression",
  stages = {
    { id = "choose", status = "READY" },
    { id = "configure", status = "ACTION_REQUIRED" },
    { id = "verify", status = "BLOCKING" },
  },
  verification = {
    {
      id = "rankRules",
      severity = "BLOCKING",
      title = "Rank Rules need configuration",
      explanation = "...",
      impact = "...",
      nextAction = "...",
      route = "ranks",
      sourceStatus = "ACTION_REQUIRED",
    },
  },
  primaryIssueId = "rankRules",
}
```

Blocking precedence is deterministic. The primary issue is the first blocking result
in setup dependency order, followed by warnings only when no blocker exists.

## UI contract

- Red/error treatment is used only for `BLOCKING`.
- Warning treatment is used for `WARNING`.
- Green/success treatment is used for `READY`.
- Muted/info treatment is used for `OPTIONAL`.
- Every badge is accompanied by a text severity label.
- A verification result with a route exposes one visible correction button.
- Opening a correction route preserves selected profile and current workflow stage.
