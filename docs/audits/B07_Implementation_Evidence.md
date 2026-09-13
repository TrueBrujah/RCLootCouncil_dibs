# B07 Implementation Evidence

## Scope and commits

- Branch: `dev`
- `B07_START_COMMIT=e26a09e8acc48d4cbc4a3c712106483e55c2c9b8`
- `B07_CHECKPOINT_COMMIT=e26a09e8acc48d4cbc4a3c712106483e55c2c9b8`
- `B07_RESULT_COMMIT=b103836715869e3a6493d508a8b903dcd17cfe3f`

The pre-B07 HEAD was used as the verified checkpoint. The working tree already
contained unrelated user changes to `docs/RC_OPTIONS.md` and
`RCLootCouncil_dibs.code-workspace`; B07 does not stage or modify either file.

## Files in the B07 result commit

- `src/modules/Capabilities.lua`
- `src/Core.lua`
- `src/RCLootCouncil_dibs.toc`
- `src/integrations/EncounterJournal.lua`
- `src/integrations/RCLootCouncilOptions.lua`
- `tests/helpers/load_addon.lua`
- `tests/integration/b07_capability_isolation_spec.lua`

## Core and optional boundary

Required startup remains outside the capability registry: SavedVariables
validation/recovery, database setup, season/rank initialization, governance,
ledger, and SyncV2 startup preserve their existing behavior and errors. B07
does not catch or downgrade these core paths.

The runtime-only registry owns these optional capabilities:

- `player_ui` and `officer_ui` — Dibs presentation windows;
- `rclootcouncil` — optional RCLootCouncil integration;
- `encounter_journal` — Blizzard Encounter Journal enhancement;
- `options_panel` — optional Retail Settings panel;
- `rclootcouncil_options` — optional RCLootCouncil options projection.

Each entry exposes its ID, optional classification, status, concise failure
reason, last attempt/trigger, dependency name, and bounded retry event list.
Statuses are `UNINITIALIZED`, `INITIALIZING`, `AVAILABLE`, `DEGRADED`,
`RETRY_PENDING`, and `UNAVAILABLE`. This state is runtime-only and does not
alter SavedVariables.

## Initialization, diagnostics, and retry behavior

Each optional initializer runs under its own protected boundary. A thrown
initializer becomes `DEGRADED`; an unavailable capability with a meaningful
future lifecycle trigger becomes `RETRY_PENDING`. Failure of one optional
initializer does not prevent the remaining optional initializers or Dibs core
from starting.

`/dibs debug report` now includes concise capability diagnostics. This exposes
the failed surface without persisting unbounded stack traces.

Retries are scoped and idempotent:

- RCLootCouncil retries only on its addon-loaded lifecycle and first world
  entry; duplicate success does not reinitialize it.
- Encounter Journal retries only when `Blizzard_EncounterJournal` loads.
- RCLootCouncil options retry on RCLootCouncil load or combat-end lifecycle
  when their own existing registration condition is relevant.

The existing direct lifecycle hooks for Encounter Journal and RC options defer
to the registry after it exists, so their failure boundary is retained on late
events. There is no general event/frame retry loop.

## RCLootCouncil and Encounter Journal behavior

Absent RCLootCouncil leaves core operational and reports a retry-pending
optional capability. If it appears later, only the RCLootCouncil capability is
retried. A thrown RCLootCouncil initializer is degraded independently from
Encounter Journal and UI capabilities.

A thrown Encounter Journal initializer similarly degrades only that capability;
the ledger, slash command, SyncV2, and other startup components remain usable.
No new RCLootCouncil callback, version mapping, award evidence behavior, or RC
history write was introduced.

## B06 and persistence protection

B07 does not modify ledger records, policy schema, SyncV2 schema, transaction
IDs, epochs, baseline, coordinator state, `AWARD_COMMIT`, or `AWARD_PROPOSAL`.
The B06 distributed-ledger test remains green. Required future-SavedVariables
recovery remains read-only and is not represented as an optional capability.

No B08 combat/UI ownership behavior, B09 RC adapter/version compatibility, or
B10 work was implemented.

## Validation

Focused B07 failure-injection tests:

```text
4 passed, 0 failed (tests/integration/b07_capability_isolation_spec.lua)
```

Coverage includes normal core survival after Player UI failure, independent
RCLootCouncil and Encounter Journal exceptions, RCLootCouncil absence, late
load recovery, duplicate retry idempotency, diagnostics, and required
persistence recovery separation.

Targeted startup/core/B06 regressions:

```text
38 passed, 0 failed (8 files)
```

The complete suite was run once against the final B07 state:

```text
304 passed, 1 failed (64 files)
FAIL RCLootCouncil DIB response projection /
  renders the voting Dibs value from a normalized RCLootCouncil row identity
tests/integration/rclootcouncil_buttons_spec.lua:155: expected 2/2, got 1/1
```

The sole failure exactly matches the B06 documented baseline and is unrelated
to B07. No new regression was introduced.

## Known limitations

B07 isolates runtime initializer failures after modules have loaded. It cannot
isolate a Lua syntax/load error in a TOC file itself; WoW aborts addon loading
before Dibs can establish a runtime boundary. Optional capability state is
intentionally not persisted across reloads.
