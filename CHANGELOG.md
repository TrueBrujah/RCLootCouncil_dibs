# Changelog

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
