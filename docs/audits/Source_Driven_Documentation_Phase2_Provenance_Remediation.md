# Source-Driven Documentation Phase 2 Provenance Remediation

Date: 2026-09-25
Scope: Remediate the Player-guide implementation-provenance leak only. No runtime/business behavior, concepts, semantic IDs, source annotations, or localization architecture were changed. No commit was created.

## Results

| Gate | Result | Evidence |
| --- | --- | --- |
| Renderer output policy | PASS | Player, Officer, and GM use the `user-facing` profile; the Developer reference uses the `technical` profile. User-facing role rendering omits source links; technical rendering retains them. |
| User-facing role guides | PASS | Direct scan found zero implementation source paths, `.lua` filenames, `Source:` fields, or symbols in Player, Officer, and GM guides. |
| Player synchronization content | PASS | Player guide still includes its Synchronization section and the `sync.status` explanation. |
| Normalized provenance | PASS | `sync.status` retains `sourceFile`, `sourceLine`, and `symbol` in the model. |
| Technical/reference provenance | PASS | Developer reference and UI reference include `src/modules/SyncV2.lua`, a source line, and `Sync.GetStatus`; Developer output includes the full normalized catalog and retains audience metadata. |
| Machine-readable provenance | PASS | CSV and JSON preserve `sync.status` source file, source line, and source symbol. |
| Catalog integrity | PASS | 26 concepts; 0 validation errors, 0 warnings, 0 missing enUS/frFR values, and 0 duplicate IDs. |
| Windows PowerShell 5.1 | PASS | Pester 3.4.0: 26 passed, 0 failed. |
| PowerShell 7.6.6 | PASS | Pester 3.4.0: 26 passed, 0 failed. |
| Generated artifacts | PASS | All eight artifacts regenerated; generator `-Check` reports current. |
| Cross-version determinism | PASS | Windows PowerShell 5.1 and PowerShell 7.6.6: SHA-256 comparison 8/8 MATCH. |
| Lua help tests | PASS | Focused `ui_help_content_spec.lua`: 11 passed, 0 failed. |
| Whitespace | PASS | `git diff --check` found no whitespace errors. Git emitted only LF-to-CRLF working-copy notices for existing files. |
| Runtime/business boundaries | PASS | This remediation changed only the docs renderer, its Pester regression coverage, and generated documentation. No runtime/business code or source annotations were edited for this remediation. |
| Worktree/commit | PASS | No files staged and no commit created. Existing Phase 2 and unrelated worktree changes were preserved. |

## Change Summary

The root cause was unconditional source-link rendering by `ConvertTo-DibsMarkdownRole`. The renderer now requires an explicit output profile. User-facing guides continue to filter by audience and omit implementation provenance. The technical Developer reference renders the complete normalized catalog, retaining audience metadata and provenance for every concept. UI reference, CSV, and JSON provenance rendering remains unchanged.

A focused regression test verifies the user-facing/technical profile boundary and model traceability. All eight generated artifacts were refreshed. No concepts, IDs, source annotations, or locale architecture were altered.

## Final Decision

**READY FOR PHASE 2 RE-VALIDATION**
