# B09 Implementation Evidence

## Scope and commits

- Branch: `dev`
- `B09_START_COMMIT=0ba6315c455d6ec52a6b69f59559cdaae12fcccd`
- `B09_CHECKPOINT_COMMIT=NONE` (no prior B09 checkpoint was present; unrelated dirty work was preserved)
- `B09_RESULT_COMMIT=6760a33a162f764899d48f43291e6c3a562698de`

The result commit contains only the B09 adapter implementation, focused tests,
authority-contract updates, adapter matrix, and Retail checklist. Existing
unrelated changes in `.specify/`, `docs/RC_OPTIONS.md`, workspace metadata,
and `.github/skills/` were not staged or modified by B09.

## Requirement status

| B09 requirement | Status | Evidence |
| --- | --- | --- |
| Optional versioned RCLootCouncil adapter | COMPLETE | Exact fixture profile `DIBS_RCLC_AWARD_TEST_V1` requires version marker `DIBS_TEST_RCLC_AWARD_V1`; no Retail release is implicitly supported. |
| Explicit supported/unsupported capability profiles | COMPLETE | `GetAwardAdapterStatus()` and `GetCapabilities()` expose adapter identity, version, state, reason, and `awardEvidence`. |
| Versioned callback/status normalization | COMPLETE | Only `RCMLAwardSuccess` and profile status `awarded` normalize to `FINAL_AWARD`; raw RC tables are not canonical evidence. |
| Unknown version/callback/status fails closed | COMPLETE | Unknown/unsupported profiles, callbacks, statuses, identities, and item links return ignored/rejected results without a debit. |
| Normalized `awardEvidence` only | COMPLETE | The adapter persists a Dibs-owned normalized receipt and passes normalized fields to the protected command. |
| Evidence uses the existing B06 protected core path | COMPLETE | `FinalizeAward()` calls `Ledger.CommitDibUse()`; no direct ledger mutation exists in the adapter. |
| Non-coordinator cannot directly debit canonical balance | COMPLETE | B09 test proves a supported callback on a follower returns `CURRENT_COORDINATOR_REQUIRED` with `PENDING_RECONCILIATION`, zero balance change, and zero canonical commits. |
| B06 authority remains authoritative | COMPLETE | RC Master Looter is no longer an authorization source; guild permissions and B06 coordinator checks remain authoritative. |
| No new synthetic RCLootCouncil history writes | COMPLETE | Pre-Dib creation/status paths no longer call RC history logging; history access is read-only. |
| Existing `dibsOrigin` rows preserved/display-only | COMPLETE | Legacy rows are marked display-only and `ConfirmReconciliationCandidate()` rejects them with `HISTORY_LEGACY_DISPLAY_ONLY`. |
| RCLootCouncil history read-only from Dibs | COMPLETE | History projection calls `GetHistoryDB()` only and never mutates the returned RC-owned table. |
| B07 capability lifecycle reused | COMPLETE | Late-load and retry behavior remains through the existing optional capability initialization path. |
| B08 UI/combat ownership remains intact | COMPLETE | B08 ownership/combat regression suite passes; adapter changes do not alter RC-owned handlers or scheduler behavior. |
| Standalone Dibs works without RCLootCouncil | COMPLETE | Absent/unsupported RC tests preserve core permissions and leave standalone ledger available. |
| Live Retail validation for a real RC release | PARTIAL | Automated fixtures and static checks are complete; no live Retail client validation was performed. |
| B10 release documentation/gate | NOT STARTED | B10 was not modified or started. |

## Validation

Focused B09 adapter suite:

```text
6 passed, 0 failed (1 file)
```

Targeted B06/B07/B08 and changed RC contract suites:

```text
38 passed, 0 failed (10 files)
```

Complete automated suite on the final B09 tree, using the runner's supported
explicit file-list override on Windows:

```text
313 passed, 1 failed (66 files)
```

The sole failure is the established pre-B09 projection baseline:

```text
FAIL RCLootCouncil DIB response projection /
  renders the voting Dibs value from a normalized RCLootCouncil row identity
tests/integration/rclootcouncil_buttons_spec.lua:155: expected 2/2, got 1/1
```

The stale authority-matrix expectation exposed by the full suite was updated to
the B09 guild-authority contract and passes independently.

## Boundary review

- Unknown or unsupported RC versions cannot reach normalized evidence or consume a Dib.
- Unknown callback/status, malformed item identity, ambiguous recipient identity,
  and conflicting evidence are rejected or ignored before protected accounting.
- RC history is never an active award-identity fallback and no active Dibs path
  writes to RC-owned history.
- The adapter has no direct canonical ledger mutation API; all automatic award
  accounting reaches B06 `CommitDibUse()` through `ProtectedActions.FinalizeAward()`.
- Non-coordinator, unavailable, sync-behind, and recovery outcomes remain
  proposal/rejection paths with no local canonical debit.
- B08 RC-owned click handlers and combat-safe Dibs-owned projection scheduling
  remain covered by the targeted regression suite.

## Retail gate

`RETAIL_RUNTIME_VALIDATION = PENDING_B10_RELEASE_GATE`

Only the fixture profile is enabled for automated evidence. A real Retail
RCLootCouncil version must not be added to the adapter matrix until the live
checklist in `B09_Retail_Validation_Checklist.md` is completed during B10.
