# DIBS 0.8.0 Release Candidate Evidence

## Phase 1: Fresh Automated Baseline

- Date: 2026-09-26
- Source commit: `19ea02f547d2fadc9a9e8b0259cb6972f1156460`
- Addon version: `0.8.0` (`src/Core.lua` and TOC)
- Full suite command: `npx.cmd --yes fengari tests/run.lua`, with all current `tests/**/*_spec.lua` supplied through `DIBS_TEST_FILES`.
- Spec files: **144**
- Passed: **745**
- Failed: **1**
- Duration: **308.10 seconds**
- Exit code: `1` because of the accepted known failure below.

### Failure Classification

| Classification | Test | Assertion | Evidence |
|---|---|---|---|
| `CONFIRMED_PRE_EXISTING` | `tests/integration/predibs_sync_recovery_spec.lua` — `Pre-Dib recovery sync / uses AceComm registration and AceTimer for one bounded anti-entropy heartbeat` | Line 50: expected `1`, got `2` | The full suite and an isolated run of this exact spec produce the same test failure and values. This is the previously tracked heartbeat timer assertion; no new unexplained regression was found. |

No other failures were reported in the full suite.

### Required Checks

- `git diff --check`: **PASS**. Git reported existing LF-to-CRLF working-copy warnings; no whitespace errors.
- `scripts/Generate-DibsDocs.ps1 -Validate`: **PASS** — 27 concepts, 0 errors, 0 warnings, 0 missing enUS/frFR entries, 0 duplicate IDs.
- `scripts/Generate-DibsDocs.ps1 -Check`: **PASS** — generated files are current.

### Gate 1

**PASS** — fresh baseline recorded; the only failure matches the known test, assertion, expected/actual values, and isolated reproduction. No unexplained regression blocks certification work.

Retail certification has not been performed. No Retail result is implied by this automated baseline.

## Phase 2: Post-Fix Release Candidate

- Date: 2026-09-29
- Source commit: `21f17b3`
- Addon version: `0.8.0` (`src/Core.lua` and TOC)
- Full suite: **824 passed, 0 failed (144 files)**.
- Focused Cosmetic/Loot Rules and RCLootCouncil button suites: **73 passed, 0 failed (4 files)**.
- B11 Retail UI-003: **9 passed, 0 failed (1 file)**.
- `git diff --check`: **PASS**.
- The Pre-Dib heartbeat test now distinguishes its recurring timer from the separate one-second digest timer.
- The Officer channel-test action preserves and displays both values returned by `Sync.StartChannelTest`.
- Pylance reports no actionable error in `RCLootCouncil.lua`; it does not recognize the repository's custom `@doc.*` annotations in `OfficerUI.lua`.

### Operator-Reported Retail Validation

- Local environment metadata: WoW `12.1.0.69933`; RCLootCouncil `3.23.3`; operator is not GM.
- The operator reports all package and Retail checks passed except the positive historical-confirmation path with a current guild member.
- That path is deferred until the next raid because the operator cannot exercise it beforehand. A non-member receiving `UNKNOWN_ROSTER_MEMBER` is expected fail-closed behavior.
- The release owner accepts this single validation exception for `v0.8.0`. The positive in-guild path is explicitly not claimed as tested; it remains a follow-up validation.
