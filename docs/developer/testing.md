# Testing and development

The automated suite runs in Lua through Fengari with WoW, Ace3, and optional RCLootCouncil doubles:

```powershell
$previousTestFiles = $env:DIBS_TEST_FILES
try {
    $files = Get-ChildItem tests -Recurse -File -Filter '*_spec.lua' |
        Sort-Object FullName |
        ForEach-Object { $_.FullName.Substring((Get-Location).Path.Length + 1) }
    $env:DIBS_TEST_FILES = $files -join ';'
    npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
    if ($LASTEXITCODE -ne 0) { throw "Fengari failed (exit $LASTEXITCODE)." }
} finally {
    $env:DIBS_TEST_FILES = $previousTestFiles
}
```

On Windows, provide `DIBS_TEST_FILES` because Fengari has no shell-based test
discovery backend there. Run from the repository root. For a behavior change,
prefer a semicolon-separated subset in the same `try/finally` wrapper; reserve
full discovery above for shared changes or release gates. Tests cover domain
policies, ledger invariants, SavedVariables migration, sync validation,
import/export limits, RC capability degradation, UI callback wiring,
optional-module navigation and guards, and TOC load integrity. The v0.8.0
release was validated with 824 passing tests in 144 files; real Retail
validation remains separate.

The First Installation Assistant focused slice is:

```powershell
$previousTestFiles = $env:DIBS_TEST_FILES
try {
    $env:DIBS_TEST_FILES = 'tests\contract\setup_assistant_contract_spec.lua;tests\integration\setup_assistant_spec.lua;tests\integration\setup_assistant_ui_spec.lua'
    npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
    if ($LASTEXITCODE -ne 0) { throw "Fengari failed (exit $LASTEXITCODE)." }
} finally {
    $env:DIBS_TEST_FILES = $previousTestFiles
}
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

The [v0.8.0 release evidence](../audits/DIBS_0.8.0_Release_Candidate_Evidence.md)
records automated results, manual Retail status, and the accepted validation
exception. The historical [B12 UI evidence](../audits/B12_Release_Candidate_Evidence.md)
remains useful for its specific scope. Keep automated counts and Retail
certification separate; a green Fengari run does not imply Retail certification.

Each release's evidence record is authoritative for its completed, deferred,
and accepted gates. For v0.8.0, the positive historical-confirmation path with
a current guild member is deferred until an eligible raid and is not claimed as
tested. Keep such exceptions explicit. A development tree must not be described
as production-ready until its applicable release gates are recorded.

Developer mode and DryRun are test/dev-only surfaces. They must not bypass permission, readiness, combat, or append-only accounting rules. Add tests when changing a rule or compatibility boundary, not for comments that do not alter behavior.

The developer sandbox is bounded and fail-closed. `SANDBOX_STORE_TOO_LARGE` is a
developer-only retained-store limitation; Developer Mode is off by default and
normal production state must remain isolated when the limit is reached.

The guild Loot Rules and rank-allocation reconciliation tests are exercised with:

```powershell
$previousTestFiles = $env:DIBS_TEST_FILES
try {
    $env:DIBS_TEST_FILES = 'tests\unit\guild_loot_rules_spec.lua;tests\integration\guild_loot_rules_spec.lua;tests\integration\guild_loot_rules_ui_spec.lua;tests\integration\season_catalog_sync_spec.lua;tests\integration\sync_status_spec.lua'
    npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
    if ($LASTEXITCODE -ne 0) { throw "Fengari failed (exit $LASTEXITCODE)." }
} finally {
    $env:DIBS_TEST_FILES = $previousTestFiles
}
```

The `LRA01`-`LRA22` scenarios cover adoption, publication, all dynamic keys,
catalog recovery, readiness, old-peer rejection, and raid-time application.
Retail two-client verification remains a separate release gate.

## Documentation-only validation

Documentation-only changes do not require Fengari or a package build.
Check local links, code/guide consistency, historical/current scope, and the diff.
Source-generated references can be checked without running addon code:

```powershell
.\scripts\Generate-DibsDocs.ps1 -Check
git diff --check
```

The generator validates annotated concepts, locale keys, and generated-output
freshness. It does not prove that every hand-written paragraph matches the UI,
nor does it certify Retail behavior. See the [documentation index](README.md).
