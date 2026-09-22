# B12 Release UI Hardening Evidence

## Scope

This record covers B12 setup and foundational validation. It does not certify
Retail behavior or release readiness.

## T008 freeze-boundary verification

The B12 source scan was run against `src/` for task-driven markers and
presentation-only domain fields:

- No `B12` task markers were found.
- No `supportTicket`, `ticketCategory`, or `ticketStatus` fields were found.
- No `releaseCandidate` runtime field was found.
- No new request lifecycle state marker was found.

The current worktree contains pre-existing Great Vault implementation changes in
`src/modules/SyncV2.lua`, `src/ui/OfficerUI.lua`, and `src/ui/PlayerUI.lua`.
Those belong to specification 013 and are not reverted by this B12 increment.
B12 source changes in this increment are limited to transient Officer request
projections and object-aware request context-menu callbacks; no authority or
persistence contract was added.

The following boundaries remain enforced by the B12 contract:

- UI projections do not write ledger, balance, policy, authority, award, or RCLootCouncil history state.
- B12 adds no production SavedVariables, SyncV2 fields, or request lifecycle states for presentation-only behavior.
- Dangerous actions continue through existing authorization, readiness, confirmation, reason, and protected-action services.
- Player, Officer/GM, and Developer Mode projections retain their existing privacy and provider boundaries.

## Automated evidence

Focused B12 manifest:

```text
55 passed, 0 failed (16 files)
```

Full Fengari suite:

```text
541 passed, 0 failed (128 files)
```

Diagnostics for changed B12 Lua and Markdown files report no errors. The scoped
`git diff --check` is clean.

## Completed setup and foundation tasks

- T001: focused manifest and baseline notes in `docs/TEST_PLAN.md`
- T002: UI fixture builders in `tests/helpers/b12_ui_fixtures.lua`
- T003: request and historical fixture builders in `tests/helpers/b12_workflow_fixtures.lua`
- T004: ownership map and freeze constraints in `specs/012-release-ui-stabilization/contracts/release-ui.md`
- T005: foundational ownership, menu, delegation, and sandbox contracts
- T006: transient projection assertions
- T007: focused quickstart command and baseline handling
- T008: source-boundary verification recorded here
- T027: request-row and request-detail support-ticket projections
- T028: request action, privacy, confirmation, and protected-delegation contracts
- T029: request context-menu actions and shared menu cleanup
- T030: transient Officer support-ticket row/detail projection
- T031: presentation-only category aliases and unknown-category fallback
- T032: primary request action routing through existing Disputes transitions
- T033: object-aware request context actions for player, history, and item identifiers
- T034: separately disclosed advanced request actions with explicit protected permission gates and existing reason/confirmation/readiness workflows
- T035: Player-safe request projections and fail-closed advanced tools for unavailable Officer requests
- T036: bounded historical candidate summaries, collapsed technical review, safe classifications, protected rejection, and unavailable-integration coverage
- T037: Officer/GM privacy, shared menu lifecycle safety, reason and confirmation guards, protected delegation, idempotent replay, and no-RCLootCouncil-write assertions
- T038: bounded exact-alias filtering, source-scan metadata, related winners and difficulties, stable identities, ambiguous response identities, and already-accounted projections
- T039: complete Search -> Review historical summaries with item, winner, difficulty, encounter, award date, classification, duplicate state, and concise evidence
- T040: technical evidence remains collapsed by default and expands in the separate transfer review without replacing the primary summary
- T041: bounded date scans, exact aliases, related context, fail-closed unknown/non-final classifications, stable idempotency, and unknown-field labels
- T042: Officer/GM protected confirmation and rejection delegation with explicit reason/confirmation, idempotent replay, and combat-safe historical accounting without live readiness checks
- T043: real historical row context-menu coverage for review/evidence actions, with direct confirmation/rejection excluded and callbacks proven non-destructive
- T044: confirmed-history Player projection bounded to safe transaction summary fields while Officer review retains technical history and evidence references
- T045: reproducible focused/full Fengari commands with exit-code accounting, explicit baseline handling, workspace diagnostics, and complete-surface diff checks documented in the quickstart
- T046: single-client Retail matrix added to the test plan with ten lifecycle cycles, route/restoration, context-menu, Pre-Dib, combat, RCLootCouncil-state, privacy, history, and sandbox checks
- T047: conditional two-client matrix and explicit no-cross-client-change recording rule added to the test plan
- T048: focused B12 manifest passes with `56 passed, 0 failed (17 files)` after adding the release-candidate contract
- T049: explicit full Fengari manifest passes with `542 passed, 0 failed (129 files)`; the unrelated RCLootCouncil baseline remains separately identified
- T050: touched B12 diagnostics are clean and `git diff --check -- specs/012-release-ui-stabilization src tests docs` is clean apart from normal Windows line-ending warnings
- T051: pending real single-client Retail execution; see `docs/audits/B12_Retail_Validation_Evidence.md` for the required matrix and release gate
- T052: recorded `NOT REQUIRED: no B12 cross-client behavior change` because B12 does not modify SyncV2, synchronization payloads, or cross-client state propagation
- T053: focused sandbox validation passes with `6 passed, 0 failed (2 files)`, covering `SANDBOX_STORE_TOO_LARGE`, default-off entry, production isolation, protected mixed-provider rejection, and lifecycle persistence
- T054: release-candidate contract passes and asserts explicit runtime version, automated evidence counts, pending Retail gate, conditional two-client status, known limitations, changelog presence, and readiness gates
- T055: final installation, supported-route, known-issues, evidence-link, and publication-gate checklists added to the quickstart and test plan
- T056: TOC and runtime source owner aligned at `0.6.4-dev`; SavedVariables and protocol versions were not changed
- T057: dated `0.6.4-dev` changelog entry added with B12 scope, preserved business/security semantics, supported workflows, validation status, and known limitations
- T058: current README, Player, Officer, developer testing, and historical-version labeling are aligned with `0.6.4-dev`; current guides link the B12 Retail evidence gate
- T059: final release-candidate evidence index created with version, changelog, automated/Retail/cross-client links, known limitations, and blocked publication decision
- T060: deployment mirror and automated route coverage pass, but final task remains open pending real Retail installation, BugSack/taint review, and readiness-gate completion
- T061: developer architecture, module inventory, SavedVariables compatibility, and testing guidance now document B12 projection ownership, release evidence boundaries, and no new persistence/synchronization fields
- T062: reviewed the B12 spec-kit artifacts; corrected stale design-only status wording in `plan.md` and `research.md`, while preserving the explicit Retail and publication gates
- T063: complete quickstart validation passes with focused `56 passed, 0 failed (17 files)` and full `542 passed, 0 failed (129 files)`; all B12 evidence paths exist, diff check is clean apart from Windows line-ending warnings, and unrelated PreDibs diagnostics remain separately identified
- T064: freeze-boundary review found no B12 changes to accounting, award commit/proposal, governance, coordinator/recovery, SyncV2, identity, production permissions, Pre-Dib lifecycle, RCLootCouncil ownership, or sandbox isolation; unrelated Great Vault/B13 source changes are explicitly excluded
- T065: final readiness remains blocked by the unexecuted real Retail matrix; T051/T060 stay open and the unrelated RCLootCouncil baseline remains explicitly separated
- T022-T026: focused page, responsive, context-menu, normalization, authorization, sandbox, RCLootCouncil capability, and route coverage passes with `37 passed, 0 failed (5 files)`

## Remaining gates

Real single-client Retail validation remains required. The B11 UI-004 manual
baseline and any unrelated `tests/integration/rclootcouncil_buttons_spec.lua:155`
result remain separate from B12 automated evidence. No release readiness claim is
made from Fengari tests alone.
