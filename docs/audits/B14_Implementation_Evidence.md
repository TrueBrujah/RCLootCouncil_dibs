# B14 First Installation Assistant Implementation Evidence

## Scope

This evidence covers specification `014-first-installation-assistant`: the
transient Officer setup projection, protected guided actions, local dry-run,
localized UI, documentation references, and automated regression validation.

## Implemented behavior

- The assistant projects RCLootCouncil, authority, season, rank-rule, channel,
and loot-type readiness checks without adding SavedVariables or SyncV2 fields.
- Administrative details are role-scoped to a verified guild GM or Officer.
- Supported season and installation-mode changes delegate through
`ProtectedActions`; the assistant does not mutate services directly.
- Local dry-run results are bounded and retained only as transient assistant
state; they do not change live loot, chat, ledger, or RCLootCouncil state.
- The Officer route is available at **Overview > Setup Assistant**.
- English and French labels, statuses, remediation text, and action controls are
localized. Player and GM/Officer guide entry points document the scope.

## Focused automated evidence

Command:

```powershell
$env:DIBS_TEST_FILES = "tests/contract/setup_assistant_contract_spec.lua;tests/integration/setup_assistant_spec.lua;tests/integration/setup_assistant_ui_spec.lua"
npx.cmd --yes fengari tests/run.lua
Remove-Item Env:DIBS_TEST_FILES -ErrorAction SilentlyContinue
```

Result:

```text
5 passed, 0 failed (3 files)
```

## Full regression evidence

Command:

```powershell
$files = Get-ChildItem tests -Recurse -Filter *.lua | Where-Object { $_.Name -ne "run.lua" } | ForEach-Object { $_.FullName.Substring((Get-Location).Path.Length + 1) }
$env:DIBS_TEST_FILES = ($files -join ";")
npx.cmd --yes fengari tests/run.lua
Remove-Item Env:DIBS_TEST_FILES -ErrorAction SilentlyContinue
```

Result:

```text
547 passed, 0 failed (132 files)
```

## Static and repository checks

- `get_errors` on the touched Lua files: no errors found.
- `git diff --check`: clean apart from normal Windows LF/CRLF conversion
warnings.
- No new SavedVariables fields were introduced.
- No new SyncV2 fields or ledger semantics were introduced.
- The unrelated Great Vault/B13 changes and existing PreDibs Pylance note are
outside this feature evidence.

## Remaining manual gate

Automated Fengari evidence does not certify Blizzard Retail protected-frame
timing, combat lockdown, RCLootCouncil absence/degradation, or real local
dry-run behavior. T015 remains open pending one-client Retail validation; no
Retail certification is claimed from this record.
