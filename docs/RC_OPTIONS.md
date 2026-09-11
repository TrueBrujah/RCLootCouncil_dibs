# RCLootCouncil - Dibs options

Open AddOns > RCLootCouncil > Dibs, or use `/dibs options`. The Blizzard/RCLootCouncil Options page is the configuration surface: seasons, rank rules, permissions, installation mode, Pre-Dibs policy, announcements, loot-type mapping, RCLootCouncil projection, and debug levels. It contains launch buttons and status only; it does not render long searches, history tables, player reports or statistics. Those operational views open in separate modeless Player or Officer control-center windows, so WoW Settings can remain open beside them. Without RCLootCouncil, the command opens the same AceConfig settings as a standalone window.

The Officer window mirrors the operational navigation: Overview, Review Requests, RC History, Loot Eligibility, Seasons, Rank Rules, Settings, Pre-Dibs, Announcements, Developer, RCLootCouncil, and Debug. It renders those pages from the shared AceConfig groups, so controls use the same Dibs services, SavedVariables, protected callbacks, dynamic loot types and diagnostics as the Blizzard/RCLootCouncil options panel. Review Requests is the private GM/Officer queue for player reports; evidence is read-only and every resolution requires a bounded reason, with explicit confirmation for ledger-changing actions. Wrong-item/player corrections offer a guild-roster player dropdown and a searchable Adventure Guide raid-loot dropdown (name, ID, raid, boss, Dibs category, and equipment metadata). If the client cannot expose Adventure Guide data, the form says why and does not accept arbitrary item text. The **Loot Eligibility** page configures Curio and Tier Set policy, reviews main/alt declarations, and displays probation and protected-loot progress; pending links never affect enforcement. The legacy Players, History and Statistics views remain available through the separate logs action and programmatic compatibility aliases. Existing protected actions continue to enforce authority: GM/officer for Dibs policy and ledger changes; the verified RCLootCouncil Master Looter may manage the loot session and finalize a qualifying DIB award, but cannot grant or remove Dibs.

History and correction item rows retain their WoW hyperlink. An Officer can use **Open in Adventure Guide** on a selected RCLootCouncil history row; when the catalogue has a matching raid and boss, the Adventure Guide opens directly on that encounter. Older rows without encounter metadata are matched against the cached Adventure Guide catalogue only after the Officer requests navigation.

The loot-type policy is semantic: `TOKEN` is the general/Curio token family and
`TOKEN_SET` is the class-based Tier Set token family. `CATALYST` is personal
player progress and is permanently excluded from Dibs buttons, Pre-Dibs, policy
settings, and ledger consumption. Older saved Catalyst settings are ignored.

The **Data** tab is the launch point for the modeless backup/profile/transfer
window. Use **Backups** for dated recovery points and preview-first restore,
**Profiles** for local presentation or GM/Officer guild policy profiles, and
**Import / Export** for checksummed `DIBS-PKG-1` packages. Configuration imports
show merge/replace impact; full-data imports are append-only and deduplicated.

## RCLootCouncil button-set mapping

RCLootCouncil's **Additional Buttons** menu mixes item families and equipment
slots. Dibs keeps those concepts separate so a slot override cannot accidentally
turn a personal item into a guild Dibs item.

| RCLootCouncil set | Dibs semantic family | Use in Dibs |
| --- | --- | --- |
| Catalyst Items | Item-dependent | Personal Catalyst is blocked; Context-token Curios and class Tier Set tokens are classified as `TOKEN` or `TOKEN_SET`. |
| Armor Token | `TOKEN_SET` | Class-based Tier Set token. |
| Mounts | `MOUNTS` | Optional collection item family. |
| Pets | `PETS` | Optional battle-pet/companion family. |
| Recipes | `RECIPE` | Profession recipes, patterns, plans and formulas. |
| Decor | `DECOR` | Optional housing family; the default Adventure Guide matrix blocks it. |
| Cosmetic Items | `COSMETIC` | Cosmetic-only items are not a Dibs progression family. |
| Rare items | `OTHER` | RCLC rarity grouping, treated as the configurable Dibs catch-all. |
| Items /w special effects | `OTHER` | RCLC qualifier, treated as the configurable Dibs catch-all. |
| Chest, Back, Feet, Finger, Hands, Head, Legs, Neck, Shoulder, Trinket, Waist, Wrist, Weapon | *(none)* | Slot-specific response set; it inherits the semantic Dibs decision. |

The integration page displays this table in game and reports which RCLC sets are
currently configured. The **Curio + Tier Set** template enables only `TOKEN` and
`TOKEN_SET` and sets the other semantic families, including the default fallback,
to disabled. **Standard loot** additionally enables mounts, pets, recipes and
`OTHER`; it leaves Decor disabled. Ordinary equipment is resolved through
`OTHER`, so this preset covers normal armor and weapons as well.

The **Installation assistant** offers these two starting presets and refreshes
the locked Dibs projection after applying one. It prepares the Dibs button in
the default RCLC response set and every additional set already enabled by the
Master Looter, while preserving existing button text, colors, response order
and slot selections. If RCLootCouncil is absent, the same presets configure
standalone Dibs and the projection is applied automatically when RCLC loads.

Overview and the RCLootCouncil policy tab show a capability snapshot (`absent`, `operational`, `degraded`, or `unsupported`), a stable reason code, and only the probes that were verified. In Standalone mode the player sees a clear fallback status and continues to use local Dibs views. The status does not expose candidates, votes, responses, or live session identifiers.

The Player Summary includes the protected-loot group and Curio/Tier Set counts.
Players can choose another guild character from the roster to submit an **alt
declaration** or a **main-change request**; both remain pending until an Officer
reviews them.

The **Raid Readiness & Dry-Run** page is available inside the Officer
RCLootCouncil section. **Run readiness check** evaluates the active season,
rank policy, installation mode, RCLootCouncil capabilities, response projection,
raid context, channel and local services. **Open selectable safe report** opens
bounded diagnostic metadata in its own selectable window and includes the Dibs
addon version plus the observed RCLootCouncil version. The dry-run fields accept an item, winner,
response, finalization status and synthetic session identity; **Run local
dry-run** reports `would_allow`, `would_reject`, `would_ignore`, or
`would_require_review` without invoking live award controls or consuming a Dib.
Players see only a safe readiness status in their Summary view.

The **RC History** Officer page is a deliberate recovery workflow for history
that predates Dibs installation. Configure exact aliases, choose a target
season and optional timestamp bounds, then press **Search history (preview)**.
Only matching DIB rows are shown; the preview also reports how many unrelated
rows were hidden. The **Transfer** button opens the selected row with its
original response/reason, date, difficulty, votes, instance, encounter and
related winners. A transfer note and one **Confirm as DIB** click are required
before a ledger debit is appended. When a legacy row has an id/date but no
final-status field, the optional history-final-status rule marks it as inferred;
Normal and Heroic rows remain separate. Repeated confirmation returns the
original transaction. `RCMLAwardSuccess` and `FinalizeAward` are shown only as
source/accounting evidence labels. No search runs at load time and no
RCLootCouncil history row is modified.

When RCLootCouncil is available, the adapter projects a locked `Dib` response into the indexed Master Looter button/response arrays. It adds the response to the active default set and every enabled additional-button set, preserves the existing responses, and re-applies after profile changes or late module loading. A full `maxButtons` configuration is left untouched so no existing RCLootCouncil response is overwritten; the runtime Dibs button still fails closed when the candidate is not eligible.

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

2026-09-11: full Lua suite passed: 226 tests, 0 failures, 54 files. Coverage includes capability transitions, late-load recovery, authority matrix, local Master Looter enforcement, explicit response normalization, stable award provenance, reload idempotency, history preservation, exact DIB history filtering, precise date/time display with seconds, zero-date handling, simplified history confirmation, inferred history final-status rules, duplicate item difficulty context, separate transfer review window with required annotation, stable Officer option pages, transfer-only table actions, sync privacy, options fallback, combat deferral, standalone operation, RC loot policy cache invalidation, indexed DIB response projection, AceDB profile discovery, malformed-count bounds, normalized voting-row Dibs display, the real lib-st callback signature, slash output with diagnostics disabled, rank allocation for candidates without ledger history, Catalyst exclusion, semantic Curio/Tier Set mapping, ordinary equipment fallback, Miscellaneous Armor Token disambiguation, Cosmetic blocking, Installation assistant controls, Raid Readiness states and invalidation, safe reports, selectable report windows with version metadata, dry-run replay, shared award validation, and no-mutation checks. Retail visual and delivery checks remain pending.

The `/dibs officer` window uses the same vertical navigation pattern as the RCLootCouncil options. It has a **Loot types** page with the same dynamic type list, checkboxes and both presets as the RCLootCouncil options. Changes use the same callbacks; reopening or refreshing either view reads the current values. The Player window uses the same navigation pattern for its Summary, History, and **My requests** pages. A player can submit a bounded report with an optional ledger entry, answer an Officer question, and read the final explanation. Use `/dibs requests` for the Player page and `/dibs review` for the authorized Officer queue. Focused options, history transfer and UI regression validation: 33 tests passed.

The officer window also has a **Debug** tab. It exposes the global and module verbosity levels, the current runtime report, and a button that opens the selectable readiness report. `/dibs debug report` remains the compact chat diagnostic. The readiness report contains runtime metadata and channel identifiers only; it does not include live loot candidates, votes, or responses.
