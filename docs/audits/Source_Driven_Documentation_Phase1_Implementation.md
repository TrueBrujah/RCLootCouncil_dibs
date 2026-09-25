# Source-Driven Documentation Phase 1 Implementation

## 1. Files Changed

Phase 1 additions and generated outputs:

- `scripts/docs/DibsDocumentation.psm1` - parser, normalized model, validation, and renderers.
- `scripts/Generate-DibsDocs.ps1` - `-Validate`, `-Generate`, and `-Check` CLI.
- `tests/powershell/Generate-DibsDocs.Tests.ps1` - Pester tests compatible with the installed Pester 3.4.
- `src/modules/Ledger.lua`, `RankRules.lua`, `PreDibs.lua`, `Installation.lua`, `Governance.lua`, `SyncV2.lua`, and `ProtectedActions.lua` - ten compact `@doc` annotation blocks only.
- `src/locales/enUS.lua` and `src/locales/frFR.lua` - ten localized concept labels and one Developer-only technical reference. Existing help text and the localization mechanism remain in place.
- `docs/generated/player-guide.md`
- `docs/generated/officer-guide.md`
- `docs/generated/gm-guide.md`
- `docs/generated/developer-reference.md`
- `docs/generated/ui-reference.md`
- `docs/generated/terminology.md`
- `docs/generated/documentation.csv`
- `docs/generated/documentation.json`

The generated files are committed-source candidates per the architecture decision; this implementation generated them in the workspace. No CI workflow or existing role guide was changed.

## 2. Parser Architecture

The PowerShell module scans first-party Lua under `src/`, excluding locales and generated source. It recognizes contiguous `---@doc.*` comment blocks attached to a Lua `function` or `local function` declaration. Source file, declaration line, and symbol are derived from that declaration; none are copied into comments.

The parser is deliberately narrow: it accepts only known metadata tags, documented locale string assignments, and the supported declaration form. It reports an orphan or unsupported binding with a source location rather than guessing. `@doc.help` and `@doc.reason_required` are accepted as aliases for the architecture's canonical `@doc.help-key` and `@doc.reason-required` spellings.

## 3. Annotation Schema Implemented

Implemented approved fields: `id`, `category`, `since`, repeatable `changed`, optional `deprecated` and `removed`, `audience`, `permission`, `scope`, `audit`, `reason-required`, `help-key`, `label-key`, and `reference-key`. Module, symbol, source file, and source line are derived. Unknown fields fail validation.

IDs must be lowercase dot-delimited tokens. Versions follow the addon's `major.minor.patch` form with an optional prerelease suffix. Permissions are checked against action IDs in `ProtectedActions.lua`; audiences, categories, scopes, booleans, required fields, and reason/audit consistency are validated.

## 4. Normalized Model

One `Get-DibsDocumentationModel` pass combines annotations, current addon version, protected action IDs, and enUS/frFR string values. Each concept contains:

- ID, module, category, lifecycle metadata, audience and permission arrays;
- scope, help/label/reference keys, audit and reason booleans;
- localized label, short-help and optional reference maps;
- source file, declaration line, and associated symbol.

Markdown, CSV, and JSON renderers all consume this same model; they do not parse source independently.

## 5. Validator Rules

The validator reports `ERROR`, `WARNING`, and `INFO` findings. Errors produce a nonzero CLI exit code. It checks duplicate and malformed IDs, unknown tags/help keys, missing enUS/frFR values, invalid audience/category/permission/scope/version/boolean values, missing required metadata, orphan annotations, source traceability, reason-without-audit, Developer terminology leaking to normal roles, and localized label/short-help equality.

It also scans existing `UI_HELP_*` keys for source references. Three unmigrated legacy keys currently produce non-blocking warnings: `UI_HELP_ENCOUNTER`, `UI_HELP_REASON`, and `UI_HELP_SETUP_ASSISTANT`. These warnings are expected during the limited pilot and do not make the whole legacy catalog fatal.

## 6. CLI Usage

From the repository root:

```powershell
pwsh -NoProfile -File scripts/Generate-DibsDocs.ps1 -Validate
pwsh -NoProfile -File scripts/Generate-DibsDocs.ps1 -Generate
pwsh -NoProfile -File scripts/Generate-DibsDocs.ps1 -Check
```

`-Validate` is read-only. `-Generate` validates before writing. `-Check` validates and compares expected output with committed files without modifying them.

## 7. Pilot Concepts Migrated

Exactly ten concepts were annotated:

| ID | Concept | Source owner | Audience |
| --- | --- | --- | --- |
| `ledger.balance` | Dib Balance | `Ledger.GetBalance` | Player, Officer, GM |
| `rank.allocation` | Rank Allocation | Protected `executeRankSet` action | Officer, GM |
| `predibs.encounter.mode` | Encounter mode | `Dibs.PreDibs.ValidatePublicRequest` | Player, Officer, GM |
| `guild.setup` | Guild Setup | `Installation.Initialize` | GM, Developer |
| `sync.coordinator` | Coordinator | `Governance.GetAuthorityState` | Officer, GM, Developer |
| `sync.status` | Synchronization | `Sync.GetStatus` | Player, Officer, GM |
| `ledger.adjust` | Dibs Administration / manual adjustment | Protected `executeLedgerAdjust` action | Officer, GM |
| `setup.reconciliation` | Historical reconciliation | `Installation.GetReconciliationView` | Officer, GM, Developer |
| `predibs.request` | Pre-Dib | `Dibs.PreDibs.CreatePublic` | Player, Officer, GM |
| `sync.protocol.state` | SyncV2 protocol state | `Sync.SetProtocolState` | Developer only |

No other help key was migrated to a semantic ID and no UI call site was converted to a new `Dibs.Help` API.

## 8. Localization Integration

`Dibs.L` in the existing enUS/frFR files remains the only translated-content system. Ten new `DOC_*_LABEL` pairs provide localized concept names, and one paired `DOC_SYNC_PROTOCOL_STATE_REFERENCE` key provides the Developer reference. Existing `UI_HELP_*` values supply each pilot's short help; no long user-facing prose was added to source comments.

The validator resolves each referenced key independently in both locale files. The existing 81 help keys were not rewritten and no localization architecture or locale load order changed.

## 9. Generated Outputs

The generator produced six role/reference Markdown files, one CSV, and one structured JSON file under `docs/generated/`. Markdown begins with `THIS FILE IS GENERATED.` and `DO NOT EDIT MANUALLY.` Each concept includes source file, declaration line, and symbol. CSV uses stable ID order and includes the approved identity, lifecycle, audience, permission, scope, help, audit, translation, and source columns. JSON retains arrays, booleans, lifecycle fields, localized content, and source objects.

## 10. Role Filtering

- Player output contains Player-visible concepts and excludes the Developer-only protocol state and its terms.
- Officer output includes rank allocation, manual adjustment, reconciliation, synchronization, and relevant player concepts.
- GM output includes Guild Setup, reconciliation, coordinator and administrative concepts.
- Developer output includes the protocol state plus internal states `LEGACY_LOCAL`, `CUTOVER_PREPARED`, `V2_ENFORCED`, `ledgerEpoch`, `legacyBaselineHash`, and `SyncV2`.
- The general UI reference includes all pilot concepts; the terminology output excludes concepts that are Developer-only.

## 11. Tests

`tests/powershell/Generate-DibsDocs.Tests.ps1` contains 21 Pester tests for valid extraction, duplicates, malformed IDs, invalid versions, missing/unknown locale keys, role filtering, Developer-term leakage, Markdown/CSV/JSON rendering, source traceability, identical label/help warnings, optional metadata/tag aliases, invalid permission/scope, orphan annotations, generated warning banners, and repeated write determinism.

Validation also ran the existing `tests/unit/ui_help_content_spec.lua`: 10 passed, 0 failed.

## 12. Deterministic-Generation Result

**YES.** Generation ran twice with no source changes. SHA-256 hashes for all eight generated files were identical after the second run, and `-Check` reported all generated files current.

## 13. LuaLS Status

The LuaLS issue was not changed because it is not required by the documentation validator and must remain a separate developer-tooling fix. `Dibs.L` is still absent from the `---@class Dibs` declaration in `src/Types.lua`; a fresh analysis can legitimately flag that one field access. Earlier diagnostics also pointed at stale locations for direct help-key accesses that are no longer present in current `PlayerUI.lua`. The documentation parser reads current saved source and does not consume editor diagnostic ranges.

## 14. Remaining Phase 2 Work

- Add the runtime `Dibs.Help.Get/Attach` facade and generated semantic-ID-to-key index; this phase intentionally leaves UI rendering and tooltip call sites unchanged.
- Migrate more concepts in small batches, then the seven audited help gaps and the remaining legacy help keys.
- Add role-specific help/reference content only where the short-help level is insufficient.
- Add changelog cross-reference enforcement for `@doc.changed` after release-note conventions are adopted.
- Add a PR CI workflow after the pilot grammar and generated outputs have been reviewed; no repository-wide CI enforcement was introduced here.
- Keep HTML deferred, as specified by the architecture.

## 15. Risks

- The parser supports adjacent documentation blocks on function declarations, not arbitrary Lua expressions or every possible annotation target. Unsupported structures fail rather than being guessed.
- Three existing help keys remain orphan warnings until their UI references or dispositions are reviewed.
- Locale-key parity cannot judge translation quality; the new French wording still requires human review.
- The installed Pester version is 3.4; tests were written and run against that version. Pin a version before adding CI.
- The runtime tooltip facade is not implemented yet, so Phase 1 proves metadata-to-document generation but does not yet remove duplicated UI wiring.

## Explicit Outcomes

- Production behavior changed: **NO**
- SavedVariables changed: **NO**
- Localization architecture changed: **NO**
- Business logic changed: **NO**
- Generated docs deterministic: **YES**
