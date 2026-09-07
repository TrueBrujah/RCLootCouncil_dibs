# RCLootCouncil - Dibs options

Open AddOns > RCLootCouncil > Dibs, or use `/dibs options`. The player and officer windows link back to these options; Overview opens either window. Without RCLootCouncil, the command opens the same AceConfig settings as a standalone window.

The tree includes Seasons, Rank Rules, Settings, Pre-Dibs, Announcements, Player, Officer, Developer, and RCLootCouncil loot-type policy. Controls use existing Dibs services and SavedVariables. Changing an announcement template/channel in one surface is reflected when the other surface is refreshed or reopened. Officer views reuse the existing seasonal filters, pagination, dashboard and statistics. Existing protected actions continue to enforce authority: GM/officer for Dibs policy and ledger changes; the verified RCLootCouncil Master Looter may manage the loot session and finalize a qualifying DIB award, but cannot grant or remove Dibs.

Overview and the RCLootCouncil policy tab show a capability snapshot (`absent`, `operational`, `degraded`, or `unsupported`), a stable reason code, and only the probes that were verified. In Standalone mode the player sees a clear fallback status and continues to use local Dibs views. The status does not expose candidates, votes, responses, or live session identifiers.

Raid Dibs is a community stream, distinct from RAID chat. Its selection remains visible even when the stream cannot be found. Announcements shows discovery status and the detected club/stream identifiers. Test buttons use the announcement service and do not create requests or ledger entries. A successful local API call still requires in-game confirmation that the message was delivered.

## Retail validation remaining

1. Open `/dibs options` with RCLootCouncil loaded; confirm the correct Dibs subcategory opens and all tree entries fit.
2. Open Player and Officer from Overview, then return through their options buttons.
3. Change a template/channel in each surface and reopen the other; verify matching values and preview.
4. Select Raid Dibs; test with a subscribed community containing that stream. Confirm delivery in the intended channel. Repeat without the stream; verify the selection remains visible and the diagnostic explains the failure.
5. Verify a non-authorized character cannot change the active season, rank policy or mode. Test a raid reminder outside a raid, from an authorized guild character, and from the verified Master Looter; confirm reminders do not change the ledger.
6. Submit/cancel a personal Pre-Dib and compare the player window. Review seasonal officer searches and pages.
7. Open options during combat; verify opening is deferred until combat ends. Repeat the command with RCLootCouncil absent.

## Automated validation

2026-09-06: full Lua suite passed: 149 tests, 0 failures, 43 files. Coverage includes capability transitions, late-load recovery, authority matrix, local Master Looter enforcement, explicit response normalization, stable award provenance, reload idempotency, history preservation, sync privacy, options fallback, combat deferral, standalone operation, and RC loot policy cache invalidation. Retail visual and delivery checks remain pending.

The `/dibs officer` window also has a **Loot types** tab with the same dynamic type list, checkboxes and both presets as the RCLootCouncil options. Changes use the same callbacks; reopening or refreshing either view reads the current values. Focused options and combat/UI regression validation: 20 tests passed.

The officer window also has a **Debug** tab. It exposes the global and module verbosity levels, the current runtime report, and a chat copy action. `/dibs debug report` prints the same report. The report contains runtime metadata and channel identifiers only; it does not include live loot candidates, votes, or responses.
