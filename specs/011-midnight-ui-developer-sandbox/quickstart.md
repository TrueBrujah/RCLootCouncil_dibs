# Quickstart: Midnight UI and Safe Developer Sandbox

## Prerequisites

- Repository root is the current directory.
- Node.js/npm and Fengari are available through `npx.cmd`.
- PowerShell is available.
- For Retail checks, a development WoW client with the addon installed and optional
  RCLootCouncil, LibSharedMedia, LibWindow, and supported external UI environments as
  available.

## Automated verification

Run the full Lua suite from the repository root:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" |
  Sort-Object FullName |
  ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\", "").Replace("\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx.cmd --yes fengari tests/run.lua
git diff --check
```

Expected result: the existing repository baseline passes, with any known pre-B11 baseline
failure recorded separately from B11 results. B11 tests must identify their own failures
rather than weakening existing production tests.

## Focused B11 automated scenarios

1. Load without RCLootCouncil and without LibStub; verify native Midnight fallback and
   standalone Dibs operation.
2. Verify Developer Mode is disabled by default; `/dibs dev on`, `/dibs dev status`, and
   `/dibs dev off` change only local developer state.
3. Clone production data into the separate sandbox store, enter with PLAYER, OFFICER, and
   GUILD_MASTER simulations, and assert production ledger, policy, coordinator, recovery,
   and SavedVariables snapshots remain byte-equivalent.
4. Attempt provider mixing, invalid schema, future schema, malformed clone, and sandbox
   mutation after exit; verify fail-closed results and unchanged production state.
5. Reload after sandbox activity; verify production provider and real authority are active,
   simulated authority is absent, and sandbox data is still available for explicit re-entry.
6. Exercise all required scenarios and assert no addon messages, fake global events, live
   loot events, or RCLootCouncil history/evidence writes are emitted.
7. Build player and officer projections for empty, degraded, blocked, large, and normal
   states; verify role-scoped visibility, readable primary status, and secondary menus.
8. Search, review, confirm, reject, stale, and ambiguous reconciliation candidates; verify
   the existing protected service path and immutable evidence behavior.
9. Invalidate a window repeatedly and assert one coalesced refresh; enter combat during
   creation/refresh and verify the existing post-combat deferral.
10. Render long labels and tables at minimum, typical, and wide sizes; assert no overlap,
    clipped primary controls, or competing scroll owners through the UI fixture model.

Relevant design details are in [data-model.md](data-model.md) and
[contracts/midnight-ui-sandbox.md](contracts/midnight-ui-sandbox.md).

## Retail validation

1. Open the player and Officer windows with no external UI environment and confirm the
   complete native Midnight presentation.
2. Repeat with each available supported UI environment. Confirm only presentation hints
   change and disable/throw the adapter to verify native fallback.
3. Move and scale windows, reload, and confirm LibWindow restoration and local presentation
   persistence without any guild-policy or sync changes.
4. Enable Developer Mode, enter the sandbox, select simulated role/coordinator states,
   exercise fault scenarios, and confirm the persistent warning identifies sandbox mode.
5. Exit and reload. Confirm production provider, real GM/Officer authority, and production
   ledger are restored; re-enter explicitly to recover the retained sandbox snapshot.
6. As a normal player, verify Officer/Developer/Debug navigation and private diagnostics
   remain hidden. As an Officer/GM, verify grouped dashboard access and action boundaries.
7. Test combat lockdown while opening, moving, refreshing, and closing windows; confirm
   existing B08 deferral and post-combat retry behavior.
8. Exercise Search -> Review -> Confirm/Reject -> Complete with real bounded RC history;
   confirm no RCLootCouncil history writes and no changed B09 evidence semantics.

## Release gates

- All automated tests pass or known baseline failures are documented.
- No production SavedVariables migration is required for appearance or sandbox state.
- Sandbox isolation and provider fail-closed tests pass at 100%.
- No protected UI or production accounting operation is bypassed in combat or sandbox mode.
- B00-B10 regression, one-client Retail, and two-client authority/sync checks remain green.
