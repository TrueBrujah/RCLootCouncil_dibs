# B11d Implementation Evidence

## Scope

This pass implements only US4 / B11d, the Officer/GM dashboard slice. US5, US6,
and US7 remain untouched. The B11d start checkpoint was:

`B11D_START_COMMIT=845d478c975070620387c7b754a59e1a04cd07bd`

The result commit is the single commit containing this evidence file.

## Implementation evidence

- `src/ui/OfficerUI.lua` keeps the public navigation projection compatible with
  existing aliases while transforming the entries into grouped AceGUI TreeGroup
  sections: Overview, Dibs, Guild Rules, Integrations, System, and Developer.
- Normal Players receive no Officer navigation or guild-wide Officer data.
  Production Officer and GM roles remain determined by `Dibs.Permissions`;
  sandbox Officer and GM presentation roles are mapped from the isolated
  `DeveloperSandbox` provider without changing production permissions.
- The overview page now renders a bounded Officer dashboard projection with the
  active season, pending requests, active Pre-Dibs, active players, recent
  activity capped at five rows, and normalized Ledger, Sync, Coordinator, and
  RCLootCouncil status cards.
- Human-readable statuses map `SYNC_BEHIND`, `SYNC_UNAVAILABLE`,
  `RECOVERY_PENDING`, `COORDINATOR_UNAVAILABLE`, and degraded/absent RC states
  to readable labels. Technical state and reason codes are available only after
  the dashboard technical-details disclosure is opened.
- Dashboard data comes from `Dibs.Sync.GetStatus`,
  `Dibs.Governance.GetAuthorityState`, and
  `Dibs.RCLootCouncil.GetLocalStatus`; no new authority, ledger, governance,
  synchronization, or RCLootCouncil semantics were added.
- All existing administrative mutations continue through
  `Dibs.ProtectedActions.Execute`. Active sandbox views remain presentation-only
  and production protected actions still fail closed with
  `MIXED_PROVIDER_REJECTED`.
- The sandbox accepts the explicit `gm` role alias and normalizes it to the
  existing `guild_master` provider role. Production role evaluation remains
  unchanged.

## Tests

Focused B11d tests:

```text
6 passed, 0 failed (2 files)
```

Adjacent B11a-c and Officer compatibility tests:

```text
44 passed, 0 failed (5 files)
```

Full Fengari regression:

```text
342 passed, 1 failed (76 files)
```

The one failure is the unchanged pre-B11d baseline in
`tests/integration/rclootcouncil_buttons_spec.lua:155`:

```text
expected 2/2, got 1/1
```

Static diagnostics reported no errors for the touched Lua files, and
`git diff --check` passed. B00-B10 semantics and the B11a-c Player surface
remain unchanged by this slice.

## Result

`B11d COMPLETE - READY FOR REVIEW`.