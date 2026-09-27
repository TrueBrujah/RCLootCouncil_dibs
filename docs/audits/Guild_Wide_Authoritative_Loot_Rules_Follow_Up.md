# Follow-Up: Guild-Wide Authoritative Loot Rules

Status: Implemented in the 0.7.0 development worktree. Retail multi-client
validation remains open; see
[Guild-Wide Loot Rules Implementation](Guild_Wide_Loot_Rules_Implementation.md).

## Current Model

Guild Loot Rules are stored as the versioned
`SEASON_CATALOG.guildConfiguration.guildLootRules` snapshot. They remain
separate from `OperationalPolicy`; their GM-only adoption/publication, local
draft preservation, shared consumers, and readiness projection are described
in the implementation audit. Do not reopen this deferred design unless the
catalog contract changes.

## Future Scope

The implemented design satisfies the previously deferred scope:

- normalized schema-v1 values in the existing revisioned season catalog;
- explicit Guild Master adoption/publication and Officer read-only use;
- bounded SyncV2 delivery, catalog validation, hashing, and recovery;
- preserved local settings and no implicit Officer migration;
- existing root SavedVariables schema with 0.7.x compatibility enforcement;
- six distinguishable readiness states and remediation.

## Acceptance Criteria

- Local edits do not become authoritative without explicit authorized adoption.
- Clients converge on the same adopted policy or expose conflicts without
  silently overwriting local or guild state.
- Older peers and mixed addon versions fail safely and report unsupported state.
- Readiness distinguishes unavailable controls, invalid local settings,
  configured local settings, and adopted guild-wide rules.

No Rank Rules behavior was changed. The final release outcome remains `NOT
READY` until the manual Retail gate is completed.
