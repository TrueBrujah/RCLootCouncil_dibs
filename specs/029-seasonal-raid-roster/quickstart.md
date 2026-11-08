# Feature 029 Validation Quickstart

Planning-only validation scenarios for implementation. No test or Retail validation result is asserted here. Keep tests on synthetic SavedVariables and preserve the user's current data.

## Automated validation matrix

1. **Lifecycle**: create draft, edit settings, open/close registration, ready, activate, complete, archive; invalid transitions fail without changing active season.
2. **Enrollment**: player self-signup/edit/withdraw; reject another player's identity, closed registration, stale revision, duplicate replay, and disabled module.
3. **Season isolation**: create two seasons; verify rules, status choices, signup approvals, allocations, and ledger events never cross season IDs.
4. **Core path**: request Thursday Core progression, show Raider/candidate, manually promote/decline with a policy revision and actor/reason; verify no automatic attendance claim and no native guild-rank mutation.
5. **Rules versioning**: publish a rule edit; prior season and historical signup/decision snapshots retain the original revision.
6. **Roster scale**: use 20, 60, 500, and 1,000 synthetic characters, including 900 inactive/non-enrolled guild members; compare expected allocation and reconciliation work to only the approved seasonal cohort.
7. **Rank handling**: approved guild members map to per-season native guild rank allocation; external/no-rank participants require an explicit policy or are blocked. Rank changes after preview invalidate the preview.
8. **Three reconciliations**: historical Main/Alt balances require review and retain selected Main balance; new-season allocation starts independently; active-season drift is a separate preview/apply.
9. **Atomic activation**: inject failure before each activation stage and verify no partial active state, no duplicate starting allocation, and previous season/ledger remains visible.
10. **Sync**: two clients, authorized and unauthorized senders, partial/missing chunks, late dependency, replay, conflict, guild switch, offline catch-up, module disabled, max-size payload; incomplete data never becomes active.
11. **Migration**: old Dibs and roster season IDs, aliases, enrollment revisions, and ledgers survive repeat migration; ambiguous associations request review and are not guessed.
12. **UI/performance**: cold and warm page rendering, bounded pagination, narrow/wide window, repeated navigation, rule editor, roster review, activation preview. Separate measured CPU time and Lua heap snapshots from static estimates.

## Suggested focused test commands

Discover exact test names and the repository's PowerShell test convention during implementation. Run only focused suites first, for example service/lifecycle, permissions, CharacterEligibility, ledger, SyncV2, PlayerUI and OfficerUI tests. Record exact commands and observed results in this file; do not mark any test complete before running it.

## Retail two-client validation (release gate)

- Use a controlled guild/season and two clients: verified GM/Officer and normal member.
- Confirm member signup and read-only roster, GM/Officer approval, rule/status revision, explicit activation, active-season allocation, rank change preview invalidation, and later sync catch-up.
- Confirm a client with partial dependencies keeps the prior season active and indicates incomplete sync.
- Confirm disabling the module blocks player/officer writes and received mutations without deleting season history.
- Confirm out-of-guild character handling follows configured no-rank policy.
- Test with RCLootCouncil installed and absent; Dibs authorization and core season workflow must remain available.
- Capture UI timings and responsiveness on representative roster sizes. These checks require actual Retail clients and cannot be inferred from Fengari/static code.

## Evidence log

No implementation validation has been run for this planning revision. Add date, commit/build ID, exact command or in-game scenario, and result when evidence exists.
