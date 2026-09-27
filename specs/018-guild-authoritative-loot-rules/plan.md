# Implementation Plan: Guild-Authoritative Loot Rules

**Branch**: `dev` (workspace branch retained) | **Date**: 2026-09-25 | **Spec**: [spec.md](spec.md)

**Input**: [Feature specification](spec.md)

## Summary

Introduce an explicit, revisioned guild Loot Rules authority for Adventure Guide eligibility and RCLootCouncil DIBS buttons. Reuse `SEASON_CATALOG` and its existing authorization, hash chain, bounded transfer, recovery, and audit; add the independently versioned `guildConfiguration.guildLootRules` snapshot. Keep the two legacy maps as per-client draft/fallback inputs, require GM-reviewed first adoption, keep edits ineffective until publication, and make received authority the sole effective source after adoption. Ship in addon version 0.8.0 so the existing same-major/minor gate rejects 0.7.x peers.

## Technical Context

**Language/Version**: Lua 5.1-compatible WoW Retail addon code.

**Primary Dependencies**: Existing Dibs modules, embedded AceComm/AceConfig services, RCLootCouncil adapter when installed; no new package.

**Storage**: Existing guild-scoped `db.seasonCatalog` record chain; local `db.settings.dibAllowedTypes` and `dibRCEnabledTypes` retained as draft/fallback. No root SavedVariables schema change and no new authoritative mutable cache.

**Testing**: Fengari custom test harness (`npx --yes fengari tests/run.lua`) with focused `DIBS_TEST_FILES`; source-driven docs validation via `scripts/Generate-DibsDocs.ps1 -Validate`.

**Target Platform**: WoW Retail; standalone DIBS and optional RCLootCouncil integration.

**Project Type**: Lua addon with domain modules, AceConfig UI, localized guides, and Lua tests.

**Performance Goals**: Validate one bounded catalog snapshot before mutation; defer the existing RCLootCouncil projection refresh through its current safe refresh API.

**Constraints**: Dynamic supported keys come from `Dibs.RCOptions.GetLootTypeOptions().types`; catalog apply is atomic after validation; no direct writes to unrelated RCLootCouncil SavedVariables; combat-sensitive UI refresh remains deferred; preserve all pre-existing dirty worktree changes.

**Scale/Scope**: One complete rule snapshot per current guild catalog revision, both decisions for every supported key, GM adoption, authorized later publication, Officer read-only consumption, readiness and migration behavior.

## Constitution Check

*Gate reviewed before research and again after design; all applicable MUST principles pass.*

| Principle | Gate | Design evidence |
|---|---|---|
| I. WoW API compliance | PASS | Uses existing addon-message transport and deferred RC projection refresh; no protected gameplay action. |
| VII. RCLootCouncil compatibility | PASS | Adapter remains optional; DIBS stays usable without RC; RC owns its own loot sessions. |
| XI. Authority and trust | PASS | Adoption and every Loot Rules publication are explicit GM-only actions; receivers verify sender and guild. |
| XIII. Data ownership | PASS | DIBS catalog owns the authority; local legacy maps survive; no RC-owned unrelated state is rewritten. |
| XIV. Public repository quality | PASS | Payload and 0.8 compatibility impact documented in plan, contract, changelog, and developer guide. |
| XVII. Data isolation | PASS | Authority remains inside the catalog for `Dibs.GetGuildKey()`; no shared/global authority store. |
| XVIII. Diagnostics and localization | PASS | Status and errors use localized DIBS messaging with authority/sync reason; no behavior-changing debug path. |
| XIX. Change notes/versioning | PASS | Set TOC/runtime version to 0.8.0 and update active version-bearing docs/scripts plus dated changelog entry. |
| XX. Item mapping and installation safety | PASS | Dynamic keys preserve existing semantic mapping; Catalyst/personal categories remain permanently ineligible. |
| XXI. Human-centered interface | PASS | Explicit review/adopt/publish controls, clear draft/effective distinction, read-only Officer view, narrow/wide UI checks. |
| XXII. Guide maintenance | PASS | Update relevant English/French Player and GM/Officer guides and review screenshot inventory; real-client screenshots remain a retail validation gate if unavailable here. |

**Post-design recheck**: PASS. Research and data model use existing revision/recovery authority, add no competing policy store, preserve local maps, and expose lag/incompatibility rather than fallback after adoption. No constitution amendment or complexity exception is needed.

## Project Structure

### Documentation

```text
specs/018-guild-authoritative-loot-rules/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/season-catalog-guild-loot-rules.md
└── tasks.md
```

### Source and Tests

```text
src/
├── RCLootCouncil_dibs.toc                 # load new service and set 0.8.0
├── Core.lua                               # runtime version
├── modules/
│   ├── Seasons.lua                        # snapshot validation, catalog projection/publication
│   ├── LootRules.lua                      # draft, authority, effective values, adoption/status
│   ├── Readiness.lua                      # Loot Rules readiness projection
│   └── SyncV2.lua                         # transport/version/readiness integration as needed
├── integrations/
│   ├── RCLootCouncil.lua                  # effective getters and projection refresh
│   └── RCLootCouncilOptions.lua           # dynamic keys and draft-only callbacks
├── ui/OfficerUI.lua                       # GM workflow and read-only Officer consumption
└── locales/{enUS,frFR}.lua                # all new labels, help, status and remediation

tests/
├── unit/                                  # normalization, snapshots, effective-value rules
├── integration/                           # adoption, catalog transfer/recovery, readiness, UI/RC
└── contract/                              # load-order, version and docs contracts where appropriate

docs/
├── audits/Guild_Wide_Loot_Rules_Implementation.md
├── developer/sync-protocol.md
├── player/ and officer/                    # English/French guides and screenshot inventory
└── generated/                              # regenerated from source annotations
```

**Structure Decision**: Keep catalog revision ownership in `Seasons`; place local-draft/effective/adoption policy in one small `LootRules` domain service; make both RCLootCouncil and readiness consume that service. Add no new sync entity or SavedVariables root.

## Implementation Decisions

- The schema-v1 `guildLootRules` field is optional only before adoption. Every later catalog revision carries the current authority forward; an attempted omission after adoption is rejected.
- Remove `dibAllowedTypes` and `dibRCEnabledTypes` from automatic catalog export/application. Existing local values stay intact on the receiver and remain usable only before adoption.
- Build a complete draft from current dynamic keys and existing defaults. Validate every required key and both booleans before adopting or publishing.
- Adoption and all subsequent publication require the verified current GM. Officers consume the authority read-only, even if they can publish other catalog settings.
- Preflight authority, catalog parent/revision, snapshot, and Sync transport before invoking catalog publication. If preflight fails, leave the current authority/effective projection untouched. Once committed, digest/recovery state reports convergence lag; never mislabel lagging peers as ready.
- Apply the new authority only through validated `ApplyCatalog`; invoke `RCLootCouncil.RefreshConfigProjection()` after successful application. Never invoke RC-owned setters for unrelated saved state.
- Keep OperationalPolicy, Rank Rules semantics, ledger, protocol envelope/entity list, and root SavedVariables schema unchanged.

## Required Test Areas

The implementation must include at least these 20 independently asserted test areas:

1. Opening the page does not adopt or publish.
2. GM adoption creates exactly one revision.
3. Non-GM adoption is denied without mutation.
4. Dynamic option-source keys all appear in the reviewed snapshot.
5. Missing dynamic source reports unavailable and does not adopt.
6. Draft edits persist locally without changing effective values.
7. Explicit publication changes effective values only on success.
8. Unauthorized publication preserves the previous revision.
9. Unavailable transport preflight preserves the previous revision and draft.
10. Successful publication records writer, action, revision, and changed keys.
11. Malformed rule/schema values are rejected before mutation.
12. Unknown or incomplete dynamic-key snapshots are rejected.
13. Wrong guild, sender, or hash is rejected.
14. Duplicate valid revision is idempotent; stale/conflicting revisions are rejected.
15. Missing-parent recovery does not prematurely change effective rules.
16. Active authority cannot be omitted/downgraded by a later catalog record.
17. Receipt preserves both clients' local legacy maps byte-for-byte.
18. Before adoption, legacy fallback is visible as local-only; after adoption, authority beats conflicting local drafts.
19. All six readiness outcomes are distinguishable, including version/schema incompatibility.
20. Successful application refreshes the DIBS projection and leaves unrelated RC SavedVariables untouched.

Add guild isolation, no-RCLootCouncil fallback, raid-time update, localization, narrow/wide UI, 0.6.x compatibility, existing wizard regression, and docs validation coverage as separate checks.

## Complexity Tracking

No constitution violations. Reusing the catalog avoids a second authority/revision/recovery subsystem; the single new domain service centralizes draft/effective precedence and keeps UI and integration logic from duplicating it.
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
