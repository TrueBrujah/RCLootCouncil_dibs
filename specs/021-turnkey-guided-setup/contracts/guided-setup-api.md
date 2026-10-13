# Guided Setup Projection and Orchestration Contract

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

## `Dibs.Wizard.PreviewProfile(profileId, actor?)`

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

## `Dibs.Wizard.ApplyProfile(profileId, actor?)`

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
