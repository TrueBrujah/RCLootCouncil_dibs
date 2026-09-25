# Source-Driven Documentation Phase 2 Revalidation

Date: 2026-09-25
Mode: Final read-only re-validation. No source, tests, generated artifacts, or staging state were changed. This report is the only file created for this re-validation; no commit was made.

## 1. Provenance Policy: PASS

Checked the actual renderer and generated artifacts. Player, Officer, and GM guides contain no source path, source line, `Source:` field, or model source symbol/API; Player still documents Synchronization and `sync.status`. The Developer reference contains all 26 catalog entries and preserves each entry's audience, source file, source line, and source symbol. UI reference preserves provenance for all entries. CSV imports as 26 rows with source file, line, and symbol. JSON parses as 26 concepts with typed source line numbers, source strings, booleans, and audience arrays.

## 2. Concept Catalog: PASS

The live validator reports 26 concepts, 0 errors, 0 warnings, 0 missing locale values, and 0 duplicate IDs. All IDs match the canonical lowercase dot-delimited format and are unique. Every concept has valid audience metadata, nonempty localized label/help, and a source file, in-range declaration line, and symbol. The concepts have distinct, descriptive labels/help rather than placeholder entries.

The live ID set exactly matches the 26 IDs recorded by the Phase 2 final-validation baseline; the provenance remediation did not alter semantic IDs.

## 3. Help Gaps and Orphans: PASS

The current Pester matrix test verifies all seven prior gaps have their specified dispositions and rejects any remaining `MISSING` row. `UI_HELP_ENCOUNTER` has been removed and has no current consumer. `UI_HELP_REASON` is reused by `ledger.adjust.reason`; `UI_HELP_SETUP_ASSISTANT` is reused by `setup.assistant.readiness`.

The live catalog has 0 `orphan-help-key` warnings. A disposable copy of `src` with one unreferenced probe key produced exactly one `orphan-help-key` warning, confirming the detector remains active.

## 4. Validator Integrity: PASS

The current Pester suite passes all 26 tests. Its negative fixtures still exercise duplicate IDs, malformed IDs, missing enUS/frFR, invalid audience, permission, scope, and version, plus Developer-only terminology leakage into Player output. The disposable orphan probe separately confirms orphan detection. The module diff is limited to role-rendering selection and provenance emission; validator rules were not weakened or changed.

## 5. Localization: PASS

`Dibs.L` remains the shared locale table used by both catalogs and is listed in the addon's ordered TOC. `src/locales/` contains only `enUS.lua` and `frFR.lua`; parsed key sets match exactly. The French catalog's ASCII-only convention is unchanged (0 non-ASCII characters in both HEAD and current files), and a mojibake-marker scan found no matches.

## 6. Generated Artifacts: PASS

All eight required artifacts exist and generator `-Check` reports current; no project artifact regeneration was performed. The six Markdown files retain the generated/no-edit header. CSV parses successfully, JSON parses with typed fields, and all eight files are valid UTF-8 without BOM and use LF newlines. Deterministic rendering is covered by Pester and the cross-version hash test.

Artifacts checked: `player-guide.md`, `officer-guide.md`, `gm-guide.md`, `developer-reference.md`, `ui-reference.md`, `terminology.md`, `documentation.csv`, and `documentation.json`.

## 7. Cross-Version and Test Gates: PASS

| Gate | Result |
| --- | --- |
| Windows PowerShell 5.1 Pester | 26 passed, 0 failed |
| PowerShell 7.6.6 Pester | 26 passed, 0 failed |
| Cross-version artifact SHA-256 | 8/8 MATCH |
| Lua help spec | 11 passed, 0 failed |
| PlayerUI integration spec | 4 passed, 0 failed |
| Catalog validator | 26 concepts, 0 errors, 0 warnings |
| Artifact freshness | PASS |
| `git diff --check` | PASS; only existing LF-to-CRLF notices |

## 8. Business-Behavior Isolation: PASS

The complete source diff consists of documentation annotations, localized strings, and presentation/help substitutions. Ledger balance and transaction logic, RankRules calculations, Governance and authority, permissions, Sync protocol behavior, SavedVariables, RCLootCouncil decisions, and Pre-Dibs behavior were not changed. In particular, `Core.lua`, the TOC/SavedVariables declarations, `Governance.lua`, `RankRules.lua`, `Permissions.lua`, and `ProtectedActions.lua` are unchanged. The changed `Ledger.lua`, `PreDibs.lua`, and `SyncV2.lua` hunks add documentation annotations only; integration/UI hunks affect annotations or displayed help text/tooltips.

## 9. PlayerUI Diagnostic: STALE

Current editor diagnostics on `PlayerUI.lua` are limited to unknown custom `---@doc.*` annotations. They do not report a Lua parse or block-structure error. The current PlayerUI source loads under Fengari and its focused integration spec passes 4/4. Classification: **STALE_TOOLING_DIAGNOSTIC**, not a reproduced syntax failure.

## 10. Worktree Scope: PASS

`git status --short`, `git diff --stat`, `git diff`, and `git ls-files --others --exclude-standard` were inspected at validation time. The tracked Phase 2 scope is identifiable: 29 files, 1,979 insertions, 150 deletions, covering the two help audits, eight generated artifacts, renderer, source annotations/localized UI help, and focused tests. The two pre-existing untracked checklist audits, `DIBS_Guided_Setup_Wizard_Post_Implementation_Validation.md` and `DIBS_Retail_Manual_Validation_Checklist.md`, are explicitly excluded from the Phase 2 count. At validation time, the Implementation, Final Validation, and Provenance Remediation reports were untracked; no files were staged and no commit had been created.

## Final Summary

Provenance policy: PASS
Concept catalog: PASS
Help gaps/orphans: PASS
Validator integrity: PASS
Localization: PASS
Generated artifacts: PASS
PS5.1: PASS
PS7.6.6: PASS
Cross-version determinism: PASS
Lua help: PASS
PlayerUI diagnostic: STALE
Business behavior isolation: PASS
Worktree scope: PASS

## Final Decision

**READY TO COMMIT**
