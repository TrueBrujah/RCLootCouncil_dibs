# Changelog

## 0.3.4-dev - 2026-09-07

- Add the RCLootCouncil Dibs logo to the addon metadata and AceGUI windows.
- Package a WoW-compatible 128px texture while retaining the original PNG in
  `docs/assets` for CurseForge and project documentation.

## 0.3.3-dev - 2026-09-07

- Make the DIB projection idempotent with AceDB wildcard defaults. This stops repeated AceConfig refreshes that reset the RCLootCouncil Settings scroll position.

## 0.3.2-dev - 2026-09-07

- Stop reordering the legacy Interface Options category list when Retail's `Settings` API is active. Native RCLootCouncil Master Looter subcategories retain their ownership and tab navigation.
- Keep the Player and Officer AceGUI windows hidden during initialization so their dialog frame cannot intercept clicks in RCLootCouncil Settings.

## 0.3.1-dev - 2026-09-07

- Keep `/dibs`, `/dib`, and `/dids` in Blizzard's cached slash-command hash
  even when the chat utility is not ready when the addon first loads.
- Remove the AceGUI shell's historical widget tracking array; released page
  widgets are now owned only by their AceGUI container during refreshes.
- Reuse an injected loot-frame Dibs button when RCLootCouncil rebuilds an
  entry's button list, preventing repeated frame creation during updates.

## 0.3.0-dev - 2026-09-07

- Show a candidate's rank allocation in the voting Dibs column before that
  candidate has a ledger transaction, while preserving real ledger balances.
- Added regression coverage for a guild member with no ledger history.

## 0.2.9-dev - 2026-09-07

- Refresh Blizzard's Retail slash-command hash after registering `/dibs`,
  `/dib`, and `/dids`, including load-on-demand paths where the cache already
  exists.
- Added a regression check that confirms the chat registry import runs.

## 0.2.8-dev - 2026-09-07

- Fixed the voting-frame Dibs and Convert cell callbacks to use the complete
  `lib-st` row/cell argument contract; Dibs values now render in the table.
- Changed AceGUI shell widget tracking to weak references so tab refreshes do
  not retain every released page widget and grow memory over time.
- Made slash registration tolerate early/load-on-demand initialization and kept
  user-facing `/dibs` status/help output visible when diagnostic level is zero.
- Added regression coverage for the real scrolling-table callback signature and
  slash output with diagnostics disabled.

## 0.2.7-dev - 2026-09-07

- Fixed the voting-frame Dibs column to resolve plain names, realm-qualified names, hyperlinks, and GUID-backed candidate rows before reading the ledger balance.
- Made the forced DIB options lock idempotent and shared, preventing a new Lua closure from being allocated on every watcher pass.
- Limited AceConfig registry refreshes to actual projection changes so RCLootCouncil Master Looter tabs remain usable and the options table does not rebuild continuously.
- Bounded malformed RCLootCouncil button counts before iterating saved response arrays.
- Bounded the late-load watcher to a finite retry window; lifecycle hooks continue to handle later profile changes.
- Added a read-only Dibs-column diagnostic and regression coverage for normalized candidate identity rendering.

## 0.2.6-dev - 2026-09-07

- Expand RCLootCouncil profile discovery for AceDB, direct-profile and packaged
  addon variants, including the uppercase `GetDB` compatibility method.
- Reapply the DIB projection after RCLootCouncil initialization and expose a
  safe projection status in `/dibs debug report`.
- Refresh the AceConfig registry after the profile mutation so an options panel
  that was already built renders the new indexed button.
- Add `/dibs debug rc` to request an immediate projection refresh without
  changing Dibs balances, history or RCLootCouncil loot data.
- Add regression coverage for the direct `db.profile` surface.

## 0.2.5-dev - 2026-09-07

- Fix the RCLootCouncil Master Looter projection so the indexed DIB button is
  inserted in the live profile and all existing responses remain available.
- Preserve inactive default response slots while increasing `numButtons` only
  for the active configuration, and initialize enabled additional-button sets.
- Send the table-shaped `ConfigTableChanged` payload expected by RCLootCouncil
  and reapply the projection after profile, options, and late-load lifecycle changes.
- Add an integration regression test covering the screenshot's two-button setup.

## 0.2.4-dev - 2026-09-06

- Replace the AceGUI Officer and Player tab bars with Blizzard/RCLootCouncil-style
  vertical navigation trees and right-side content panels.
- Preserve the existing page callbacks, permission checks, refresh behavior, and
  Standalone/RCLootCouncil operation while adding stable Officer and Player titles.
- Fix the TreeGroup content layout so selected pages render their controls instead
  of appearing empty in Retail.
- Make the Officer tree mirror the RCLootCouncil menu: Overview, Seasons, Rank
  Rules, Settings, Pre-Dibs, Announcements, Developer, RCLootCouncil and Debug.
- Render Officer controls from the shared AceConfig groups so settings, rank
  rules, announcements, integration policy and diagnostics use the same options
  and protected callbacks in both surfaces.
- Improve form sizing with shared headings, wider controls, full-width loot
  type labels and scrollable option pages.

## 0.2.3-dev - 2026-09-06

- Add the WoW Lua Language Server project configuration so vendored libraries
  and test fixtures do not inflate addon diagnostics.
- Declare the complete shared Dibs module namespace in `Core.lua`, leaving the
  analyzer with no addon-source diagnostics while preserving module load order.
- Fix the remaining source-level type, scope, and API-contract diagnostics.

## 0.2.2-dev - 2026-09-06

- Declare the `ProtectedActions` and `PreDibs` namespaces before Core's early
  guards and commands access them.
- Replace deprecated global item APIs with the current `C_Item` APIs, while
  preserving asynchronous item loading and test coverage.
- Remove the deprecated `InterfaceOptions_AddCategory` fallback for the Retail
  Settings registration path.
- Keep the legacy Encounter Journal loot-scroll probe dynamic so it remains an
  optional compatibility path without claiming an unsupported frame field.

## 0.2.1-dev - 2026-09-06

- Initialize the shared `Dibs.Permissions` namespace in `Core.lua` so static
  analyzers recognize the field before the permissions module is loaded.
- Preserve the existing permissions table during reloads; runtime authority and
  standalone/RCLootCouncil permission rules are unchanged.

## 0.2.0-dev - 2026-09-06

- Harden the optional RCLootCouncil integration with capability detection and explicit
  degraded/unsupported states.
- Require a verified local Master Looter, an explicit finalized `DIB` response, and a
  stable award identity before automatic Dib accounting.
- Reject ambiguous or non-DIB awards and keep duplicate delivery idempotent across reloads
  when RCLootCouncil provides a stable session or history identity.
- Normalize explicit DIB responses from text, response tables, and numeric RC response IDs;
  reject empty or conflicting response values and test-mode awards with reason codes.
- Recheck late-loaded RC modules through idempotent hook markers, keep `PLAYER_LOGIN`
  initialization independent of the optional addon, and reject forged callback provenance.
- Expose capability diagnostics in player/officer options and debug reports without live
  candidate, vote, response, or session payloads.
- Preserve unrelated RCLootCouncil history and keep Standalone Dibs administration
  independent of integration availability.
- Add compatibility, authority, award-provenance, privacy, and Retail validation coverage.
