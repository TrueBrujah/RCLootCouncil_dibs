# Source-Driven Documentation Phase 1 Validation

Status: READ-ONLY VALIDATION. No source, test, or generated output was changed during this review. This requested report is the only file created.

## Result

| Area | Result |
| --- | --- |
| Architecture compliance | PARTIAL |
| Localization integrity | PASS |
| Permission isolation | PASS |
| Determinism | PARTIAL |
| CLI | PARTIAL |
| Tests | PARTIAL |

**Decision: NOT READY TO COMMIT.** The CSV renderer corrupts embedded line breaks, and Windows PowerShell 5.1 produces different JSON bytes and fails the test suite. CSV and JSON also lack an explicit generated marker.

## Scope and Method

Compared the [architecture](Source_Driven_Documentation_Architecture.md), [implementation report](Source_Driven_Documentation_Phase1_Implementation.md), current annotations, runtime permission code, locale files, generator, generated outputs, and tests. Ran validation and `-Check` under PowerShell 7.6.6, ran the Pester and Lua help suites, exercised invalid-model CLI failure in a disposable temporary fixture, and rendered adversarial CSV/UTF-8 cases in memory or under the system temp directory. No `-Generate` was run against the repository.

The worktree was already dirty. Diff inspection found Phase 1 source hunks are Lua documentation comments, but it also found unrelated executable changes in `src/modules/RankRules.lua` and `src/modules/SyncV2.lua`. Those changes cannot be attributed to this documentation implementation. The implementation report's no-behavior-change claim is supported for the documentation hunks, not for the entire dirty worktree.

## Architecture Checks

1. **Canonical IDs: PASS.** Exactly ten concepts are extracted. All IDs conform to lowercase dot-delimited tokens: `guild.setup`, `ledger.adjust`, `ledger.balance`, `predibs.encounter.mode`, `predibs.request`, `rank.allocation`, `setup.reconciliation`, `sync.coordinator`, `sync.protocol.state`, and `sync.status`.
2. **Metadata is not runtime authority: PASS.** `@doc.*` occurs only in Lua comments. Runtime authorization remains in executable protected-action and `Dibs.Permissions` paths; the generator does not execute or consume annotations at runtime.
3. **Permission metadata is descriptive: PASS.** The generator checks annotated permission IDs against the protected-action registry and includes them in documentation output. No runtime permission check reads documentation metadata.
4. **Localization source: PASS.** Referenced labels, help, and technical reference are resolved from the existing `Dibs.L` assignments in `enUS.lua` and `frFR.lua`. No second translated-content catalog or runtime help facade was introduced.
5. **No duplicated translated prose in annotations: PASS.** Annotations contain controlled values and locale keys only. Technical reference prose is in the two locale files.
6. **Shared model: PASS.** Markdown, CSV, and JSON renderers all receive the concepts from `Get-DibsDocumentationModel`; none reparses source independently.
7. **Determinism: PARTIAL.** Repeated PowerShell 7 in-memory rendering yielded byte-identical strings for all eight outputs, and the existing Pester repeat-write test passes. Windows PowerShell 5.1 serializes `documentation.json` with different indentation, so `-Check` rejects the checked-in file. Validator warning order also varies between runs because legacy keys are traversed from an unordered hashtable.
8. **Source traceability: PASS for current pilot.** All ten reported source lines were checked against the current declaration symbols. Generated role references use relative source links and line anchors. The test suite itself asserts detailed trace data for only one fixture concept.
9. **Player filtering: PASS.** Four Player concepts are present; `sync.protocol.state` and protocol terms are absent from Player output.
10. **Officer filtering: PASS.** Eight Officer concepts include operational rank, ledger adjustment, reconciliation, and synchronization information.
11. **GM filtering: PASS.** Nine GM concepts include `guild.setup`, reconciliation, coordinator, and administrative concepts.
12. **Developer filtering: PASS.** Developer output includes `sync.protocol.state` and its technical reference.
13. **Missing locale detection: PASS.** Separate Pester cases detect absent enUS and frFR values. Current validation reports zero missing values for either locale.
14. **Duplicate IDs: PASS.** Duplicate IDs produce an error; a Pester fixture asserts rejection.
15. **Invalid versions: PARTIAL.** Invalid `since` is covered and rejected. The implementation also checks `changed`, `deprecated`, and `removed`, but their invalid cases are not tested.
16. **Invalid controlled values: PASS for tested values.** Invalid audience, permission, and scope values are rejected by fixtures. Unknown tags, invalid booleans, duplicate singleton tags, and category validation lack equivalent tests.
17. **Orphan warnings: PASS as non-blocking legacy findings.** `UI_HELP_ENCOUNTER`, `UI_HELP_REASON`, and `UI_HELP_SETUP_ASSISTANT` exist in both locale catalogs and have no direct first-party source reference. They are emitted as `WARNING`; the CLI exits nonzero only for errors. Current `-Validate` exits zero with all three warnings. The key inventory is still an explicit migration exception, not proof that these keys are currently used.
18. **Repeated output: PASS within PowerShell 7.** In-memory outputs and the test's repeated temporary-file writes were byte-identical. Repository files were not regenerated during this review.
19. **Generated markers: PARTIAL.** All six Markdown files begin with `THIS FILE IS GENERATED.` and `DO NOT EDIT MANUALLY.` CSV and JSON do not explicitly identify themselves as generated.
20. **Runtime/business behavior: PASS for Phase 1-specific hunks, with worktree caveat.** Phase 1 additions in source are comments and locale assignments; they do not change executable behavior. Separate executable diffs already present in `RankRules.lua` and `SyncV2.lua` make a whole-worktree no-behavior-change claim invalid without isolating those changes.

## CLI and Format Checks

- `-Validate` from the repository root passed with 10 concepts, 0 errors, 0 locale gaps, 0 duplicate IDs, and 3 warnings. The default mode is also validation.
- `-Check` passed under PowerShell 7.6.6 with generated files current.
- A disposable fixture with an invalid version passed to `-Generate` returned exit code 1 and wrote no outputs. This verifies validation failure propagation; the successful repository `-Generate` mode was not run to preserve generated files.
- Default paths worked when invoked from both the repository root and a different working directory. Paths are derived from script location or the supplied `-Root`, not this developer's absolute machine path.
- Concept/file ordering in generated outputs is stable and ID-sorted. Diagnostic warning order is not stable, as noted above.
- CSV commas and embedded double quotes round-trip correctly. Embedded CRLF does not: `ConvertTo-DibsCsv` replaces LF with the two literal characters backtick+n instead of preserving the newline inside the quoted field. This is a content-changing violation of RFC 4180 field handling. See [DibsDocumentation.psm1](../../scripts/docs/DibsDocumentation.psm1#L570).
- JSON parses successfully. A synthetic accented French string survived strict UTF-8 encoding/decoding through the writer, with no BOM. The current pilot French strings are mostly ASCII transliterations, so live accented locale data was not independently exercised.
- Windows PowerShell 5.1 is present and the repository contains Windows PowerShell/.NET Framework compatibility guidance. Under 5.1, `-Validate` passed but `-Check` failed because `documentation.json` formatting differed from PowerShell 7. The Pester 3.4 suite passed 12/21 and failed 9/21 under 5.1; under PowerShell 7.6.6 it passed 21/21. No explicit minimum version for this new generator was found, but 5.1 compatibility is not currently demonstrated.

## Test Results and Coverage

- PowerShell / Pester 3.4 under PowerShell 7.6.6: **21 passed, 0 failed**.
- The same PowerShell suite under Windows PowerShell 5.1: **12 passed, 9 failed**.
- Targeted Lua UI-help suite: **10 passed, 0 failed**. It checks locale key values and selected English/French content, not generator behavior.

| Coverage area | Rating | Evidence / gap |
| --- | --- | --- |
| Parser | PARTIAL | Valid extraction, aliases, source binding, and orphan annotations are tested; lexical edge cases and full field-error coverage are absent. |
| Validation | PARTIAL | IDs, duplicate IDs, versions, locale gaps, permissions, audiences, scopes, and orphan annotations have fixtures; several schema rules remain untested. |
| Localization resolution | STRONG | Unknown help key and separate missing-enUS/missing-frFR cases are tested; both Lua locales are checked by the 10 help specs. Translation quality remains human-reviewed. |
| Role filtering | PARTIAL | Player exclusion, Officer operations, GM setup, and Developer-only output are covered, but the matrix is not exhaustive. |
| Deterministic generation | PARTIAL | Renderers and repeat writes are checked within one runtime; no test covers cross-version byte equality, which currently fails on 5.1. |
| Source traceability | PARTIAL | File, line, module, symbol, and JSON trace are asserted for one fixture; generated links and all live concepts are not test-covered. |
| CLI failure behavior | MISSING | No Pester test invokes the CLI or asserts exit codes. Manual invalid-model `-Generate` returned 1 and wrote nothing. |

## Required Follow-Up Before Commit

1. Preserve embedded CSV newlines according to RFC 4180 and add comma/quote/newline round-trip tests.
2. Make JSON serialization byte-stable across the supported PowerShell versions, or explicitly raise/document the generator's minimum version and align tests and generated outputs.
3. Add CLI-level tests for `-Validate`, `-Generate`, `-Check`, mode conflicts, exit codes, and root resolution.
4. Decide how CSV and JSON identify generated ownership without breaking their formats.
5. Review and isolate the unrelated executable worktree diffs before making a commit-readiness claim for the full change set.
