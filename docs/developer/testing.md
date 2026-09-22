# Testing and development

The automated suite runs in Lua through Fengari with WoW, Ace3, and optional RCLootCouncil doubles:

```powershell
npx.cmd --yes fengari tests/run.lua
```

Use `DIBS_TEST_FILES` to run a semicolon-separated subset. Tests cover domain policies, ledger invariants, SavedVariables migration, sync validation, import/export limits, RC capability degradation, UI callback wiring, optional-module navigation and guards, and TOC load integrity. The 0.6.4-dev development pass is currently validated with 558 passing tests in 136 files; real Retail validation remains separate.

The First Installation Assistant focused slice is:

```powershell
$env:DIBS_TEST_FILES = "tests/contract/setup_assistant_contract_spec.lua;tests/integration/setup_assistant_spec.lua;tests/integration/setup_assistant_ui_spec.lua"
npx.cmd --yes fengari tests/run.lua
Remove-Item Env:DIBS_TEST_FILES -ErrorAction SilentlyContinue
```

The assistant is an Officer-only transient projection. Its supported changes
use ProtectedActions, and its local dry-run must not be treated as Retail
validation.

The Data Health Dashboard is a read-only Officer projection in Diagnostics. It
aggregates persistence, readiness, RCLootCouncil, synchronization, and backup
status without exposing ledger rows, player identities, private evidence, or
raw transport payloads. Its unavailable and degraded states are not readiness
certification.

Player notifications are local-only projections. They use the existing
`Dibs.Message` path, filter to the local character, deduplicate through a
bounded per-character store, and never change domain or synchronization state.

Retail-only checks remain manual: protected-frame behavior, real RC callback
authority, Blizzard Encounter Journal timing, guild roster identity, visual
layout at multiple scales, two-client coordinator handoff, partition/recovery,
and clean-package installation. Do not report those as automated results.

The B12 release evidence is indexed in
[`docs/audits/B12_Release_Candidate_Evidence.md`](../audits/B12_Release_Candidate_Evidence.md).
It keeps automated counts, manual Retail status, known baselines, and sandbox
limitations separate so a green Fengari run cannot imply Retail certification.

The release gate also requires the current B00-B09 evidence records, an explicit
`V2_ENFORCED` cutover test, exact-sequence/gap recovery, coordinator-unavailable
proposal behavior, and validation of the specific RCLootCouncil profile. Until
those checks are recorded, `RETAIL_RUNTIME_VALIDATION` remains pending and the
development tree must not be described as production-ready.

Developer mode and DryRun are test/dev-only surfaces. They must not bypass permission, readiness, combat, or append-only accounting rules. Add tests when changing a rule or compatibility boundary, not for comments that do not alter behavior.

The developer sandbox is bounded and fail-closed. `SANDBOX_STORE_TOO_LARGE` is a
developer-only retained-store limitation; Developer Mode is off by default and
normal production state must remain isolated when the limit is reached.
