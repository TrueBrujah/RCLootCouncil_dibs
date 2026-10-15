# Quickstart: Data Health Review Center

## Automated checks

From the repository root on Windows:

```powershell
$previousTestFiles = $env:DIBS_TEST_FILES
try {
    $env:DIBS_TEST_FILES = 'tests\contract\health_anomaly_contract_spec.lua;tests\integration\health_dashboard_ui_spec.lua;tests\integration\great_vault_ui_spec.lua'
    npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
    if ($LASTEXITCODE -ne 0) { throw "Fengari failed (exit $LASTEXITCODE)." }
} finally {
    $env:DIBS_TEST_FILES = $previousTestFiles
}
git diff --check
```

Expected outcome: all selected suites pass; export tests show only the health-specific prefix and aggregate finding/source-status data; preview and scanning do not mutate source records.

## Retail validation

Using synthetic/test-guild data only:

1. Log in as a verified Guild Master or Officer and open **Officer > Diagnostics**.
2. Confirm service health and review findings are distinct sections.
3. Exercise a no-findings state and a synthetic unresolved Vault conflict; verify the latter opens the existing Vault review page.
4. Verify a normal player cannot see the findings or trigger preview/export actions.
5. Inspect the generated export in a private test environment and confirm it contains no character or player identity, record ID, raw evidence, or importable package prefix.
6. Repeat navigation and action attempts during combat to confirm no protected UI is invoked.

Do not use production guild personal data for export validation. Record Retail-only checks separately; Fengari does not certify live UI behavior.
