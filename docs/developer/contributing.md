# Contributing

Read the relevant specification and implementation before editing. Keep the source of truth in the owning domain module; UI code should project data and delegate mutations. Preserve public APIs, persisted keys, protocol fields, and compatibility aliases unless a migration is designed first.

For a behavior change:

1. Identify the applicable `DIBS-RULE-*` identifier and update its traceability entry.
2. Update LuaCATS types and function documentation at the boundary.
3. Add or adjust focused tests, including permission/combat/compatibility cases.
4. Run `npx.cmd --yes fengari tests/run.lua` and `git diff --check`.
5. Update the developer, officer, or player guide when user-visible behavior changes.

For a documentation-only change, verify every claim against `src/` and tests. Avoid comments that restate syntax. Mention manual Retail checks separately from automated validation. Keep embedded library code out of Dibs naming and rule inventories unless the integration contract requires it.
