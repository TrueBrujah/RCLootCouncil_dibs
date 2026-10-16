# Contributing

Read the relevant specification and implementation before editing. Keep the source of truth in the owning domain module; UI code should project data and delegate mutations. Preserve public APIs, persisted keys, protocol fields, and compatibility aliases unless a migration is designed first.

For a behavior change:

1. Identify the applicable `DIBS-RULE-*` identifier and update its traceability entry.
2. Update LuaCATS types and function documentation at the boundary.
3. Add or adjust focused tests, including permission/combat/compatibility cases.
4. Run the smallest relevant suites using explicit `DIBS_TEST_FILES` on Windows,
   then `git diff --check`; see [testing.md](testing.md) for the environment-safe
   wrapper. Do not rely on implicit full-suite discovery on Windows.
5. Update affected developer references and both French/English player and
   GM/Officer guides when workflows change. Review screenshot inventories too.
6. Add a dated changelog note; shipped addon changes require a TOC version
   increment. Documentation-only changes may retain the addon version.

For a documentation-only change, verify every claim against `src/` and tests. Avoid comments that restate syntax. Mention manual Retail checks separately from automated validation. Keep embedded library code out of Dibs naming and rule inventories unless the integration contract requires it.
Check local links and generated reference freshness as described in
[testing.md](testing.md#documentation-only-validation); no addon test run or
packaging is required. Distinguish published downloads, local source changes,
and historical evidence. Never advertise an unpublished ZIP as stable. Avoid comments that restate syntax. Mention manual Retail checks separately from automated validation. Keep embedded library code out of Dibs naming and rule inventories unless the integration contract requires it.
