# Quickstart: Backups, Export, Import, and Profiles

## Automated validation

Add fixtures for valid/current/old/future packages, checksum tampering, truncation,
executable-looking text, duplicate transactions, cross-guild scope, and profile isolation.
Run:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" | Sort-Object FullName | ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\", "").Replace("\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx.cmd --yes fengari tests/run.lua
git diff --check
```

## Retail acceptance

1. Create a local backup and verify scope, schema, checksum, size, and retention status.
2. Change a test profile, preview restore, cancel, and confirm that balances and history do
   not change. Restore it and verify the pre-operation snapshot remains available.
3. Create local and guild profiles. Switch, copy, reset, and delete them; verify no ledger
   transaction, permission, season, or guild identity changes.
4. Export configuration-only, guild policy, and full-data packages. Confirm sensitivity
   warnings and that redacted output omits private fields.
5. Import configuration into an empty test scope. Review merge/replace preview and
   confirm only that scope changes. Test full-package reimport on the same populated
   client for deduplication; this does not validate fresh-install canonical recovery.
6. Try malformed, truncated, tampered, future-version, cross-guild, and executable-looking
   packages as player, ML, Officer, and GM; verify authority and rejection messages.
7. Simulate reload, combat, failed apply, changed realm/guild, and RCLootCouncil absent or
   degraded. Verify active data and restore recovery remain usable.
8. Create a local snapshot at setting A, change live state to B, select the snapshot,
   export it and reimport its text through configuration Preview/Apply. Verify the
   package is historical A, integrity metadata is unchanged, preview is read-only,
   and confirmation changes only allowed configuration, never authority or ledger.
9. Test selected full-snapshot sensitive consent, selection reset and role/context
   changes before redisplay. Reject unavailable/unattested/oversized exports without
   live recapture. Use isolated data; this does not validate full canonical recovery.

## Release gate

Selected-snapshot export uses the original retained package, checked against snapshot
attestations and the unchanged portable size limit. Historical configuration text
uses the normal import preview/confirmation path. External snapshot registration
and fresh-install canonical recovery remain T036; ordinary full import refuses
unknown canonical history. Previews retain at most 16 entries
per operation type and expire after 1,800 seconds; recreate before confirmation.

2026-11-15 stabilization evidence: 15 new lifecycle/capture tests pass under Fengari,
Lua 5.4.6 and native Lua 5.1.5; 92 backup/import regressions pass under both native
runtimes. Independent QA passes 93 tests under Lua 5.4.6 across data, UI and profiles.
UI regressions pass 32/32 on all three runtimes; all 108 source files compile under
Lua 5.1.5. Documentation validation/check and diff-check pass. The global pre-fix run
is red (1,785 passed / 138 failed, 254 files); the post-stabilization Lua 5.4.6 run is also red
(1,811 passed / 134 failed, 257 files). Four prior profile/Officer-button failures
are resolved, and comparison found no added failure names. Targeted results are
not a full-suite or Retail certification. These global counts precede the historical
export slice and are its baseline, not a full-suite rerun on its final source.

Historical export evidence: 19/19 service tests and a 29/29 UI/backup regression group
pass under Fengari, Lua 5.4.6 and native Lua 5.1.5. Independent QA passes 45/45 under
Lua 5.4.6 and Lua 5.1.5 (historical service/UI, scope isolation and canonical backup).
The final service test verifies byte-exact cached text rejection after valid same-ID
package substitution. All 108 sources compile under Lua 5.1.5. Retail steps 8–9 and
the user checklist D07/D08 remain unexecuted. T027 and T036 stay open.

## Compressed transport follow-up

Export APIs retain legacy raw output by default; `compressed=true` selects the
versioned `DIBS-COMP-1` wrapper. DataUI prefers it when checked native capabilities or
the unchanged bundled LibDeflate are available; otherwise it explains legacy fallback.
Imports auto-detect both formats. The 250,000-character cap applies to encoded text;
preflight verifies actual raw DEFLATE expansion against its declared length and the
existing 32 MiB budget before calling a decompressor. All inner package validation,
scope and canonical refusal remains active. Local restore does not depend on the
optional transport codec.

Measured outside WoW under Lua 5.4.6 with the real bundled LibDeflate: a local sample
went from 288 raw bytes to 281 encoded characters; a full synthetic 2,000-row history
went from 288,412 bytes to 30,412 encoded characters. These are sample sizes, not a
general compression ratio or Retail performance measurement. No private data used.
Test D09/D10 in the existing Retail checklist; native C_EncodingUtil, UI layout,
LibStub coexistence and live-client timing remain unvalidated until then.

Final compressed-slice validation: **84/84 across 10 suites under Fengari, Lua 5.4.6
and native Lua 5.1.5**; independent QA **66/66 under both native runtimes**, plus three
additional malformed-stream probes rejected before a decoder call. Compilation
**109/109 Lua sources under Lua 5.1**, documentation Generate/Check and diff-check pass.
The first Fengari run exposed the old library's double-number assumption; its isolated
test environment now preserves Lua 5.1 floating-byte semantics. No vendor/global
production code changed; independent Node fixtures still verify the actual bytes.
The historical 1,811/134 global baseline is unchanged evidence, not a new full-suite run.

Add migration, retention, privacy, and package-format documentation plus a dated changelog
and version increment before shipping.
