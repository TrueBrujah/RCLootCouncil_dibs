# Naming conventions

The project uses the following convention for new code:

- Lua files use PascalCase for first-party modules (`CharacterEligibility.lua`, `RCLootCouncil.lua`); directory names are lowercase.
- The single public namespace is `Dibs`; module tables are `Dibs.<ModuleName>`. `Dibs.CoreAPI` is the stable application facade.
- Public functions use PascalCase (`GetBalance`, `CreateSeason`). Historical lower-camel `CoreAPI` methods (`createSeason`, `setActiveSeason`) remain stable because callers may depend on them.
- Local variables and private helpers use lowerCamelCase. Constants use upper snake case (`MAX_CHUNKS`).
- Blizzard event names, Ace messages, sync message types, and protocol prefixes use uppercase (`PLAYER_LOGIN`, `RCMLAwardSuccess`, `REQUEST`, `DIBS`).
- Database fields and serialized keys use lowerCamelCase. IDs are opaque strings; timestamps are Unix seconds and must never be replaced by `0` when a source timestamp exists.
- LuaLS aliases/classes use PascalCase with a `Dibs` prefix (`DibsTransaction`, `DibsPreDibRequest`).
- Tests use descriptive `*_spec.lua` files and `*_fixture` helpers; test doubles must not leak into runtime code.

Existing public and persisted identifiers are compatibility surfaces. Before changing one, search callers and SavedVariables, add a migration/alias, bump the relevant schema, and add a regression test. `Dibs.Eligibility` is a documented compatibility alias for `Dibs.CharacterEligibility`.
