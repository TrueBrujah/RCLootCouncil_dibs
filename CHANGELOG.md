# Changelog

## 0.3.14-dev - 2026-09-10

- Keep WoW/RCLootCouncil Options focused on configuration, short launch actions,
  and status. Player and Officer searches, reports, history, reconciliation,
  and statistics stay in separate modeless control-center windows.
- Add an explicit **Open in Adventure Guide** action for selected
  RCLootCouncil history rows. Catalogued raid and encounter IDs are retained;
  older rows use a bounded Adventure Guide lookup only when requested.
- Preserve rich item links and open Dibs windows at the DIALOG strata so the
  Settings panel can remain available beside them.

## 0.3.13-dev - 2026-09-09

- Use the embedded MSA-DropDownMenu library for lightweight Officer choices.
- Normalize compact RCLootCouncil item tokens into rich links and resolve only
  visible rows, with a bounded history index cache for repeated searches.
- Paginate reconciliation previews so long histories do not freeze the UI.

## 0.3.12-dev - 2026-09-09

- Fix RCLootCouncil history reconciliation attributing traded awards to the
  original loot owner instead of the awarded player.
- Preserve the original owner as separate Officer evidence.

## 0.3.11-dev - 2026-09-09

- Implement GM/Officer-controlled RCLootCouncil history reconciliation with a
  bounded, read-only preview and exact configurable response aliases.
- Classify finalized, duplicate, ambiguous, rejected and unsupported rows;
  preserve original response text, response identity, winner, item, status and
  award time as immutable evidence.
- Add guided and manually acknowledged confirmation through a protected
  append-only `rclootcouncil_history` debit, with stable award/evidence
  idempotency across reloads and repeated confirmations.
- Add the Officer **RC History** page and shared options entry. The source
  labels `RCMLAwardSuccess` and `FinalizeAward` remain informational evidence,
  never executable controls. Player history shows only a safe source/reason
  summary.

## 0.3.10-dev - 2026-09-09

- Add guild-roster player choices to Officer target corrections, with a local
  search field and a dropdown that never invents character names.
- Add a bounded, session-cached Adventure Guide raid-loot catalogue for target
  corrections. Search supports item name, ID, raid, boss, Dibs category, and
  equipment metadata; the correction form accepts only catalogue selections.
- Keep the correction UI explicit when the Adventure Guide API or loot data is
  unavailable instead of accepting arbitrary item text.

## 0.3.9-dev - 2026-09-09

- Replace simulated text columns with real aligned AceGUI table cells and
  responsive widths so request lists, timelines, and detail views remain easy
  to scan at different window sizes.
- Keep form sections and resolution details inside bounded scrollable panels.

## 0.3.8-dev - 2026-09-09

- Improve the Player and Officer review pages with bounded scrolling, titled
  sections, compact queue rows, and grouped actions so details remain usable
  on smaller screens.
- Add a protected `Correct item or player` resolution for wrong-target reports.
  The original evidence stays preserved, corrected metadata is recorded in the
  audit timeline, and a linked player balance is transferred with two audited
  ledger adjustments.

## 0.3.7-dev - 2026-09-09

- Added the Officer Audit and Dispute Center: players can submit bounded,
  non-authoritative reports from their own Dibs context, while GM/Officer
  reviewers get a private queue, evidence view, safe resolutions, and an
  append-only audit timeline. Balance corrections use linked protected ledger
  transactions and remain idempotent across reloads or repeated actions.

## 0.3.6-dev - 2026-09-09

- Added the Raid Readiness and Dry-Run Center on `dev`: bounded readiness
  probes, safe and Officer reports, authorized slash commands, and a local
  simulation path that never invokes live loot controls or consumes Dibs.
- Added shared pure award validation and a final readiness safety gate for live
  RCLootCouncil award accounting.
- Readiness reports now open in a selectable window and show the Dibs addon and
  observed RCLootCouncil versions; chat is reserved for short fallback messages.

## 0.3.5 - 2026-09-09

- Reserve `CATALYST` items for the player's personal progression: Catalyst is
  always blocked from Dibs buttons, Pre-Dibs, policy settings, and ledger use.
  Class-based Tier Set tokens are classified as `TOKEN_SET`, while Curios use
  `TOKEN`. The broader RCLootCouncil `Catalyst Items` button set is resolved
  from item metadata so it cannot hide Curios or Tier Set tokens. This source
  and policy change is included in the `0.3.5` build.
- Add an in-game RCLootCouncil button-set mapping guide and two safe semantic
  templates (`Curio + Tier Set` and `Standard loot`). Slot-specific RCLootCouncil
  groups remain compatibility projections and are never treated as new Dibs
  item families.
- Add the Installation assistant to the RCLootCouncil options. It applies the
  recommended semantic preset and refreshes the locked Dibs response in the
  default and already-enabled RCLootCouncil button sets without changing the
  guild's existing response configuration.
- Resolve ordinary armor, weapons and other unclassified equipment through the
  configurable `OTHER` Dibs family. Keep Cosmetic Items blocked even when the
  catch-all family is enabled, recognize readable RCLootCouncil slot labels such
  as `Chest` and `Weapon` as compatibility sets, and resolve an Armor Token
  before the broad Retail Miscellaneous fallback.
- Add the draft specification for GM/Officer-controlled RCLootCouncil history
  reconciliation, configurable response aliases, manual historical Dibs
  confirmation, and auditable evidence records. This is documentation only;
  no addon behavior or SavedVariables format changes are included yet.
- Clarify that `RCMLAwardSuccess` is the RCLootCouncil source event while
  `FinalizeAward` is Dibs's protected accounting action, not an executable
  history control.
- Add the draft specification for local backups, preview-first export/import,
  safe configuration profiles, version-aware migration, and privacy-aware
  recovery. This is documentation only; no addon behavior or SavedVariables
  format changes are included yet.
- Add the draft specification for a Raid Readiness and Dry-Run Center with
  pre-raid capability checks, fail-closed live-award gating, safe local
  simulations, and privacy-aware reports. This is documentation only; no addon
  behavior or SavedVariables format changes are included yet.
- Add the draft specification for a simple Officer Audit and Dispute Center:
  one-button player reports, prefilled evidence, a small Officer resolution
  queue, and append-only corrections. This is documentation only; no addon
  behavior or SavedVariables format changes are included yet.

## 0.3.4 - 2026-09-07

- Add the RCLootCouncil Dibs logo to the addon metadata and AceGUI windows.
- Package a WoW-compatible 128px texture while retaining the original PNG in
  `docs/assets` for CurseForge and project documentation.
- Add a GitHub Actions workflow that packages `dev` and `main` pushes as
  verified ZIP artifacts with a SHA-256 checksum.
- Update the packaging actions to Node.js 24-compatible releases and remove
  the GitHub Actions Node.js 20 deprecation warning.
- Publish versioned tags as GitHub Releases with the addon ZIP and checksum so
  users can download tagged builds from the repository's Releases page.

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
