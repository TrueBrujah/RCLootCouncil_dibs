# Contract: First Installation Assistant

## Readiness projection

`Dibs.SetupAssistant.Evaluate(options)` returns a transient report:

```lua
{
  status = "READY_FOR_RAID|NEEDS_ATTENTION|UNAVAILABLE|DENIED",
  actorRole = "gm|officer|player",
  checks = {
    { id = "season", state = "ready|blocked|degraded|unavailable|skipped", required = true, ... },
  },
  blockingCount = 0,
  checkedAt = 0,
  dryRun = nil,
}
```

Administrative evaluation requires a verified GM/Officer unless the caller requests the existing safe player projection.

## Protected setup action

`Dibs.SetupAssistant.ExecuteAction(actionId, payload, actor)` delegates to `Dibs.ProtectedActions.Execute` and returns its result. It MUST reject unknown action IDs before delegation.

Supported initial action IDs:

- `season.create`
- `season.set`
- `rank.set`
- `installation.mode.set`
- `settings.modify` when an existing settings payload is supported

The assistant does not introduce a new mutation boundary.

## Local dry-run

`Dibs.SetupAssistant.RunDryRun(input)` delegates to `Dibs.DryRun.Run` and returns a bounded result. It MUST not call live award callbacks, send addon messages, write ledger transactions, or mutate RCLootCouncil history.
