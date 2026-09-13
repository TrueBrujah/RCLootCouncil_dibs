# B11b Implementation Evidence

## Scope

This pass implements US2, the isolated developer sandbox. It keeps the existing
guild-scoped production database and production authority paths unchanged when
the sandbox is inactive. Sandbox data is stored in the separate
`RCLootCouncil_dibsSandboxDB` SavedVariable.

## Completed task IDs

- T002, T008-T009, T012
- T021-T030

T004, T011, and T020 remain open for later shared-foundation and UI lifecycle
work. US3-US7 remain untouched.

## Implementation evidence

- `src/integrations/DeveloperSandboxStore.lua` owns schema 1 sandbox data,
  bounded deep-copy validation, future-schema rejection, oversized-store
  rejection, clone, refresh, reset, and retained data after reload.
- `src/integrations/DeveloperSandbox.lua` owns the in-memory active provider,
  simulated role/coordinator state, authority origin, explicit entry/exit, and
  fail-closed provider status. Active simulation is not persisted.
- `src/integrations/DeveloperSandboxScenarios.lua` provides the required role
  and bounded fault scenarios without invoking transport, live loot, RC evidence,
  or protected accounting.
- `src/integrations/DeveloperMode.lua` exposes status and sandbox lifecycle
  commands. Disabling Developer Mode exits an active sandbox.
- `src/ui/DeveloperUI.lua` and `src/ui/OfficerUI.lua` expose the warning,
  provider, simulated role, coordinator state, lifecycle controls, and hidden
  Developer/Debug navigation behavior.
- `ProtectedActions`, `Permissions`, `Governance`, and `RaidRelay` reject the
  mixed production/sandbox provider with `MIXED_PROVIDER_REJECTED`.

## Validation

Focused B11b suites:

```text
10 passed, 0 failed (4 files)
```

Focused navigation plus B11b validation:

```text
33 passed, 0 failed (5 files)
```

Full Fengari regression:

```text
329 passed, 1 failed (72 files)
```

The one failure is the known pre-existing RCLootCouncil response projection
baseline:

```text
tests/integration/rclootcouncil_buttons_spec.lua:155
expected 2/2, got 1/1
```

No B11b diagnostic was reported. The working tree also passed the available
static diagnostics for all touched Lua files.

## Result

`B11b COMPLETE - READY FOR B11c`