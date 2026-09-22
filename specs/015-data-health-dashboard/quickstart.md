# Quickstart: Data Health Dashboard

## Focused automated validation

```powershell
$env:DIBS_TEST_FILES = "tests/contract/health_dashboard_contract_spec.lua;tests/integration/health_dashboard_ui_spec.lua;tests/integration/toc_load_spec.lua"
npx.cmd --yes fengari tests/run.lua
Remove-Item Env:DIBS_TEST_FILES -ErrorAction SilentlyContinue
```

## Manual Retail validation

1. Open Diagnostics as a guild GM and Officer.
2. Confirm version, schema, persistence, readiness, RCLootCouncil, sync, and backup checks are visible.
3. Disable or omit RCLootCouncil and confirm the state is explicitly unavailable, not ready.
4. Enter combat, refresh/reopen the page, and confirm no protected-frame or lifecycle error occurs.
5. Open Diagnostics as a normal player and confirm the administrative health report is unavailable.
6. Confirm the existing debug report remains available and no repair action is exposed by the health dashboard.

Automated Fengari evidence does not certify Retail protected frames, combat lockdown, or real optional-addon timing.
