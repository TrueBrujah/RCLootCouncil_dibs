# Source-Driven Documentation Phase 1 Compatibility Remediation

Status: Compatibility and deterministic-output remediation complete. No runtime addon behavior, annotations, permissions, localization semantics, or SavedVariables were changed.

## Root Causes and Fixes

### CSV Line Breaks

The previous renderer quoted CSV cells and doubled embedded quotes correctly, but then removed every carriage return and replaced each line feed with the literal two-character sequence backtick+n. Thus CRLF became visible `\n` text, LF content was rewritten, and multiline text no longer round-tripped. Rows were assembled after transforming the fields, so the prior implementation hid rather than correctly represented multiline cells.

`ConvertTo-DibsCsv` now canonicalizes every field's line endings to LF, then wraps every field in double quotes and doubles embedded double quotes. It appends each logical record after serializing its fields; embedded LF remains inside the quoted field. CSV record separators are LF, matching the repository's generated-text policy. Tests parse the output and verify one logical row with simple, comma, quote, LF, CRLF, accented French, and multiple multiline cells.

### JSON and PowerShell 5.1

The previous JSON path used `ConvertTo-Json -Depth 20`. Its default indentation differs between Windows PowerShell 5.1 and PowerShell 7.6.6; the same ordered model produced different JSON byte streams and made 5.1 `-Check` report the JSON artifact stale. The values and semantic property order were otherwise valid; no business data or JSON type conversion caused the mismatch.

A small recursive serializer now writes the existing structured object graph with fixed two-space indentation, model property order, concept/array order, invariant numeric formatting, and LF newlines. It serializes strings, arrays, ordered objects, booleans, and nulls as their corresponding JSON types; strings escape quotes, backslashes, controls, and unpaired surrogates. Unsupported types fail explicitly. JSON remains structured and is not flattened.

### The Nine Original PowerShell 5.1 Test Failures

Windows PowerShell 5.1 scalar values do not provide the same `.Count` behavior as PowerShell 7 when a helper function emits a one-element array through the pipeline. Pester then received null for the affected count expressions. These were test-helper/runtime behavior failures, not production validation defects. Both hosts had Pester **3.4.0**, so there was no Pester-version difference.

The nine failing tests were:

| Test | Classification | Cause / correction |
| --- | --- | --- |
| rejects duplicate IDs and reports both the concept and duplicate rule | Runtime/API behavior | Singleton findings array was unrolled; helper now returns the array without enumeration. |
| rejects malformed semantic IDs | Runtime/API behavior | Same singleton-array unrolling. |
| rejects invalid lifecycle versions | Runtime/API behavior | Same singleton-array unrolling. |
| rejects an unknown help key | Runtime/API behavior | Same singleton-array unrolling. |
| reports a missing enUS value separately | Runtime/API behavior | Same singleton-array unrolling. |
| reports a missing frFR value separately | Runtime/API behavior | Same singleton-array unrolling. |
| rejects Developer-only terms if attached to a Player audience | Runtime/API behavior | Same singleton-array unrolling. |
| rejects unknown permission and scope values | Runtime/API behavior | Same singleton-array unrolling. |
| reports annotations not attached to a Lua function | Runtime/API behavior | Same singleton-array unrolling. |

No assertion was removed or weakened. `Get-FixtureRules` now returns a non-enumerated array so the same assertions behave consistently in 5.1 and 7.

The CLI's default `Root` initializer also evaluated `$PSScriptRoot` too early under Windows PowerShell 5.1 when launched with `-File`. Default root resolution now occurs in the script body after automatic variables are initialized. Default-root `-Validate` succeeds under both hosts from the repository root.

## Encoding and Newlines

The architecture specifies UTF-8 for CSV; the existing generator already wrote UTF-8 without BOM. That approved policy is retained and enforced with `UTF8Encoding(false)` for every generated file. The writer normalizes CRLF and lone CR to LF before writing, including embedded field text. Markdown, CSV, and JSON are therefore UTF-8 without BOM and use LF regardless of host PowerShell, Windows defaults, or `core.autocrlf`.

## Files Changed

- `scripts/docs/DibsDocumentation.psm1`: canonical LF normalization, CSV multiline-safe quoted fields, typed deterministic JSON writer, explicit UTF-8 without BOM output.
- `scripts/Generate-DibsDocs.ps1`: defer default repository-root resolution until script execution.
- `tests/powershell/Generate-DibsDocs.Tests.ps1`: preserve singleton arrays; add CSV round-trip cases for all requested values; assert JSON arrays/null/strings and byte encoding/newline policy.
- `scripts/Test-DibsDocsCrossVersion.ps1`: disposable-root workflow that invokes both installed runtimes through validation, generation, freshness checks, and SHA-256 comparison.
- `docs/generated/`: regenerated eight artifacts using the compatibility-safe serializer.
- `docs/audits/Source_Driven_Documentation_Phase1_Compatibility_Remediation.md`: this report.

No other source, test, locale, runtime, or authored documentation files were changed by this remediation. Existing unrelated worktree changes were preserved. No commit was made.

## Validation Results

| Check | Windows PowerShell 5.1 | PowerShell 7.6.6 |
| --- | --- | --- |
| PowerShell documentation tests | 22 passed, 0 failed (Pester 3.4.0) | 22 passed, 0 failed (Pester 3.4.0) |
| Documentation validation | 0 errors, 3 warnings | 0 errors, 3 warnings |
| Generation | Passed; 8 artifacts | Passed; 8 artifacts |
| Generated-file `-Check` | Passed | Passed |
| Repeated generation hashes | Stable for all 8 artifacts | Stable for all 8 artifacts |
| `git diff --check` | Passed | Passed |

Cross-version SHA-256 comparison: **8/8 MATCH** for player guide, officer guide, GM guide, Developer reference, UI reference, terminology, CSV, and JSON.

CLI default-root `-Validate` was also run from the repository root without an explicit `-Root` under both hosts; both passed.

The reusable workflow is `pwsh -NoProfile -File scripts/Test-DibsDocsCrossVersion.ps1`. It requires `powershell.exe` (Windows PowerShell 5.1) and `pwsh` (PowerShell 7), copies `src/` into isolated temporary roots, and leaves repository outputs alone while comparing each generated artifact.

CSV regression coverage passes under both hosts: simple values, commas, embedded quotes, LF, CRLF, accented French, multiple multiline fields, and repeated-render determinism. JSON parsing and type assertions pass under both hosts. The output writer tests confirm UTF-8 without BOM and LF-only bytes.

Targeted Lua UI-help suite: **10 passed, 0 failed**.

The same three documented non-blocking legacy warnings remain: `UI_HELP_ENCOUNTER`, `UI_HELP_REASON`, and `UI_HELP_SETUP_ASSISTANT` have no first-party source reference. Both runtimes report 10 concepts, 0 validation errors, 0 missing locale values, and 0 duplicate IDs.

## Final Result

CSV integrity: **PASS**

PowerShell 5.1 compatibility: **PASS**

PowerShell 7 compatibility: **PASS**

Cross-version determinism: **PASS**

Generated-file freshness: **PASS**

**FINAL DECISION: READY FOR PHASE 1 RE-VALIDATION**
